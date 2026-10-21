// Pure input parsing and validation for the azure-devops extension. No
// network, filesystem, or process access - every function here is
// deterministic and safe to unit test directly.

function decodePathPart(value) {
    return decodeURIComponent(value);
}

/** Parses an https://dev.azure.com or *.visualstudio.com pull request URL. */
export function parsePullRequestUrl(value) {
    let url;
    try {
        url = new URL(value);
    } catch {
        throw new Error("pullRequestUrl must be a valid Azure DevOps URL.");
    }

    const parts = url.pathname.split("/").filter(Boolean).map(decodePathPart);
    const gitIndex = parts.findIndex((part) => part.toLowerCase() === "_git");
    const pullRequestIndex = parts.findIndex(
        (part) => part.toLowerCase() === "pullrequest",
    );
    if (
        gitIndex < 1 ||
        pullRequestIndex !== gitIndex + 2 ||
        !parts[pullRequestIndex + 1]
    ) {
        throw new Error(
            "pullRequestUrl must look like https://dev.azure.com/{organization}/{project}/_git/{repository}/pullrequest/{id}.",
        );
    }

    const pullRequestId = Number(parts[pullRequestIndex + 1]);
    if (!Number.isInteger(pullRequestId) || pullRequestId <= 0) {
        throw new Error("The pull request URL does not contain a valid pull request ID.");
    }

    let organization;
    let projectIndex;
    if (url.hostname.toLowerCase() === "dev.azure.com") {
        organization = parts[0];
        projectIndex = 1;
    } else if (url.hostname.toLowerCase().endsWith(".visualstudio.com")) {
        organization = url.hostname.slice(0, -".visualstudio.com".length);
        projectIndex = 0;
    } else {
        throw new Error("pullRequestUrl must use dev.azure.com or visualstudio.com.");
    }

    return {
        organization,
        project: parts[projectIndex],
        repository: parts[gitIndex + 1],
        pullRequestId,
    };
}

/** Accepts a bare organization name or a dev.azure.com/*.visualstudio.com URL. */
export function normalizeOrganization(value) {
    const trimmed = value.trim().replace(/\/+$/, "");
    if (!trimmed.includes("://")) {
        return trimmed;
    }

    const url = new URL(trimmed);
    if (url.hostname.toLowerCase() === "dev.azure.com") {
        const organization = url.pathname.split("/").filter(Boolean)[0];
        if (organization) {
            return decodePathPart(organization);
        }
    } else if (url.hostname.toLowerCase().endsWith(".visualstudio.com")) {
        return url.hostname.slice(0, -".visualstudio.com".length);
    }

    throw new Error("organization must be a name or an Azure DevOps organization URL.");
}

/** Resolves the pull request identity from either a URL or explicit fields. */
export function resolvePullRequest(args) {
    if (args.pullRequestUrl) {
        return parsePullRequestUrl(args.pullRequestUrl);
    }

    const missing = ["organization", "project", "repository", "pullRequestId"]
        .filter((name) => args[name] === undefined || args[name] === "");
    if (missing.length > 0) {
        throw new Error(
            `Provide pullRequestUrl or all explicit fields. Missing: ${missing.join(", ")}.`,
        );
    }

    const pullRequestId = Number(args.pullRequestId);
    if (!Number.isInteger(pullRequestId) || pullRequestId <= 0) {
        throw new Error("pullRequestId must be a positive integer.");
    }

    return {
        organization: normalizeOrganization(args.organization),
        project: args.project,
        repository: args.repository,
        pullRequestId,
    };
}

export function requireNonEmptyString(value, name) {
    if (typeof value !== "string" || value.trim() === "") {
        throw new Error(`${name} must be a non-empty string.`);
    }
    return value.trim();
}

const commitIdPattern = /^[0-9a-f]{7,64}$/i;

export function validateCommitId(commitId) {
    const value = String(commitId).trim();
    if (!commitIdPattern.test(value)) {
        throw new Error("commitId must be a Git commit ID with 7 to 64 hexadecimal characters.");
    }
    return value;
}

/** True when `candidate` is a full commit ID that `requestedCommitId` prefixes. */
export function commitMatches(candidate, requestedCommitId) {
    return (
        typeof candidate === "string" &&
        candidate.toLowerCase().startsWith(requestedCommitId.toLowerCase())
    );
}
