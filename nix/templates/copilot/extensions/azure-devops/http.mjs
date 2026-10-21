// HTTP access to the Azure DevOps REST API: bounded timeouts, retries for
// transient failures on idempotent (read-only) requests, and shared JSON
// response handling.
//
// Mutations (POST/PATCH/PUT/DELETE) are never retried automatically - retrying
// a non-idempotent request risks double-creating a pull request or duplicating
// a side effect if the first attempt actually succeeded server-side but the
// response was lost. Callers that need to retry a mutation must do so
// explicitly and idempotently at a higher layer; this module will not do it
// for them.

import { setTimeout as sleep } from "node:timers/promises";

const idempotentMethods = new Set(["GET", "HEAD"]);

// Longer than a typical Azure DevOps REST call, but still bounded: build and
// policy-evaluation endpoints in particular can be slow under load.
export const requestTimeoutMs = 60_000;
export const maxRetryAttempts = 3;
export const retryBaseDelayMs = 500;
export const maxErrorBodyCharacters = 4_000;
// Azure DevOps (and any proxy in front of it) may return a `Retry-After`
// header on 429/5xx responses. We honor it - servers know their own load
// better than a fixed backoff schedule does - but always bound it so a
// misbehaving or malicious response cannot stall a tool call indefinitely.
export const maxRetryAfterMs = 30_000;

function methodOf(options) {
    return String(options?.method ?? "GET").toUpperCase();
}

/** Whether retrying this request cannot cause a duplicate side effect. */
export function isIdempotentRequest(options) {
    return idempotentMethods.has(methodOf(options));
}

function isRetryableStatus(status) {
    return status === 408 || status === 429 || (status >= 500 && status <= 599);
}

function isRetryableNetworkError(error) {
    if (error?.name === "AbortError" || error?.name === "TimeoutError") {
        return true;
    }
    const code = error?.cause?.code ?? error?.code;
    return ["ECONNRESET", "ETIMEDOUT", "EAI_AGAIN", "ECONNREFUSED", "EPIPE"].includes(
        code,
    );
}

/**
 * Parses a `Retry-After` header value (either delay-seconds or an HTTP-date)
 * into a millisecond delay, bounded to `[0, boundMs]`. Returns `null` when
 * the header is absent or unparseable, so callers fall back to their own
 * backoff schedule.
 */
export function parseRetryAfterMs(headerValue, boundMs = maxRetryAfterMs) {
    if (!headerValue) {
        return null;
    }
    const trimmed = String(headerValue).trim();

    let delayMs;
    if (/^\d+$/.test(trimmed)) {
        delayMs = Number(trimmed) * 1000;
    } else {
        const dateMs = Date.parse(trimmed);
        if (Number.isNaN(dateMs)) {
            return null;
        }
        delayMs = dateMs - Date.now();
    }

    if (!Number.isFinite(delayMs)) {
        return null;
    }
    return Math.min(Math.max(delayMs, 0), boundMs);
}

/**
 * Fetches `endpoint`, retrying transient failures (HTTP 408/429/5xx and
 * common transient network errors, including request timeouts) with
 * exponential backoff - but only when the request method is idempotent.
 * Mutating requests are always attempted exactly once.
 *
 * @param {string|URL} endpoint
 * @param {RequestInit} [options]
 * @param {object} [config]
 * @param {typeof fetch} [config.fetchImpl] injectable for tests.
 * @param {number} [config.timeoutMs]
 * @param {number} [config.attempts] total attempts including the first.
 * @param {number} [config.baseDelayMs] backoff base, injectable for tests.
 * @param {number} [config.maxRetryAfterMs] bound applied to a server-provided
 *   `Retry-After` header, injectable for tests.
 */
export async function fetchWithRetry(endpoint, options = {}, config = {}) {
    const {
        fetchImpl = fetch,
        timeoutMs = requestTimeoutMs,
        attempts = isIdempotentRequest(options) ? maxRetryAttempts : 1,
        baseDelayMs = retryBaseDelayMs,
        maxRetryAfterMs: retryAfterBoundMs = maxRetryAfterMs,
    } = config;

    let lastError;
    for (let attempt = 1; attempt <= attempts; attempt += 1) {
        options.signal?.throwIfAborted();
        const isLastAttempt = attempt === attempts;
        try {
            const response = await fetchImpl(endpoint, {
                ...options,
                signal: AbortSignal.any([
                    AbortSignal.timeout(timeoutMs),
                    ...(options.signal ? [options.signal] : []),
                ]),
            });
            if (!isLastAttempt && isRetryableStatus(response.status)) {
                const retryAfterMs = parseRetryAfterMs(
                    response.headers?.get?.("retry-after"),
                    retryAfterBoundMs,
                );
                await response.body?.cancel?.();
                lastError = new Error(`HTTP ${response.status} ${response.statusText}`);
                await sleep(retryAfterMs ?? baseDelayMs * 2 ** (attempt - 1), undefined, {
                    signal: options.signal,
                });
                continue;
            }
            return response;
        } catch (error) {
            options.signal?.throwIfAborted();
            lastError = error;
            if (isLastAttempt || !isRetryableNetworkError(error)) {
                throw error;
            }
            await sleep(baseDelayMs * 2 ** (attempt - 1), undefined, { signal: options.signal });
        }
    }
    throw lastError;
}

/** Reads and truncates a response body for inclusion in an error message. */
async function readErrorBody(response) {
    try {
        return (await response.text()).slice(0, maxErrorBodyCharacters);
    } catch {
        return "";
    }
}

/**
 * Fetches JSON from the Azure DevOps REST API with the shared authorization
 * header, bounded timeout, and (for read-only requests) automatic retry.
 * Returns both the parsed body and the raw `Response`, so callers that need
 * a response header (for example an `ETag` for optimistic concurrency) do
 * not have to issue a second request.
 */
export async function fetchJsonResponse(endpoint, authorization, description, options = {}, config = {}) {
    let response;
    try {
        response = await fetchWithRetry(
            endpoint,
            {
                ...options,
                headers: {
                    Accept: "application/json",
                    Authorization: authorization,
                    ...options.headers,
                },
            },
            config,
        );
    } catch (error) {
        options.signal?.throwIfAborted();
        throw new Error(
            `${description} failed: ${error instanceof Error ? error.message : String(error)}`,
        );
    }

    if (!response.ok) {
        const body = await readErrorBody(response);
        throw new Error(
            `${description} returned HTTP ${response.status} ${response.statusText}. ${body}`,
        );
    }

    return { data: await response.json(), response };
}

/**
 * Fetches JSON from the Azure DevOps REST API with the shared authorization
 * header, bounded timeout, and (for read-only requests) automatic retry.
 */
export async function fetchJson(endpoint, authorization, description, options = {}, config = {}) {
    const { data } = await fetchJsonResponse(endpoint, authorization, description, options, config);
    return data;
}
