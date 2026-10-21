// Pull request discussion threads: read-only listing plus resolving
// (setting status "fixed") a validated set of threads. Thread mutation is a
// PATCH per thread and is never automatically retried; listing threads and
// resolving the commit scope are both read-only GETs and go through the
// shared retrying fetchJson.

import { ToolFailure } from "./contracts.mjs";
import { authorizationHeader } from "./auth.mjs";
import { fetchJson, fetchJsonResponse } from "./http.mjs";
import { gitApiUrl, pullRequestWebUrl, simplifyThread } from "./formatting.mjs";
import { commitMatches, resolvePullRequest } from "./validation.mjs";

/**
 * Resolves an explicit `commitId` argument to the pull request iteration
 * that introduced it, or returns `null` when no commit was requested (in
 * which case callers should not scope threads to a specific iteration).
 */
export async function resolveCommitScope(pullRequest, authorization, commitId, { signal } = {}) {
    signal?.throwIfAborted();
    if (commitId === undefined || commitId === null || commitId === "") {
        return null;
    }

    const requestedCommitId = String(commitId).trim();
    if (!/^[0-9a-f]{7,64}$/i.test(requestedCommitId)) {
        throw new Error("commitId must be a Git commit ID with 7 to 64 hexadecimal characters.");
    }

    const iterationsEndpoint = gitApiUrl(
        pullRequest,
        `/pullRequests/${pullRequest.pullRequestId}/iterations`,
    );
    iterationsEndpoint.searchParams.set("includeCommits", "true");
    iterationsEndpoint.searchParams.set("api-version", "7.1");

    const payload = await fetchJson(
        iterationsEndpoint,
        authorization,
        "Azure DevOps iteration request",
        { signal },
    );

    const matches = [];
    for (const iteration of payload.value ?? []) {
        const candidateCommitIds = [
            iteration.sourceRefCommit?.commitId,
            ...(iteration.commits ?? []).map((commit) => commit.commitId),
        ].filter(Boolean);
        const matchedCommitId = candidateCommitIds.find((candidate) =>
            commitMatches(candidate, requestedCommitId),
        );
        if (matchedCommitId) {
            matches.push({
                iterationId: Number(iteration.id),
                commitId: matchedCommitId,
                sourceRefCommitId: iteration.sourceRefCommit?.commitId ?? null,
            });
        }
    }

    const uniqueMatches = [
        ...new Map(matches.map((match) => [match.iterationId, match])).values(),
    ];
    if (uniqueMatches.length === 0) {
        throw new Error(
            `Commit ${requestedCommitId} was not found in pull request ${pullRequest.pullRequestId}.`,
        );
    }
    if (uniqueMatches.length > 1) {
        throw new Error(
            `Commit ${requestedCommitId} maps to multiple pull request iterations: ` +
                `${uniqueMatches.map((match) => match.iterationId).join(", ")}. Provide a more specific commit ID.`,
        );
    }

    return {
        requestedCommitId,
        ...uniqueMatches[0],
    };
}

/**
 * Builds the threads endpoint for a pull request. When `commitScope` is
 * given, thread positions are requested as Azure DevOps maps them onto that
 * iteration (`$iteration`), diffed against the very start of the pull
 * request (`$baseIteration=0`) so PR-level and earlier-iteration threads
 * remain present in the response instead of being dropped. Azure DevOps -
 * not this extension - is responsible for that iteration mapping; we must
 * not re-filter the returned threads by an equality check against thread
 * creation metadata, which would incorrectly hide threads it already
 * mapped in for us.
 */
function threadsEndpointFor(pullRequest, commitScope) {
    const endpoint = gitApiUrl(pullRequest, `/pullRequests/${pullRequest.pullRequestId}/threads`);
    endpoint.searchParams.set("api-version", "7.1");
    if (commitScope) {
        endpoint.searchParams.set("$iteration", String(commitScope.iterationId));
        endpoint.searchParams.set("$baseIteration", "0");
    }
    return endpoint;
}

