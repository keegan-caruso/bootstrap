import assert from "node:assert/strict";
import test from "node:test";
import { getPullRequestComments, resolveCommitScope, resolvePullRequestComments } from "./comments.mjs";
import { jsonResponse } from "./test-support.mjs";

const pullRequest = { organization: "org", project: "proj", repository: "repo", pullRequestId: 5 };

test("resolveCommitScope returns null when no commitId is requested", async () => {
    const result = await resolveCommitScope(pullRequest, "Bearer token", undefined);
    assert.equal(result, null);
});

test("resolveCommitScope rejects a malformed commitId before making any request", async (t) => {
    let calls = 0;
    t.mock.method(globalThis, "fetch", async () => {
        calls += 1;
        throw new Error("should not be called");
    });
    await assert.rejects(
        resolveCommitScope(pullRequest, "Bearer token", "not-hex!"),
        /7 to 64 hexadecimal characters/,
    );
    assert.equal(calls, 0);
});

test("resolveCommitScope matches a single iteration by commit prefix", async (t) => {
    t.mock.method(globalThis, "fetch", async () =>
        jsonResponse(200, {
            value: [
                { id: 1, sourceRefCommit: { commitId: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } },
                { id: 2, sourceRefCommit: { commitId: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" } },
            ],
        }),
    );
    const result = await resolveCommitScope(pullRequest, "Bearer token", "bbbbbbb");
    assert.equal(result.iterationId, 2);
});

test("resolveCommitScope throws when a commit maps to multiple iterations", async (t) => {
    t.mock.method(globalThis, "fetch", async () =>
        jsonResponse(200, {
            value: [
                { id: 1, commits: [{ commitId: "cccccccccccccccccccccccccccccccccccccccc" }] },
                { id: 2, sourceRefCommit: { commitId: "cccccccccccccccccccccccccccccccccccccccc" } },
            ],
        }),
    );
    await assert.rejects(
        resolveCommitScope(pullRequest, "Bearer token", "ccccccc"),
        /maps to multiple pull request iterations/,
    );
});

test("resolveCommitScope retries a transient failure (read-only GET)", async (t) => {
    let calls = 0;
    t.mock.method(globalThis, "fetch", async () => {
        calls += 1;
        if (calls === 1) {
            return jsonResponse(503, "unavailable");
        }
        return jsonResponse(200, {
            value: [{ id: 1, sourceRefCommit: { commitId: "dddddddddddddddddddddddddddddddddddddddd" } }],
        });
    });
    const result = await resolveCommitScope(pullRequest, "Bearer token", "ddddddd");
    assert.equal(calls, 2);
    assert.equal(result.iterationId, 1);
});

test("getPullRequestComments filters by status and excludes deleted threads by default", async (t) => {
    t.mock.method(globalThis, "fetch", async () =>
        jsonResponse(200, {
            value: [
                { id: 1, status: "active", isDeleted: false, comments: [{ id: 1, content: "a" }] },
                { id: 2, status: "fixed", isDeleted: false, comments: [{ id: 2, content: "b" }] },
                { id: 3, status: "active", isDeleted: true, comments: [{ id: 3, content: "c" }] },
            ],
        }),
    );
    const result = JSON.parse(
        await getPullRequestComments(
            {
                ...pullRequest,
                status: "active",
            },
            async () => "Bearer test-token",
        ),
    );
    assert.equal(result.threadCount, 1);
    assert.equal(result.threads[0].id, 1);
});

test("getPullRequestComments requests $iteration/$baseIteration=0 and keeps PR-level threads when a commitId is given", async (t) => {
    let threadsUrl;
    t.mock.method(globalThis, "fetch", async (url) => {
        const href = url.toString();
        if (href.includes("/iterations")) {
            return jsonResponse(200, {
                value: [{ id: 2, sourceRefCommit: { commitId: "b".repeat(40) } }],
            });
        }
        threadsUrl = url;
        // Azure DevOps has already mapped both a PR-level thread (no
        // iteration context at all) and an earlier-iteration thread onto the
        // requested iteration; the extension must not filter either out.
        return jsonResponse(200, {
            value: [
                { id: 1, status: "active", isDeleted: false, comments: [], pullRequestThreadContext: null },
                {
                    id: 2,
                    status: "active",
                    isDeleted: false,
                    comments: [],
                    pullRequestThreadContext: { iterationContext: { secondComparingIteration: 1 } },
                },
            ],
        });
    });

    const result = JSON.parse(
        await getPullRequestComments(
            {
                ...pullRequest,
                commitId: "b".repeat(40),
            },
            async () => "Bearer test-token",
        ),
    );

    assert.equal(threadsUrl.searchParams.get("$iteration"), "2");
    assert.equal(threadsUrl.searchParams.get("$baseIteration"), "0");
    assert.equal(threadsUrl.searchParams.has("iteration"), false);
    assert.equal(result.threadCount, 2);
    assert.deepEqual(
        result.threads.map((thread) => thread.id),
        [1, 2],
    );
});

test("resolvePullRequestComments resolves an active thread, re-checking it and forwarding an ETag as If-Match", async (t) => {
    let patchBody;
    let patchHeaders;
    t.mock.method(globalThis, "fetch", async (url, options) => {
        const isSingleThread = url.pathname.endsWith("/threads/1");
        if (options?.method === "PATCH") {
            patchBody = JSON.parse(options.body);
            patchHeaders = options.headers;
            return jsonResponse(200, { id: 1, status: "fixed", comments: [] });
        }
        if (isSingleThread) {
            // The immediate pre-PATCH recheck: still active, and this time
            // Azure DevOps happens to return an ETag we should forward.
            return jsonResponse(200,
                { id: 1, status: "active", isDeleted: false, comments: [] },
                { etag: '"7"' },
            );
        }
        return jsonResponse(200, {
            value: [{ id: 1, status: "active", isDeleted: false, comments: [] }],
        });
    });
    const result = JSON.parse(
        await resolvePullRequestComments(
            {
                ...pullRequest,
                threadIds: [1],
            },
            async () => "Bearer test-token",
        ),
    );
    assert.deepEqual(result.resolvedThreadIds, [1]);
    assert.deepEqual(patchBody, { status: "fixed" });
    assert.equal(patchHeaders["If-Match"], '"7"');
});

test("resolvePullRequestComments refuses to resolve a thread that was deleted between selection and the pre-PATCH recheck", async (t) => {
    let patchCalls = 0;
    t.mock.method(globalThis, "fetch", async (url, options) => {
        const isSingleThread = url.pathname.endsWith("/threads/1");
        if (options?.method === "PATCH") {
            patchCalls += 1;
            return jsonResponse(200, { id: 1, status: "fixed", comments: [] });
        }
        if (isSingleThread) {
            return jsonResponse(200, { id: 1, status: "active", isDeleted: true, comments: [] });
        }
        return jsonResponse(200, {
            value: [{ id: 1, status: "active", isDeleted: false, comments: [] }],
        });
    });

    await assert.rejects(
        resolvePullRequestComments(
            {
                ...pullRequest,
                threadIds: [1],
            },
            async () => "Bearer test-token",
        ),
        (error) => {
            assert.equal(error.name, "ToolFailure");
            assert.match(error.message, /was deleted after it was selected for resolution/);
            assert.deepEqual(error.details, {
                resolvedThreadIds: [],
                failedThreadId: 1,
                remainingThreadIds: [],
            });
            return true;
        },
    );
    assert.equal(patchCalls, 0, "a deleted thread must never be PATCHed");
});

test("resolvePullRequestComments refuses to resolve a thread whose status changed between selection and the pre-PATCH recheck", async (t) => {
    let patchCalls = 0;
    t.mock.method(globalThis, "fetch", async (url, options) => {
        const isSingleThread = url.pathname.endsWith("/threads/1");
        if (options?.method === "PATCH") {
            patchCalls += 1;
            return jsonResponse(200, { id: 1, status: "fixed", comments: [] });
        }
        if (isSingleThread) {
            // Someone else resolved (or otherwise changed) the thread
            // concurrently, between the batch fetch and our recheck.
            return jsonResponse(200, { id: 1, status: "wontFix", isDeleted: false, comments: [] });
        }
        return jsonResponse(200, {
            value: [{ id: 1, status: "active", isDeleted: false, comments: [] }],
        });
    });

    await assert.rejects(
        resolvePullRequestComments(
            {
                ...pullRequest,
                threadIds: [1],
            },
            async () => "Bearer test-token",
        ),
        (error) => {
            assert.equal(error.name, "ToolFailure");
            assert.match(error.message, /no longer active or pending \(now "wontfix"\)/);
            return true;
        },
    );
    assert.equal(patchCalls, 0, "a thread whose status changed concurrently must never be PATCHed");
});

test("resolvePullRequestComments never retries a failing PATCH and reports structured partial progress", async (t) => {
    let patchCalls = 0;
    t.mock.method(globalThis, "fetch", async (url, options) => {
        const isSingleThread = url.pathname.endsWith("/threads/1");
        if (options?.method === "PATCH") {
            patchCalls += 1;
            return jsonResponse(500, "server error");
        }
        if (isSingleThread) {
            return jsonResponse(200, { id: 1, status: "active", isDeleted: false, comments: [] });
        }
        return jsonResponse(200, {
            value: [{ id: 1, status: "active", isDeleted: false, comments: [] }],
        });
    });

    await assert.rejects(
        resolvePullRequestComments(
            {
                ...pullRequest,
                threadIds: [1],
            },
            async () => "Bearer test-token",
        ),
        (error) => {
            assert.equal(error.name, "ToolFailure");
            assert.deepEqual(error.details, {
                resolvedThreadIds: [],
                failedThreadId: 1,
                remainingThreadIds: [],
            });
            return true;
        },
    );
    assert.equal(patchCalls, 1);
});

test("resolvePullRequestComments rejects threads that would overwrite an existing outcome", async (t) => {
    t.mock.method(globalThis, "fetch", async () =>
        jsonResponse(200, {
            value: [{ id: 1, status: "wontFix", isDeleted: false, comments: [] }],
        }),
    );
    await assert.rejects(
        resolvePullRequestComments(
            {
                ...pullRequest,
                threadIds: [1],
            },
            async () => "Bearer test-token",
        ),
        /would overwrite existing outcomes/,
    );
});
