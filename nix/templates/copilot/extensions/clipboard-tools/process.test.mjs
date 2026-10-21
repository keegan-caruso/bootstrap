import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { EventEmitter, once } from "node:events";
import { PassThrough, Writable } from "node:stream";
import { setTimeout as delay } from "node:timers/promises";
import test from "node:test";
import { runClipboardCommand } from "./clipboard.mjs";

function fakeChild() {
    const child = new EventEmitter();
    child.pid = 123;
    child.stdin = new Writable({ write(_chunk, _encoding, callback) { callback(); } });
    child.stderr = new PassThrough();
    child.signals = [];
    child.kill = signal => { child.signals.push(signal); return true; };
    return child;
}

test("a successful parent exit completes without waiting for daemon-owned stderr", async () => {
    const child = fakeChild();
    const result = runClipboardCommand(Buffer.from("text"), { spawnImpl: () => child });
    child.emit("exit", 0, null);
    assert.equal(await result, "wl-copy");
    assert(child.stderr.destroyed);
    assert.deepEqual(child.signals, []);
});

test("failed commands report bounded stderr after the stream drains", async () => {
    const child = fakeChild();
    const result = runClipboardCommand(Buffer.from("text"), { spawnImpl: () => child, maxStderrBytes: 4 });
    child.emit("exit", 2, null);
    child.stderr.end("diagnostic text");
    await assert.rejects(result, /exited with code 2: diag$/);
});

test("a missing executable is reported without attempting to kill a child", async () => {
    const child = fakeChild();
    child.pid = undefined;
    const result = runClipboardCommand(Buffer.from("text"), { spawnImpl: () => child });
    child.emit("error", Object.assign(new Error("missing"), { code: "ENOENT" }));
    await assert.rejects(result, /wl-copy is not installed/);
    assert.deepEqual(child.signals, []);
});

test("stdin errors terminate the child and wait for its exit before rejecting", async () => {
    const child = fakeChild();
    const result = runClipboardCommand(Buffer.from("text"), { spawnImpl: () => child });
    let settled = false;
    result.catch(() => { settled = true; });
    child.stdin.emit("error", new Error("pipe failure"));
    await delay(0);
    assert.equal(settled, false);
    assert.deepEqual(child.signals, ["SIGTERM"]);
    child.emit("exit", null, "SIGTERM");
    await assert.rejects(result, /pipe failure/);
    assert(child.stderr.destroyed);
});

test("a child that ignores termination is forcibly killed without losing the original error", async () => {
    const child = fakeChild();
    child.kill = signal => {
        child.signals.push(signal);
        if (signal === "SIGKILL") child.emit("exit", null, signal);
        return true;
    };
    const result = runClipboardCommand(Buffer.from("text"), { spawnImpl: () => child, killGraceMs: 5 });
    const rejected = assert.rejects(result, /pipe failure/);
    child.stdin.emit("error", new Error("pipe failure"));
    await delay(20);
    await rejected;
    assert.deepEqual(child.signals, ["SIGTERM", "SIGKILL"]);
});

test("cancelled clipboard commands do not start or leave a running child", async () => {
    await assert.rejects(
        runClipboardCommand(Buffer.from("text"), {
            signal: AbortSignal.abort(),
            spawnImpl: () => assert.fail("cancelled process must not start"),
        }),
        { name: "AbortError" },
    );
    const child = fakeChild();
    const controller = new AbortController();
    const result = runClipboardCommand(Buffer.from("text"), {
        spawnImpl: () => child, signal: controller.signal,
    });
    controller.abort();
    assert.deepEqual(child.signals, ["SIGTERM"]);
    child.emit("exit", null, "SIGTERM");
    await assert.rejects(result, { name: "AbortError" });
});

test("a falsy cancellation reason cannot turn a terminated copy into success", async () => {
    const child = fakeChild();
    const controller = new AbortController();
    const result = runClipboardCommand(Buffer.from("text"), {
        spawnImpl: () => child, signal: controller.signal,
    });
    controller.abort(0);
    child.emit("exit", null, "SIGTERM");
    await assert.rejects(result, error => error === 0);
});

test("an actual child closing stdin is reaped after EPIPE", async () => {
    let child;
    try {
        await assert.rejects(runClipboardCommand(Buffer.alloc(2 * 1024 * 1024), {
            command: process.execPath,
            args: ["-e", "require('node:fs').closeSync(0); setInterval(() => {}, 1000)"],
            spawnImpl: (...args) => (child = spawn(...args)),
        }), /EPIPE/);
        assert(child.exitCode !== null || child.signalCode !== null);
    } finally {
        if (child && child.exitCode === null && child.signalCode === null) {
            const closed = once(child, "close");
            child.kill("SIGKILL");
            await closed;
        }
    }
});
