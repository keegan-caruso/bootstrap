import assert from "node:assert/strict";
import test from "node:test";
import { resolveAgainstWorkingDirectory, workingDirectoryFromEvents } from "./working-directory.mjs";

test("workingDirectoryFromEvents uses the latest settled root context", () => {
    const events = [
        { type: "session.start", data: { context: { cwd: "/initial" } } },
        { type: "session.context_changed", data: { cwd: "/pending", pendingGitContext: true } },
        { type: "session.context_changed", data: { cwd: "/agent" }, agentId: "subagent" },
        { type: "session.context_changed", data: { cwd: "/current" } },
    ];

    assert.equal(workingDirectoryFromEvents(events, "/fallback"), "/current");
});

test("workingDirectoryFromEvents falls back when no context is present", () => {
    assert.equal(workingDirectoryFromEvents([], "/fallback"), "/fallback");
});

test("resolveAgainstWorkingDirectory resolves relative paths against the active cwd", () => {
    assert.equal(
        resolveAgainstWorkingDirectory(".npmrc", "/workspace/project"),
        "/workspace/project/.npmrc",
    );
    assert.equal(resolveAgainstWorkingDirectory("/etc/absolute", "/workspace"), "/etc/absolute");
    assert.throws(() => resolveAgainstWorkingDirectory("", "/workspace"), /non-empty file path/);
    assert.throws(() => resolveAgainstWorkingDirectory(undefined, "/workspace"), /non-empty file path/);
});
