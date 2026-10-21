import { spawn } from "node:child_process";
import { constants } from "node:fs";
import { open } from "node:fs/promises";
import { isAbsolute, resolve } from "node:path";
import { maxClipboardFileBytes } from "./contracts.mjs";

export function errorMessage(error) {
    return error instanceof Error ? error.message : String(error);
}

export function workingDirectoryFromEvents(events, fallback = process.cwd()) {
    let workingDirectory = fallback;

    for (const event of events) {
        if (event.agentId) {
            continue;
        }
        if (event.type === "session.start" && event.data?.context?.cwd) {
            workingDirectory = event.data.context.cwd;
        } else if (
            event.type === "session.context_changed" &&
            !event.data?.pendingGitContext &&
            event.data?.cwd
        ) {
            workingDirectory = event.data.cwd;
        }
    }

    return workingDirectory;
}

export function resolveClipboardFilePath(path, workingDirectory) {
    if (typeof path !== "string" || path.length === 0 || path.includes("\0")) {
        throw new Error("path must be a non-empty file path");
    }
    return isAbsolute(path) ? resolve(path) : resolve(workingDirectory, path);
}

export async function readClipboardFile(
    path,
    { signal, openImpl = open, maxBytes = maxClipboardFileBytes } = {},
) {
    signal?.throwIfAborted();
    const file = await openImpl(path, constants.O_RDONLY | constants.O_NONBLOCK);
    try {
        const fileStat = await file.stat();
        if (!fileStat.isFile()) {
            throw new Error(`Path is not a file: ${path}`);
        }
        if (fileStat.size > maxBytes) {
            throw new Error(`File exceeds the ${maxBytes}-byte clipboard limit: ${path}`);
        }
        const chunks = [];
        let size = 0;
        while (size <= maxBytes) {
            signal?.throwIfAborted();
            const chunk = Buffer.allocUnsafe(Math.min(64 * 1024, maxBytes + 1 - size));
            const { bytesRead } = await file.read(chunk, 0, chunk.length, null);
            if (bytesRead === 0) {
                break;
            }
            size += bytesRead;
            if (size > maxBytes) {
                throw new Error(`File exceeds the ${maxBytes}-byte clipboard limit: ${path}`);
            }
            chunks.push(chunk.subarray(0, bytesRead));
        }
        signal?.throwIfAborted();
        return Buffer.concat(chunks, size);
    } finally {
        await file.close();
    }
}

export function runClipboardCommand(
    content,
    {
        timeoutMs = 15_000,
        maxStderrBytes = 16 * 1024,
        command = "wl-copy",
        args = [],
        signal,
        spawnImpl = spawn,
        killGraceMs = 1_000,
    } = {},
) {
    return new Promise((resolveWrite, rejectWrite) => {
        signal?.throwIfAborted();
        const child = spawnImpl(command, args, { stdio: ["pipe", "ignore", "pipe"] });
        const stderr = [];
        let stderrBytes = 0;
        let settled = false;
        let failure;
        let exited = false;
        let exitCode;
        let exitSignal;
        let inputFinished = false;
        let stderrEnded = false;
        let timeout;
        let killTimer;

        const exitError = () => {
            const detail = Buffer.concat(stderr).toString("utf8").trim();
            const status = exitSignal ? `signal ${exitSignal}` : `code ${exitCode}`;
            return new Error(`${command} exited with ${status}${detail ? `: ${detail}` : ""}`);
        };
        const complete = (error) => {
            if (settled) {
                return;
            }
            settled = true;
            clearTimeout(timeout);
            clearTimeout(killTimer);
            signal?.removeEventListener("abort", onAbort);
            child.stdin.destroy();
            child.stderr.destroy();
            if (error !== undefined) {
                rejectWrite(error);
            } else {
                resolveWrite(command);
            }
        };
        const terminate = (error) => {
            if (settled || failure !== undefined) {
                return;
            }
            failure = error;
            child.stdin.destroy();
            if (exited) {
                complete(failure);
                return;
            }
            child.kill("SIGTERM");
            killTimer = setTimeout(() => child.kill("SIGKILL"), killGraceMs);
            killTimer.unref();
        };
        const onAbort = () => terminate(signal.reason);
        const finishExit = () => {
            if (!exited) {
                return;
            }
            if (failure !== undefined) {
                complete(failure);
            } else if (exitCode === 0 && inputFinished) {
                // wl-copy's daemon inherits stderr; its parent's successful
                // exit completes the copy without waiting for that pipe to close.
                complete();
            } else if (exitCode !== 0 && stderrEnded) {
                complete(exitError());
            }
        };

        child.stderr.on("data", (chunk) => {
            const remaining = maxStderrBytes - stderrBytes;
            if (remaining <= 0) {
                return;
            }
            const bounded = chunk.subarray(0, remaining);
            stderr.push(bounded);
            stderrBytes += bounded.length;
        });
        child.stderr.on("error", terminate);
        child.stderr.once("end", () => {
            stderrEnded = true;
            finishExit();
        });
        child.on("error", (error) => {
            if (command === "wl-copy" && error?.code === "ENOENT") {
                error = new Error(
                    "wl-copy is not installed or is not on PATH. Install the wl-clipboard package.",
                );
            }
            if (!child.pid) {
                complete(error);
            } else {
                terminate(error);
            }
        });
        child.once("exit", (code, processSignal) => {
            exited = true;
            exitCode = code;
            exitSignal = processSignal;
            finishExit();
        });
        child.once("close", () => {
            complete(failure !== undefined ? failure : (exitCode === 0 && inputFinished ? undefined : exitError()));
        });
        child.stdin.once("finish", () => {
            inputFinished = true;
            finishExit();
        });

        timeout = setTimeout(() => {
            terminate(exited && exitCode !== 0
                ? exitError()
                : new Error(`${command} did not exit within ${timeoutMs}ms`));
        }, timeoutMs);
        timeout.unref();
        signal?.addEventListener("abort", onAbort, { once: true });
        child.stdin.on("error", terminate);
        if (signal?.aborted) {
            onAbort();
            return;
        }
        child.stdin.end(content);
    });
}

export function writeClipboard(content, runCommand = runClipboardCommand, options = {}) {
    return runCommand(content, options);
}
