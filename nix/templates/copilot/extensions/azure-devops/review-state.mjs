// Pull request review-state aggregation: active discussion threads, policy
// evaluations, and the build metadata those policies reference.

import { maxReviewCommentCharacters, maxReviewThreads } from "./contracts.mjs";
import { authorizationHeader } from "./auth.mjs";
import { fetchJson } from "./http.mjs";
import { gitApiUrl, simplifyThread } from "./formatting.mjs";
import { getPullRequestSnapshot, simplifyPullRequest } from "./pull-request.mjs";
import { resolvePullRequest } from "./validation.mjs";

function threadActivityDate(thread) {
    return (thread.comments ?? []).reduce((latest, comment) => {
        const candidate =
            comment.lastContentUpdatedDate ??
            comment.lastUpdatedDate ??
            comment.publishedDate ??
            "";
        return candidate > latest ? candidate : latest;
    }, thread.lastUpdatedDate ?? thread.publishedDate ?? "");
}

function simplifyReviewThread(thread) {
    const simplified = simplifyThread(thread, false);
    return {
        id: simplified.id,
        status: simplified.status,
        publishedDate: simplified.publishedDate,
        lastUpdatedDate: simplified.lastUpdatedDate,
        threadContext: simplified.threadContext,
        pullRequestThreadContext: simplified.pullRequestThreadContext,
        comments: simplified.comments.map((comment) => ({
            id: comment.id,
            parentCommentId: comment.parentCommentId,
            author: comment.author
                ? {
                    id: comment.author.id,
                    displayName: comment.author.displayName,
                    uniqueName: comment.author.uniqueName,
                }
                : null,
            content:
                comment.content.length > maxReviewCommentCharacters
                    ? `${comment.content.slice(0, maxReviewCommentCharacters)}\n[truncated]`
                    : comment.content,
            publishedDate: comment.publishedDate,
            lastUpdatedDate: comment.lastUpdatedDate,
        })),
    };
}

function policyValue(record, paths) {
    for (const path of paths) {
        let value = record;
        for (const part of path.split(".")) {
            value = value?.[part];
        }
        if (value !== undefined && value !== null && value !== "") {
            return value;
        }
    }
    return null;
}

function simplifyPolicy(record, buildsById, pullRequestSourceCommitId) {
    const configuration = record.configuration ?? {};
    const settings = configuration.settings ?? {};
    const context = record.context ?? {};
    const type = configuration.type ?? {};
    const buildId = policyValue({ context }, ["context.buildId", "context.build.id"]);
    const build = buildId ? buildsById.get(Number(buildId)) : null;
    const simplified = {
        configurationId: configuration.id,
        displayName:
            build?.definition?.name ??
            policyValue({ context, settings }, [
                "context.name",
                "context.displayName",
                "settings.displayName",
                "settings.buildDefinitionName",
                "settings.statusName",
            ]) ??
            type.displayName,
        type: type.displayName,
        status: record.status,
        isBlocking: Boolean(configuration.isBlocking),
        isEnabled: Boolean(configuration.isEnabled),
        completedDate: record.completedDate ?? null,
    };
    if (buildId) {
        simplified.build = {
            definitionId:
                build?.definition?.id ??
                policyValue({ context, settings }, [
                    "context.buildDefinitionId",
                    "settings.buildDefinitionId",
                ]),
            definitionName: build?.definition?.name ?? null,
            id: buildId,
            url:
                build?._links?.web?.href ??
                policyValue({ context, record }, [
                    "context.buildUrl",
                    "context.build.url",
                    "context.build._links.web.href",
                    "record._links.web.href",
                ]),
            sourceVersion: build?.sourceVersion ?? null,
            sourceBranch: build?.sourceBranch ?? null,
            pullRequestSourceCommitId: build ? pullRequestSourceCommitId : null,
            includesPullRequestSourceCommit: build
                ? build.sourceVersion === pullRequestSourceCommitId ||
                    (build.sourceCommit?.parents ?? []).includes(pullRequestSourceCommitId)
                : null,
            sourceVersionParents: build?.sourceCommit?.parents ?? [],
            status: build?.status ?? null,
            result: build?.result ?? null,
        };
    }
    return simplified;
}

async function getBuildsById(snapshot, authorization, policyRecords, signal) {
    const buildIds = [
        ...new Set(
            policyRecords
                .map((record) =>
                    policyValue({ context: record.context ?? {} }, [
                        "context.buildId",
                        "context.build.id",
                    ]),
                )
                .map(Number)
                .filter((buildId) => Number.isInteger(buildId) && buildId > 0),
        ),
    ];
    const builds = await Promise.all(
        buildIds.map(async (buildId) => {
            const pullRequest = snapshot.pullRequest;
            const endpoint = new URL(
                `https://dev.azure.com/${encodeURIComponent(pullRequest.organization)}` +
                `/${encodeURIComponent(pullRequest.project)}/_apis/build/builds/${buildId}`,
            );
            endpoint.searchParams.set("api-version", "7.1");
            return fetchJson(endpoint, authorization, `Azure DevOps build ${buildId} request`, { signal });
        }),
    );
    const sourceVersions = [
        ...new Set(builds.map((build) => build.sourceVersion).filter(Boolean)),
    ];
    const sourceCommits = await Promise.all(
        sourceVersions.map(async (sourceVersion) => {
            const endpoint = gitApiUrl(
                snapshot.pullRequest,
                `/commits/${encodeURIComponent(sourceVersion)}`,
            );
            endpoint.searchParams.set("api-version", "7.1");
            return fetchJson(
                endpoint,
                authorization,
                `Azure DevOps build source commit ${sourceVersion} request`,
                { signal },
            );
        }),
    );
    const sourceCommitsById = new Map(
        sourceCommits.map((commit) => [commit.commitId, commit]),
    );
    return new Map(
        builds.map((build) => [
            Number(build.id),
            {
                ...build,
                sourceCommit: sourceCommitsById.get(build.sourceVersion) ?? null,
            },
        ]),
    );
}

