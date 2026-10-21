import assert from "node:assert/strict";
import { setTimeout as delay } from "node:timers/promises";
import test from "node:test";
import { azureDevOpsAuthorizationValue } from "./auth.mjs";
import { getPullRequestComments, resolvePullRequestComments } from "./comments.mjs";
import { fetchWithRetry } from "./http.mjs";
import { getPullRequestReviewState } from "./review-state.mjs";

const args = { organization: "org", project: "project", repository: "repo", pullRequestId: 1 };

test("cancelled PR operations do not acquire credentials", async () => {
    const signal = AbortSignal.abort();
    for (const operation of [getPullRequestComments, resolvePullRequestComments, getPullRequestReviewState]) {
        await assert.rejects(
            operation(args, () => assert.fail("authentication must not start"), { signal }),
            { name: "AbortError" },
        );
    }
});

test("AzureAuth receives cancellation and does not start for an aborted call", async () => {
    const controller = new AbortController();
    await azureDevOpsAuthorizationValue(async (_file, _args, options) => {
        assert.equal(options.signal, controller.signal);
        return { stdout: "Bearer test-header" };
    }, { signal: controller.signal });
    controller.abort();
    await assert.rejects(
        azureDevOpsAuthorizationValue(() => assert.fail("process must not start"), { signal: controller.signal }),
        { name: "AbortError" },
    );
});

test("request timeouts remain active when a caller supplies a cancellation signal", async () => {
    await assert.rejects(
        fetchWithRetry("https://dev.azure.com/test", { signal: new AbortController().signal }, {
            attempts: 1,
            timeoutMs: 10,
            fetchImpl: async (_url, { signal }) => {
                await delay(30);
                signal.throwIfAborted();
                assert.fail("request timeout was disabled");
            },
        }),
        { name: "TimeoutError" },
    );
});

test("cancelling a retry delay prevents another request", async () => {
    const controller = new AbortController();
    let requests = 0;
    await assert.rejects(
        fetchWithRetry("https://dev.azure.com/test", { signal: controller.signal }, {
            fetchImpl: async () => {
                requests += 1;
                return {
                    status: 503,
                    headers: { get: () => "30" },
                    body: { cancel: async () => controller.abort() },
                };
            },
        }),
        { name: "AbortError" },
    );
    assert.equal(requests, 1);
});

test("cancelling after one resolved thread prevents subsequent mutations and preserves progress", async (t) => {
    const controller = new AbortController();
    const patched = [];
    t.mock.method(globalThis, "fetch", async (url, options) => {
        const id = Number(url.pathname.split("/").at(-1));
        if (options.method === "PATCH") {
            patched.push(id);
            controller.abort();
            return Response.json({ id, status: "fixed", comments: [] });
        }
        if (url.pathname.endsWith("/threads")) {
            return Response.json({ value: [1, 2].map(id => ({ id, status: "active", comments: [] })) });
        }
        return Response.json({ id, status: "active", comments: [] });
    });

    await assert.rejects(
        resolvePullRequestComments({ ...args, threadIds: [1, 2] }, async () => "Bearer test-header", {
            signal: controller.signal,
        }),
        error => {
            assert.deepEqual(error.details.resolvedThreadIds, [1]);
            assert.equal(error.details.failedThreadId, 2);
            return true;
        },
    );
    assert.deepEqual(patched, [1]);
});