export async function getPullRequestComments(args, getAuthorization = authorizationHeader, { signal } = {}) {
    signal?.throwIfAborted();
    const pullRequest = resolvePullRequest(args);
    const authorization = await getAuthorization(undefined, { signal });
    const commitScope = await resolveCommitScope(pullRequest, authorization, args.commitId, { signal });

    const endpoint = threadsEndpointFor(pullRequest, commitScope);
    const payload = await fetchJson(endpoint, authorization, "Azure DevOps threads request", { signal });

    const includeDeleted = args.includeDeleted === true;
    const requestedStatus = args.status ?? "all";
    const threads = (payload.value ?? [])
        .filter((thread) => includeDeleted || !thread.isDeleted)
        .filter(
            (thread) =>
                requestedStatus === "all" ||
                String(thread.status).toLowerCase() === requestedStatus.toLowerCase(),
        )
        .map((thread) => simplifyThread(thread, includeDeleted));

    return JSON.stringify(
        {
            pullRequest: {
                ...pullRequest,
                url: pullRequestWebUrl(pullRequest),
            },
            commitScope,
            threadCount: threads.length,
            commentCount: threads.reduce((total, thread) => total + thread.comments.length, 0),
            threads,
        },
        null,
        2,
    );
}

export async function resolvePullRequestComments(args, getAuthorization = authorizationHeader, { signal } = {}) {
    signal?.throwIfAborted();
    const pullRequest = resolvePullRequest(args);

    const requestedThreadIds = args.threadIds;
    if (!Array.isArray(requestedThreadIds) || requestedThreadIds.length === 0) {
        throw new Error("threadIds must contain at least one Azure DevOps thread ID.");
    }
    if (requestedThreadIds.length > 100) {
        throw new Error("At most 100 thread IDs can be resolved in one call.");
    }

    const threadIds = [...new Set(requestedThreadIds.map(Number))];
    if (threadIds.some((threadId) => !Number.isInteger(threadId) || threadId <= 0)) {
        throw new Error("Every thread ID must be a positive integer.");
    }

    const authorization = await getAuthorization(undefined, { signal });
    const commitScope = await resolveCommitScope(pullRequest, authorization, args.commitId, { signal });

    // Azure DevOps has already scoped this response to the requested
    // iteration (see threadsEndpointFor); no additional client-side
    // iteration-equality filtering is applied.
    const threadsEndpoint = threadsEndpointFor(pullRequest, commitScope);
    const payload = await fetchJson(threadsEndpoint, authorization, "Azure DevOps threads request", { signal });
    const threadsById = new Map((payload.value ?? []).map((thread) => [Number(thread.id), thread]));
    const missingThreadIds = threadIds.filter((threadId) => !threadsById.has(threadId));
    if (missingThreadIds.length > 0) {
        throw new Error(
            `No threads were changed because these thread IDs were not found: ${missingThreadIds.join(", ")}.`,
        );
    }

    const deletedThreadIds = threadIds.filter((threadId) => threadsById.get(threadId).isDeleted);
    if (deletedThreadIds.length > 0) {
        throw new Error(
            `No threads were changed because these threads are deleted: ${deletedThreadIds.join(", ")}.`,
        );
    }

    const alreadyFixed = [];
    const toResolve = [];
    const conflictingStatuses = [];
    for (const threadId of threadIds) {
        const thread = threadsById.get(threadId);
        const status = String(thread.status ?? "unknown").toLowerCase();
        if (status === "fixed") {
            alreadyFixed.push(simplifyThread(thread, false));
        } else if (status === "active" || status === "pending") {
            toResolve.push(thread);
        } else {
            conflictingStatuses.push({ threadId, status });
        }
    }

    if (conflictingStatuses.length > 0) {
        throw new Error(
            "No threads were changed because resolving would overwrite existing outcomes: " +
                conflictingStatuses
                    .map(({ threadId, status }) => `${threadId} (${status})`)
                    .join(", ") +
                ".",
        );
    }

    // Each PATCH below is a non-idempotent mutation of a single thread and is
    // never retried automatically. If one fails partway through, the thrown
    // ToolFailure records exactly which threads were already resolved so the
    // caller can decide whether to retry only the remaining ones.
    const resolved = [];
    for (const thread of toResolve) {
        const threadEndpoint = new URL(
            `${threadsEndpoint.origin}${threadsEndpoint.pathname}/${thread.id}`,
        );
        threadEndpoint.searchParams.set("api-version", "7.1");

        const remainingThreadIds = () =>
            toResolve
                .filter(
                    (value) =>
                        !resolved.some((resolvedThread) => resolvedThread.id === value.id) &&
                        value.id !== thread.id,
                )
                .map((value) => value.id);

        // Immediately re-check this specific thread right before mutating
        // it, closing (not eliminating) the window in which someone else
        // could have deleted it or changed its status since the batch fetch
        // above. If Azure DevOps returns an ETag for the thread, forward it
        // as `If-Match` on the PATCH below for optimistic concurrency; if it
        // does not, we simply proceed without that extra protection rather
        // than inventing a header Azure DevOps does not document support for.
        let recheckedThread;
        let etag;
        try {
            const recheck = await fetchJsonResponse(
                threadEndpoint,
                authorization,
                `Azure DevOps thread ${thread.id} recheck`,
                { signal },
            );
            recheckedThread = recheck.data;
            etag = recheck.response.headers?.get?.("etag") ?? null;
        } catch (error) {
            throw new ToolFailure(error instanceof Error ? error.message : String(error), {
                resolvedThreadIds: resolved.map((value) => value.id),
                failedThreadId: thread.id,
                remainingThreadIds: remainingThreadIds(),
            });
        }

        if (recheckedThread.isDeleted) {
            throw new ToolFailure(
                `Thread ${thread.id} was deleted after it was selected for resolution. No changes were made to this thread.`,
                {
                    resolvedThreadIds: resolved.map((value) => value.id),
                    failedThreadId: thread.id,
                    remainingThreadIds: remainingThreadIds(),
                },
            );
        }
        const recheckedStatus = String(recheckedThread.status ?? "unknown").toLowerCase();
        if (recheckedStatus !== "active" && recheckedStatus !== "pending") {
            throw new ToolFailure(
                `Thread ${thread.id} is no longer active or pending (now "${recheckedStatus}"); refusing to resolve it to avoid overwriting a concurrent change. No changes were made to this thread.`,
                {
                    resolvedThreadIds: resolved.map((value) => value.id),
                    failedThreadId: thread.id,
                    remainingThreadIds: remainingThreadIds(),
                },
            );
        }

        let updated;
        try {
            updated = await fetchJson(
                threadEndpoint,
                authorization,
                `Azure DevOps thread ${thread.id} update`,
                {
                    signal,
                    method: "PATCH",
                    headers: {
                        "Content-Type": "application/json",
                        ...(etag ? { "If-Match": etag } : {}),
                    },
                    body: JSON.stringify({ status: "fixed" }),
                },
                { attempts: 1 },
            );
        } catch (error) {
            throw new ToolFailure(
                error instanceof Error ? error.message : String(error),
                {
                    resolvedThreadIds: resolved.map((value) => value.id),
                    failedThreadId: thread.id,
                    remainingThreadIds: remainingThreadIds(),
                },
            );
        }

        resolved.push(simplifyThread(updated, false));
    }

    return JSON.stringify(
        {
            pullRequest: {
                ...pullRequest,
                url: pullRequestWebUrl(pullRequest),
            },
            commitScope,
            requestedThreadIds: threadIds,
            resolvedThreadIds: resolved.map((thread) => thread.id),
            alreadyFixedThreadIds: alreadyFixed.map((thread) => thread.id),
            threads: [...resolved, ...alreadyFixed],
        },
        null,
        2,
    );
}
