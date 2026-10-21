import assert from "node:assert/strict";
import test from "node:test";
import { getPullRequestSnapshot } from "./pull-request.mjs";
import { jsonResponse } from "./test-support.mjs";

const pullRequest = {
    organization: "org",
    project: "proj",
    repository: "repo",
    pullRequestId: 5,
};

test("getPullRequestSnapshot picks the latest iteration when no commitId is given", async (t) => {
    t.mock.method(globalThis, "fetch", async (url) => {
        if (url.toString().includes("/iterations")) {
            return jsonResponse(200, {
                value: [
                    {
                        id: 1,
                        sourceRefCommit: { commitId: "a".repeat(40) },
                        targetRefCommit: { commitId: "b".repeat(40) },
                    },
                    {
                        id: 2,
                        sourceRefCommit: { commitId: "c".repeat(40) },
                        targetRefCommit: { commitId: "d".repeat(40) },
                        commonRefCommit: { commitId: "e".repeat(40) },
                    },
                ],
            });
        }
        return jsonResponse(200, { title: "PR title" });
    });

    const snapshot = await getPullRequestSnapshot(
        pullRequest,
        "******",
        undefined,
    );
    assert.equal(snapshot.commitScope.iterationId, 2);
    assert.equal(snapshot.commitScope.sourceCommitId, "c".repeat(40));
    assert.equal(snapshot.commitScope.commonCommitId, "e".repeat(40));
});

test("getPullRequestSnapshot throws when the pull request has no iterations", async (t) => {
    t.mock.method(globalThis, "fetch", async (url) => {
        if (url.toString().includes("/iterations")) {
            return jsonResponse(200, { value: [] });
        }
        return jsonResponse(200, { title: "PR title" });
    });

    await assert.rejects(
        getPullRequestSnapshot(pullRequest, "******", undefined),
        /does not contain any iterations/,
    );
});
