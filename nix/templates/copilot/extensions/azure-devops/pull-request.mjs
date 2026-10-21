// Core pull request API access: resolving a PR's current iteration/commit scope
// (the "snapshot" every other read-only tool pins its results to).

import { fetchJson } from "./http.mjs";
import { gitApiUrl, identity, pullRequestWebUrl } from "./formatting.mjs";
import { commitMatches, validateCommitId } from "./validation.mjs";

function iterationCommitIds(iteration) {
    return [
        iteration.sourceRefCommit?.commitId,
        ...(iteration.commits ?? []).map((commit) => commit.commitId),
    ].filter(Boolean);
}

/**
 * Resolves a pull request's details plus the iteration/commit scope
 * (`commitId` argument, or the latest iteration when omitted) that every
 * other tool must agree on to avoid PR-head drift between calls.
 */
export async function getPullRequestSnapshot(pullRequest, authorization, commitId, { signal } = {}) {
    const pullRequestEndpoint = gitApiUrl(
        pullRequest,
        `/pullRequests/${pullRequest.pullRequestId}`,
    );
    pullRequestEndpoint.searchParams.set("api-version", "7.1");

    const iterationsEndpoint = gitApiUrl(
        pullRequest,
        `/pullRequests/${pullRequest.pullRequestId}/iterations`,
    );
    iterationsEndpoint.searchParams.set("includeCommits", "true");
    iterationsEndpoint.searchParams.set("api-version", "7.1");

    const [details, iterationsPayload] = await Promise.all([
        fetchJson(pullRequestEndpoint, authorization, "Azure DevOps pull request request", { signal }),
        fetchJson(iterationsEndpoint, authorization, "Azure DevOps iterations request", { signal }),
    ]);
    const iterations = [...(iterationsPayload.value ?? [])].sort(
        (left, right) => Number(left.id) - Number(right.id),
    );
    if (iterations.length === 0) {
        throw new Error(
            `Pull request ${pullRequest.pullRequestId} does not contain any iterations.`,
        );
    }

    let iteration;
    let requestedCommitId = null;
    if (commitId !== undefined && commitId !== null && commitId !== "") {
        requestedCommitId = validateCommitId(commitId);
        const matches = iterations.filter((candidate) =>
            iterationCommitIds(candidate).some((candidateCommitId) =>
                commitMatches(candidateCommitId, requestedCommitId),
            ),
        );
        if (matches.length === 0) {
            throw new Error(
                `Commit ${requestedCommitId} was not found in pull request ${pullRequest.pullRequestId}.`,
            );
        }
        if (matches.length > 1) {
            throw new Error(
                `Commit ${requestedCommitId} maps to multiple pull request iterations: ` +
                    `${matches.map((match) => match.id).join(", ")}. Provide the source commit ID returned by the changed-files tool.`,
            );
        }
        [iteration] = matches;
    } else {
        iteration = iterations.at(-1);
    }

    const sourceCommitId =
        iteration.sourceRefCommit?.commitId ??
        details.lastMergeSourceCommit?.commitId;
    const targetCommitId =
        iteration.targetRefCommit?.commitId ??
        details.lastMergeTargetCommit?.commitId;
    const commonCommitId = iteration.commonRefCommit?.commitId ?? null;
    if (!sourceCommitId || !targetCommitId) {
        throw new Error(
            `Azure DevOps did not return source and target commits for pull request ${pullRequest.pullRequestId}.`,
        );
    }

    return {
        pullRequest,
        details,
        iteration,
        commitScope: {
            requestedCommitId,
            iterationId: Number(iteration.id),
            sourceCommitId,
            targetCommitId,
            commonCommitId,
        },
    };
}

export function simplifyPullRequest(snapshot, includeReviewers = false) {
    const { pullRequest, details, commitScope } = snapshot;
    const simplified = {
        ...pullRequest,
        url: pullRequestWebUrl(pullRequest),
        title: details.title,
        status: details.status,
        mergeStatus: details.mergeStatus,
        isDraft: Boolean(details.isDraft),
        createdBy: identity(details.createdBy),
        creationDate: details.creationDate,
        closedDate: details.closedDate ?? null,
        sourceRefName: details.sourceRefName,
        targetRefName: details.targetRefName,
        repository: {
            id: details.repository?.id,
            name: details.repository?.name,
            projectId: details.repository?.project?.id,
            projectName: details.repository?.project?.name,
        },
        commitScope,
    };
    if (includeReviewers) {
        simplified.reviewers = (details.reviewers ?? []).map((reviewer) => ({
            ...identity(reviewer),
            vote: reviewer.vote ?? 0,
            isRequired: Boolean(reviewer.isRequired),
            hasDeclined: Boolean(reviewer.hasDeclined),
        }));
    }
    return simplified;
}
