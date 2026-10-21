// Resolves the active Copilot CLI working directory from session events, and
// resolves a user-supplied relative path against it. This exists so that
// relative config paths (for example `azure_devops_refresh_artifacts_auth`'s
// `filePath`) are resolved against wherever the CLI is currently rooted,
// rather than the extension process's own (potentially stale, since the
// extension is a long-lived forked process) working directory.

import { isAbsolute, resolve } from "node:path";

/**
 * Walks session events for the most recent settled working directory,
 * ignoring sub-agent events and git-context updates that have not settled
 * yet (`pendingGitContext`).
 */
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

/** Resolves a possibly-relative path against the active working directory. */
export function resolveAgainstWorkingDirectory(path, workingDirectory) {
    if (typeof path !== "string" || path.trim() === "") {
        throw new Error("path must be a non-empty file path.");
    }
    return isAbsolute(path) ? resolve(path) : resolve(workingDirectory, path);
}
