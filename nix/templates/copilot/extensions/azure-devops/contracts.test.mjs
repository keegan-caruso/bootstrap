import assert from "node:assert/strict";
import test from "node:test";
import {
    withCancellation,
    failure,
    guardTool,
    ToolFailure,
    toFailureResult,
    getPullRequestCommentsTool,
    getPullRequestReviewStateTool,
    refreshArtifactsAuthTool,
    resolvePullRequestCommentsTool,
} from "./contracts.mjs";

const allTools = [
    getPullRequestReviewStateTool,
    getPullRequestCommentsTool,
    resolvePullRequestCommentsTool,
    refreshArtifactsAuthTool,
];

test("all four public tool names are present and unique", () => {
    const names = allTools.map((tool) => tool.name);
    assert.deepEqual(
        [...names].sort(),
        [
            "azure_devops_get_pull_request_comments",
            "azure_devops_get_pull_request_review_state",
            "azure_devops_refresh_artifacts_auth",
            "azure_devops_resolve_pull_request_comments",
        ],
    );
});

test("every tool schema rejects unknown properties", () => {
    for (const tool of allTools) {
        assert.equal(
            tool.parameters.additionalProperties,
            false,
            `${tool.name} must declare additionalProperties: false`,
        );
    }
});

test("mutating tools do not opt out of permission prompts implicitly", () => {
    // Resolving threads is a mutation and must NOT set skipPermission: true.
    assert.equal(resolvePullRequestCommentsTool.skipPermission, undefined);
    // Read-only tools are explicitly marked skippable.
    assert.equal(getPullRequestReviewStateTool.skipPermission, true);
    assert.equal(getPullRequestCommentsTool.skipPermission, true);
});

test("failure() returns a plain-message failure result without details", () => {
    assert.deepEqual(failure("boom"), {
        textResultForLlm: "boom",
        resultType: "failure",
    });
});

test("failure() folds details into a structured JSON payload", () => {
    const result = failure("boom", { resolvedThreadIds: [1, 2] });
    assert.equal(result.resultType, "failure");
    assert.deepEqual(JSON.parse(result.textResultForLlm), {
        message: "boom",
        resolvedThreadIds: [1, 2],
    });
});

test("toFailureResult converts a ToolFailure into structured details", () => {
    const error = new ToolFailure("partial failure", { failedThreadId: 3 });
    const result = toFailureResult(error);
    assert.deepEqual(JSON.parse(result.textResultForLlm), {
        message: "partial failure",
        failedThreadId: 3,
    });
});

test("toFailureResult converts a plain Error into a plain-message failure", () => {
    const result = toFailureResult(new Error("plain"));
    assert.deepEqual(result, { textResultForLlm: "plain", resultType: "failure" });
});

test("guardTool converts thrown errors into structured failures instead of rejecting", async () => {
    const handler = guardTool(async () => {
        throw new ToolFailure("nope", { remainingThreadIds: [9] });
    });
    const result = await handler({}, {});
    assert.equal(result.resultType, "failure");
    assert.deepEqual(JSON.parse(result.textResultForLlm), {
        message: "nope",
        remainingThreadIds: [9],
    });
});

test("guardTool passes through successful results untouched", async () => {
    const handler = guardTool(async (args) => `ok:${args.value}`);
    assert.equal(await handler({ value: 1 }, {}), "ok:1");
});

test("withCancellation passes the signal without replacing the injectable dependency", async () => {
    const controller = new AbortController();
    let receivedDependency = "not-called";
    let receivedSignal;
    const handler = withCancellation(async (args, dependency = "default", { signal } = {}) => {
        receivedDependency = dependency;
        receivedSignal = signal;
        return args.value;
    });

    assert.equal(await handler({ value: 1 }, { toolCallId: "call-1", signal: controller.signal }), 1);
    assert.equal(receivedDependency, "default");
    assert.equal(receivedSignal, controller.signal);
});

test("withCancellation refuses an already cancelled invocation", () => {
    const controller = new AbortController();
    controller.abort();
    const handler = withCancellation(() => assert.fail("cancelled handler was invoked"));
    assert.throws(() => handler({}, { signal: controller.signal }), { name: "AbortError" });
});
