import assert from "node:assert/strict";
import test from "node:test";
import {
    runClipboardCommand,
    resolveClipboardFilePath,
    workingDirectoryFromEvents,
    writeClipboard,
} from "./clipboard.mjs";

test("workingDirectoryFromEvents uses the latest settled root context", () => {
    const events = [
        {
            type: "session.start",
            data: { context: { cwd: "/initial" } },
        },
        {
            type: "session.context_changed",
            data: { cwd: "/pending", pendingGitContext: true },
        },
        {
            type: "session.context_changed",
            data: { cwd: "/agent" },
            agentId: "subagent",
        },
        {
            type: "session.context_changed",
            data: { cwd: "/current" },
        },
    ];

    assert.equal(workingDirectoryFromEvents(events, "/fallback"), "/current");
});

test("resolveClipboardFilePath resolves relative paths against the active cwd", () => {
    assert.equal(
        resolveClipboardFilePath("notes/file.txt", "/workspace"),
        "/workspace/notes/file.txt",
    );
    assert.throws(
        () => resolveClipboardFilePath("bad\0path", "/workspace"),
        /non-empty file path/,
    );
});

test("writeClipboard invokes only the configured wl-copy runner", async () => {
    const signal = new AbortController().signal;
    let received;
    const result = await writeClipboard(Buffer.from("text"), async (content, options) => {
        received = content;
        assert.equal(options.signal, signal);
        return "wl-copy";
    }, { signal });

    assert.equal(result, "wl-copy");
    assert.equal(received.toString("utf8"), "text");
});

test("writeClipboard propagates wl-copy failures", async () => {
    await assert.rejects(
        writeClipboard(Buffer.from("text"), async () => {
            throw new Error("wl-copy unavailable");
        }),
        /wl-copy unavailable/,
    );
});

test("runClipboardCommand terminates a hung clipboard process", async () => {
    await assert.rejects(
        runClipboardCommand(
            Buffer.from("text"),
            {
                timeoutMs: 25,
                command: process.execPath,
                args: ["-e", "setInterval(() => {}, 1000)"],
            },
        ),
        /did not exit within 25ms/,
    );
});
