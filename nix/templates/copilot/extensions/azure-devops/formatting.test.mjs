import assert from "node:assert/strict";
import test from "node:test";
import {
    gitApiUrl,
    identity,
    pullRequestWebUrl,
    simplifyComment,
    simplifyThread,
} from "./formatting.mjs";

test("identity returns null for falsy input and maps known fields", () => {
    assert.equal(identity(null), null);
    assert.deepEqual(
        identity({ id: "1", displayName: "Alice", uniqueName: "alice@example.com", url: "u", extra: "x" }),
        { id: "1", displayName: "Alice", uniqueName: "alice@example.com", url: "u" },
    );
});

test("simplifyComment defaults optional fields and maps likers", () => {
    const comment = simplifyComment({
        id: 1,
        content: "hello",
        commentType: "text",
        author: { id: "a", displayName: "Alice" },
        usersLiked: [{ id: "b", displayName: "Bob" }],
    });
    assert.equal(comment.parentCommentId, 0);
    assert.equal(comment.isDeleted, false);
    assert.equal(comment.usersLiked[0].displayName, "Bob");
});

test("simplifyThread filters deleted comments unless includeDeleted", () => {
    const thread = {
        id: 10,
        status: "active",
        comments: [
            { id: 1, content: "a", isDeleted: false },
            { id: 2, content: "b", isDeleted: true },
        ],
    };
    assert.equal(simplifyThread(thread, false).comments.length, 1);
    assert.equal(simplifyThread(thread, true).comments.length, 2);
});

test("pullRequestWebUrl encodes path segments", () => {
    const url = pullRequestWebUrl({
        organization: "my org",
        project: "my project",
        repository: "my repo",
        pullRequestId: 5,
    });
    assert.equal(
        url,
        "https://dev.azure.com/my%20org/my%20project/_git/my%20repo/pullrequest/5",
    );
});

test("gitApiUrl builds the encoded repositories API base with a suffix", () => {
    const url = gitApiUrl(
        { organization: "org", project: "proj", repository: "repo" },
        "/pullRequests/5",
    );
    assert.equal(
        url.toString(),
        "https://dev.azure.com/org/proj/_apis/git/repositories/repo/pullRequests/5",
    );
});
