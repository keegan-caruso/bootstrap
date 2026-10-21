import assert from "node:assert/strict";
import test from "node:test";
import { getPullRequestReviewState } from "./review-state.mjs";
import { jsonResponse } from "./test-support.mjs";

const fakeAuth = async () => "Bearer test-token";
const commitId = "a".repeat(40);

function baseArgs() {
    return { organization: "org", project: "proj", repository: "repo", pullRequestId: 5 };
}

test("getPullRequestReviewState aggregates threads and blocking policy counts", async (t) => {
    t.mock.method(globalThis, "fetch", async (url) => {
        const href = url.toString();
        if (href.includes("/iterations")) {
            return jsonResponse(200, {
                value: [
                    {
                        id: 1,
                        sourceRefCommit: { commitId },
                        targetRefCommit: { commitId: "b".repeat(40) },
                        commonRefCommit: { commitId: "c".repeat(40) },
                    },
                ],
            });
        }
        if (href.includes("/threads")) {
            return jsonResponse(200, {
                value: [
                    {
                        id: 10,
                        status: "active",
                        isDeleted: false,
                        comments: [{ id: 1, content: "please fix", publishedDate: "2024-01-01" }],
                    },
                    { id: 11, status: "fixed", isDeleted: false, comments: [] },
                ],
            });
        }
        if (href.includes("/policy/evaluations")) {
            return jsonResponse(200, {
                value: [
                    {
                        configuration: { id: 1, isBlocking: true, isEnabled: true, type: { displayName: "Build" } },
                        context: {},
                        status: "rejected",
                    },
                ],
            });
        }
        // Pull request details (no distinguishing path segment beyond repositories root).
        return jsonResponse(200, {
            title: "PR title",
            lastMergeSourceCommit: { commitId },
            repository: { project: { id: "proj-id" } },
        });
    });

    const result = JSON.parse(await getPullRequestReviewState(baseArgs(), fakeAuth));
    assert.equal(result.reviewThreads.activeCount, 1);
    assert.equal(result.reviewThreads.active[0].id, 10);
    assert.equal(result.policies.blockingCount, 1);
    assert.equal(result.policies.hasFailedBlockingPolicies, true);
    assert.equal(result.policies.hasPendingBlockingPolicies, false);
});

test("getPullRequestReviewState rejects when the pull request head changes during aggregation", async (t) => {
    let prDetailsCalls = 0;
    t.mock.method(globalThis, "fetch", async (url) => {
        const href = url.toString();
        if (href.includes("/iterations")) {
            return jsonResponse(200, {
                value: [{ id: 1, sourceRefCommit: { commitId }, targetRefCommit: { commitId: "b".repeat(40) } }],
            });
        }
        if (href.includes("/threads")) {
            return jsonResponse(200, { value: [] });
        }
        if (href.includes("/policy/evaluations")) {
            return jsonResponse(200, { value: [] });
        }
        // Pull request details: called once for the initial snapshot, and
        // again for the post-aggregation recheck. Simulate a push landing
        // in between by returning a different head commit the second time.
        prDetailsCalls += 1;
        const headCommitId = prDetailsCalls === 1 ? commitId : "e".repeat(40);
        return jsonResponse(200, {
            title: "PR title",
            lastMergeSourceCommit: { commitId: headCommitId },
            repository: { project: { id: "proj-id" } },
        });
    });

    await assert.rejects(
        getPullRequestReviewState(baseArgs(), fakeAuth),
        /Pull request head changed while collecting review state/,
    );
    assert.equal(prDetailsCalls, 2);
});

test("getPullRequestReviewState rejects a stale requested commit", async (t) => {
    t.mock.method(globalThis, "fetch", async (url) => {
        const href = url.toString();
        if (href.includes("/iterations")) {
            return jsonResponse(200, {
                value: [{ id: 1, sourceRefCommit: { commitId }, targetRefCommit: { commitId: "b".repeat(40) } }],
            });
        }
        return jsonResponse(200, {
            title: "PR title",
            lastMergeSourceCommit: { commitId: "d".repeat(40) },
        });
    });

    await assert.rejects(
        getPullRequestReviewState({ ...baseArgs(), commitId }, fakeAuth),
        /only available for the current head/,
    );
});
