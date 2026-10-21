import assert from "node:assert/strict";
import test from "node:test";
import { jsonResponse } from "./test-support.mjs";
import {
    fetchJson,
    fetchJsonResponse,
    fetchWithRetry,
    isIdempotentRequest,
    parseRetryAfterMs,
} from "./http.mjs";

test("isIdempotentRequest treats GET/HEAD (and the default) as retryable", () => {
    assert.equal(isIdempotentRequest({}), true);
    assert.equal(isIdempotentRequest({ method: "get" }), true);
    assert.equal(isIdempotentRequest({ method: "HEAD" }), true);
    assert.equal(isIdempotentRequest({ method: "POST" }), false);
    assert.equal(isIdempotentRequest({ method: "PATCH" }), false);
    assert.equal(isIdempotentRequest({ method: "DELETE" }), false);
});

for (const attempts of [2, 3]) {
    test(`fetchWithRetry succeeds on attempt ${attempts} with backoff when Retry-After is absent`, async () => {
        let calls = 0;
        const fetchImpl = async () => {
            calls += 1;
            if (calls < attempts) {
                return jsonResponse(503, "unavailable");
            }
            return jsonResponse(200, { ok: true });
        };

        const response = await fetchWithRetry(
            "https://example.test/",
            {},
            { fetchImpl, attempts, baseDelayMs: 0 },
        );
        assert.equal(calls, attempts);
        assert.equal(response.status, 200);
    });
}

test("fetchWithRetry gives up after the configured attempt count", async () => {
    let calls = 0;
    const fetchImpl = async () => {
        calls += 1;
        return jsonResponse(500, "still down");
    };

    const response = await fetchWithRetry(
        "https://example.test/",
        {},
        { fetchImpl, attempts: 3, baseDelayMs: 0 },
    );
    assert.equal(calls, 3);
    assert.equal(response.status, 500);
});

test("fetchWithRetry never retries a POST even on a transient status", async () => {
    let calls = 0;
    const fetchImpl = async () => {
        calls += 1;
        return jsonResponse(503, "unavailable");
    };

    const response = await fetchWithRetry(
        "https://example.test/",
        { method: "POST" },
        { fetchImpl, baseDelayMs: 0 },
    );
    assert.equal(calls, 1);
    assert.equal(response.status, 503);
});

test("fetchWithRetry retries transient network errors (e.g. timeouts) for GET", async () => {
    let calls = 0;
    const fetchImpl = async () => {
        calls += 1;
        if (calls < 2) {
            const error = new Error("aborted");
            error.name = "AbortError";
            throw error;
        }
        return jsonResponse(200, { ok: true });
    };

    const response = await fetchWithRetry(
        "https://example.test/",
        {},
        { fetchImpl, attempts: 3, baseDelayMs: 0 },
    );
    assert.equal(calls, 2);
    assert.equal(response.status, 200);
});

test("fetchWithRetry does not retry a PATCH after a network error", async () => {
    let calls = 0;
    const fetchImpl = async () => {
        calls += 1;
        const error = new Error("reset");
        error.code = "ECONNRESET";
        throw error;
    };

    await assert.rejects(
        fetchWithRetry("https://example.test/", { method: "PATCH" }, { fetchImpl, baseDelayMs: 0 }),
        /reset/,
    );
    assert.equal(calls, 1);
});

test("parseRetryAfterMs converts delay-seconds to milliseconds", () => {
    assert.equal(parseRetryAfterMs("2"), 2000);
    assert.equal(parseRetryAfterMs("0"), 0);
});

test("parseRetryAfterMs converts an HTTP-date to a millisecond delay", () => {
    const future = new Date(Date.now() + 5000).toUTCString();
    const delayMs = parseRetryAfterMs(future);
    // Allow slack for the time elapsed formatting/parsing the date above.
    assert.ok(delayMs > 4000 && delayMs <= 5000, `expected ~5000ms, got ${delayMs}`);
});

test("parseRetryAfterMs bounds an overly large delay to the configured cap", () => {
    assert.equal(parseRetryAfterMs("3600", 1000), 1000);
});

test("parseRetryAfterMs returns null for a missing or unparseable header", () => {
    assert.equal(parseRetryAfterMs(null), null);
    assert.equal(parseRetryAfterMs(""), null);
    assert.equal(parseRetryAfterMs("not-a-valid-value"), null);
});

test("fetchWithRetry honors a bounded Retry-After header instead of waiting out an unbounded value", async () => {
    let calls = 0;
    const fetchImpl = async () => {
        calls += 1;
        if (calls === 1) {
            // The server asks for a 100-second delay; a real implementation
            // must bound this so a single misbehaving response cannot stall
            // the tool call for minutes.
            return jsonResponse(429, "slow down", { "retry-after": "100" });
        }
        return jsonResponse(200, { ok: true });
    };

    const startedAt = Date.now();
    const response = await fetchWithRetry(
        "https://example.test/",
        {},
        { fetchImpl, attempts: 2, baseDelayMs: 60_000, maxRetryAfterMs: 20 },
    );
    const elapsedMs = Date.now() - startedAt;
    assert.equal(calls, 2);
    assert.equal(response.status, 200);
    assert.ok(elapsedMs < 2000, `expected the bounded Retry-After (~20ms) to be honored, took ${elapsedMs}ms`);
});

test("fetchJson resolves parsed JSON on success", async () => {
    const fetchImpl = async () => jsonResponse(200, { value: [1, 2, 3] });
    const result = await fetchJson(
        "https://example.test/",
        "Bearer token",
        "test request",
        {},
        { fetchImpl, baseDelayMs: 0 },
    );
    assert.deepEqual(result, { value: [1, 2, 3] });
});

test("fetchJsonResponse exposes both the parsed body and the raw response (e.g. for reading an ETag)", async () => {
    const fetchImpl = async () => jsonResponse(200, { id: 1 }, { etag: '"9"' });
    const { data, response } = await fetchJsonResponse(
        "https://example.test/",
        "******",
        "test request",
        {},
        { fetchImpl, baseDelayMs: 0 },
    );
    assert.deepEqual(data, { id: 1 });
    assert.equal(response.headers.get("etag"), '"9"');
});

test("fetchJson raises a descriptive error including the truncated body on failure", async () => {
    const fetchImpl = async () => jsonResponse(404, "not found detail");
    await assert.rejects(
        fetchJson("https://example.test/", "Bearer token", "test request", {}, { fetchImpl, attempts: 1, baseDelayMs: 0 }),
        /test request returned HTTP 404 status-404\. not found detail/,
    );
});

test("fetchJson sends the Authorization header verbatim", async () => {
    let seenAuthorization;
    const fetchImpl = async (_url, options) => {
        seenAuthorization = options.headers.Authorization;
        return jsonResponse(200, {});
    };
    await fetchJson("https://example.test/", "Bearer abc123", "test request", {}, { fetchImpl, baseDelayMs: 0 });
    assert.equal(seenAuthorization, "Bearer abc123");
});