export async function getPullRequestReviewState(args, getAuthorization = authorizationHeader, { signal } = {}) {
    signal?.throwIfAborted();
    const pullRequest = resolvePullRequest(args);
    const authorization = await getAuthorization(undefined, { signal });

    const snapshot = await getPullRequestSnapshot(pullRequest, authorization, args.commitId, { signal });
    const currentSourceCommitId = snapshot.details.lastMergeSourceCommit?.commitId;
    if (
        currentSourceCommitId &&
        snapshot.commitScope.sourceCommitId !== currentSourceCommitId
    ) {
        throw new Error(
            `Pull request review state is only available for the current head ` +
                `${currentSourceCommitId}; requested commit resolved to ` +
                `${snapshot.commitScope.sourceCommitId}.`,
        );
    }
    const threadsEndpoint = gitApiUrl(
        pullRequest,
        `/pullRequests/${pullRequest.pullRequestId}/threads`,
    );
    threadsEndpoint.searchParams.set("api-version", "7.1");

    const projectId = snapshot.details.repository?.project?.id;
    if (!projectId) {
        throw new Error(
            "Azure DevOps did not return the repository project ID required to query policies.",
        );
    }
    const policiesEndpoint = new URL(
        `https://dev.azure.com/${encodeURIComponent(pullRequest.organization)}` +
        `/${encodeURIComponent(pullRequest.project)}/_apis/policy/evaluations`,
    );
    policiesEndpoint.searchParams.set(
        "artifactId",
        `vstfs:///CodeReview/CodeReviewId/${projectId}/${pullRequest.pullRequestId}`,
    );
    policiesEndpoint.searchParams.set("includeNotApplicable", "true");
    policiesEndpoint.searchParams.set("$top", "1000");
    policiesEndpoint.searchParams.set("api-version", "7.1-preview.1");

    const [threadsPayload, policiesPayload] = await Promise.all([
        fetchJson(threadsEndpoint, authorization, "Azure DevOps threads request", { signal }),
        fetchJson(policiesEndpoint, authorization, "Azure DevOps policies request", { signal }),
    ]);
    const allActiveThreads = (threadsPayload.value ?? [])
        .filter((thread) => !thread.isDeleted)
        .filter((thread) => ["active", "pending"].includes(String(thread.status).toLowerCase()))
        .map(simplifyReviewThread)
        .sort((left, right) => threadActivityDate(right).localeCompare(threadActivityDate(left)));
    const activeThreads = allActiveThreads.slice(0, maxReviewThreads);
    const policyRecords = policiesPayload.value ?? [];
    const buildsById = await getBuildsById(snapshot, authorization, policyRecords, signal);
    const policies = policyRecords.map((record) =>
        simplifyPolicy(record, buildsById, snapshot.commitScope.sourceCommitId),
    );
    const blockingPolicies = policies.filter(
        (policy) =>
            policy.isEnabled &&
            policy.isBlocking &&
            String(policy.status).toLowerCase() !== "notapplicable",
    );
    const blockingPolicyCounts = blockingPolicies.reduce((counts, policy) => {
        const status = String(policy.status ?? "unknown");
        counts[status] = (counts[status] ?? 0) + 1;
        return counts;
    }, {});

    // Threads, policies, and builds above were each fetched independently and
    // can take a noticeable amount of time (build lookups in particular).
    // Re-check the pull request head now that everything has been collected:
    // if it moved while we were gathering data, the aggregated review state
    // could mix information from two different heads, so we reject rather
    // than return a possibly-inconsistent snapshot.
    const recheckEndpoint = gitApiUrl(pullRequest, `/pullRequests/${pullRequest.pullRequestId}`);
    recheckEndpoint.searchParams.set("api-version", "7.1");
    const recheckedDetails = await fetchJson(
        recheckEndpoint,
        authorization,
        "Azure DevOps pull request recheck",
        { signal },
    );
    const recheckedSourceCommitId = recheckedDetails.lastMergeSourceCommit?.commitId;
    if (
        recheckedSourceCommitId &&
        recheckedSourceCommitId !== snapshot.commitScope.sourceCommitId
    ) {
        throw new Error(
            `Pull request head changed while collecting review state (was ` +
                `${snapshot.commitScope.sourceCommitId}, now ${recheckedSourceCommitId}); the ` +
                `collected threads, policies, and builds may be inconsistent. Re-run the tool for a fresh snapshot.`,
        );
    }

    return JSON.stringify(
        {
            pullRequest: simplifyPullRequest(snapshot, true),
            reviewThreads: {
                activeCount: allActiveThreads.length,
                returnedCount: activeThreads.length,
                truncated: allActiveThreads.length > activeThreads.length,
                newestActive: activeThreads[0] ?? null,
                active: activeThreads,
            },
            policies: {
                totalCount: policies.length,
                blockingCount: blockingPolicies.length,
                blockingStatusCounts: blockingPolicyCounts,
                hasPendingBlockingPolicies: blockingPolicies.some((policy) =>
                    ["queued", "running"].includes(String(policy.status).toLowerCase()),
                ),
                hasFailedBlockingPolicies: blockingPolicies.some((policy) =>
                    ["rejected", "broken"].includes(String(policy.status).toLowerCase()),
                ),
                evaluations: policies,
            },
        },
        null,
        2,
    );
}
