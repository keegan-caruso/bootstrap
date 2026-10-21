import assert from "node:assert/strict";
import test from "node:test";
import {
    commitMatches,
    normalizeOrganization,
    parsePullRequestUrl,
    requireNonEmptyString,
    resolvePullRequest,
    validateCommitId,
} from "./validation.mjs";

test("parsePullRequestUrl parses a dev.azure.com URL", () => {
    const result = parsePullRequestUrl(
        "https://dev.azure.com/my-org/My%20Project/_git/my-repo/pullrequest/42",
    );
    assert.deepEqual(result, {
        organization: "my-org",
        project: "My Project",
        repository: "my-repo",
        pullRequestId: 42,
    });
});

test("parsePullRequestUrl parses a *.visualstudio.com URL", () => {
    const result = parsePullRequestUrl(
        "https://my-org.visualstudio.com/My-Project/_git/my-repo/pullrequest/7",
    );
    assert.equal(result.organization, "my-org");
    assert.equal(result.pullRequestId, 7);
});

test("parsePullRequestUrl preserves literal and encoded plus characters", () => {
    for (const repository of ["repo+tools", "repo%2Btools"]) {
        assert.equal(
            parsePullRequestUrl(`https://dev.azure.com/org/project/_git/${repository}/pullrequest/1`).repository,
            "repo+tools",
        );
    }
});

test("parsePullRequestUrl rejects malformed URLs", () => {
    assert.throws(() => parsePullRequestUrl("not a url"), /valid Azure DevOps URL/);
    assert.throws(
        () => parsePullRequestUrl("https://dev.azure.com/org/proj/_git/repo"),
        /must look like/,
    );
    assert.throws(
        () => parsePullRequestUrl("https://example.com/org/proj/_git/repo/pullrequest/1"),
        /dev\.azure\.com or visualstudio\.com/,
    );
});

test("normalizeOrganization accepts a bare name or a URL", () => {
    assert.equal(normalizeOrganization("my-org"), "my-org");
    assert.equal(normalizeOrganization("my-org/"), "my-org");
    assert.equal(normalizeOrganization("https://dev.azure.com/my-org/"), "my-org");
    assert.equal(normalizeOrganization("https://my-org.visualstudio.com"), "my-org");
    assert.throws(() => normalizeOrganization("https://example.com/my-org"), /organization must be/);
});

test("resolvePullRequest prefers pullRequestUrl when present", () => {
    const result = resolvePullRequest({
        pullRequestUrl: "https://dev.azure.com/org/proj/_git/repo/pullrequest/5",
        organization: "ignored",
    });
    assert.equal(result.organization, "org");
    assert.equal(result.pullRequestId, 5);
});

test("resolvePullRequest requires all explicit fields without a URL", () => {
    assert.throws(
        () => resolvePullRequest({ organization: "org", project: "proj" }),
        /Missing: repository, pullRequestId/,
    );
    const result = resolvePullRequest({
        organization: "org",
        project: "proj",
        repository: "repo",
        pullRequestId: "9",
    });
    assert.equal(result.pullRequestId, 9);
});

test("validateCommitId enforces hex length bounds", () => {
    assert.equal(validateCommitId("abc1234"), "abc1234");
    assert.throws(() => validateCommitId("xyz"), /7 to 64 hexadecimal characters/);
});

test("commitMatches is a case-insensitive prefix match", () => {
    assert.equal(commitMatches("ABCDEF1234567890", "abcdef"), true);
    assert.equal(commitMatches("123", "abcdef"), false);
    assert.equal(commitMatches(undefined, "abcdef"), false);
});

test("requireNonEmptyString trims and rejects blanks", () => {
    assert.equal(requireNonEmptyString("  value  ", "field"), "value");
    assert.throws(() => requireNonEmptyString("   ", "field"), /field must be a non-empty string/);
    assert.throws(() => requireNonEmptyString(undefined, "field"), /field must be a non-empty string/);
});
