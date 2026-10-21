// Shared contracts for the azure-devops extension: tool schemas, limits, and
// the result/failure helpers every tool handler is composed through.
//
// This module must stay dependency-free (no fetch, no child_process, no fs)
// so it can be imported and unit tested in isolation, and so every other
// module can safely depend on it without creating cycles.

// Environment variables that leak ambient Azure Artifacts credentials into
// the credential-provider subprocesses. They are stripped so that refreshing
// credentials for one feed cannot silently reuse a token scoped to another.
export const credentialProviderBuildVariables = Object.freeze([
    "ARTIFACTS_CREDENTIALPROVIDER_ACCESSTOKEN",
    "ARTIFACTS_CREDENTIALPROVIDER_EXTERNAL_FEED_ENDPOINTS",
    "ARTIFACTS_CREDENTIALPROVIDER_FEED_ENDPOINTS",
    "ARTIFACTS_CREDENTIALPROVIDER_URI_PREFIXES",
    "VSS_NUGET_ACCESSTOKEN",
    "VSS_NUGET_EXTERNAL_FEED_ENDPOINTS",
    "VSS_NUGET_URI_PREFIXES",
]);

export const maxReviewThreads = 100;
export const maxReviewCommentCharacters = 4_000;

/**
 * Error carrying structured, tool-result details (for example partial-progress
 * information for a multi-step mutation) alongside a human-readable message.
 * Thrown from business logic and translated into a structured failure result
 * by {@link guardTool}, so callers never have to build failure objects by hand.
 */
export class ToolFailure extends Error {
    constructor(message, details) {
        super(message);
        this.name = "ToolFailure";
        this.details = details;
    }
}

/** Builds a plain-string success failure with no extra structured detail. */
export function failure(message, details) {
    if (!details) {
        return { textResultForLlm: message, resultType: "failure" };
    }
    return {
        textResultForLlm: JSON.stringify({ message, ...details }, null, 2),
        resultType: "failure",
    };
}

/** Converts any thrown value into a structured failure tool result. */
export function toFailureResult(error) {
    if (error instanceof ToolFailure) {
        return failure(error.message, error.details);
    }
    return failure(error instanceof Error ? error.message : String(error));
}

/**
 * Wraps a tool handler so that every thrown error - validation, network,
 * filesystem, or otherwise - is consistently converted into a structured
 * `{ resultType: "failure" }` tool result instead of an unhandled rejection
 * or an ad hoc inline failure. Business-logic modules can therefore just
 * `throw new Error(...)` (or `throw new ToolFailure(...)` for structured
 * detail) and never construct failure results themselves.
 */
export function guardTool(handler) {
    return async (args, invocation) => {
        try {
            return await handler(args, invocation);
        } catch (error) {
            return toFailureResult(error);
        }
    };
}

/**
 * Passes cancellation without occupying the injectable authorization parameter.
 */
export function withCancellation(handler) {
    return (args, invocation) => {
        const signal = invocation?.signal;
        signal?.throwIfAborted();
        return handler(args, undefined, { signal });
    };
}

const pullRequestReadProperties = Object.freeze({
    pullRequestUrl: {
        type: "string",
        description:
            "Full Azure DevOps pull request URL. When supplied, explicit repository fields are ignored.",
    },
    organization: {
        type: "string",
        description:
            "Azure DevOps organization name or URL. Required without pullRequestUrl.",
    },
    project: {
        type: "string",
        description: "Azure DevOps project name. Required without pullRequestUrl.",
    },
    repository: {
        type: "string",
        description:
            "Azure DevOps repository name or ID. Required without pullRequestUrl.",
    },
    pullRequestId: {
        type: "integer",
        description: "Pull request ID. Required without pullRequestUrl.",
    },
    commitId: {
        type: "string",
        description:
            "Optional commit SHA within the pull request. Use the source commit returned by these tools to pin subsequent calls to the same PR iteration.",
    },
});

export const getPullRequestReviewStateTool = Object.freeze({
    name: "azure_devops_get_pull_request_review_state",
    description:
        "Get a compact, read-only Azure DevOps pull request review snapshot: PR metadata and head commit, reviewers, newest and active discussion threads, policy evaluations, build metadata exposed by policies, and blocking-policy gate counts. Prefer this over separate comment, PR metadata, and policy calls when reviewing a PR.",
    parameters: {
        type: "object",
        properties: {
            ...pullRequestReadProperties,
        },
        additionalProperties: false,
    },
    skipPermission: true,
});

export const getPullRequestCommentsTool = Object.freeze({
    name: "azure_devops_get_pull_request_comments",
    description:
        "Fetch Azure DevOps pull request discussion threads and comments, including thread status, file/line context, authors, dates, and replies. Accepts a PR URL or explicit organization/project/repository/PR fields. Authenticates with AzureAuth.",
    parameters: {
        type: "object",
        properties: {
            ...pullRequestReadProperties,
            status: {
                type: "string",
                enum: [
                    "all",
                    "active",
                    "fixed",
                    "wontFix",
                    "closed",
                    "byDesign",
                    "pending",
                    "unknown",
                ],
                default: "all",
                description: "Return only threads with this status.",
            },
            includeDeleted: {
                type: "boolean",
                default: false,
                description: "Include deleted threads and comments.",
            },
        },
        additionalProperties: false,
    },
    skipPermission: true,
});

export const resolvePullRequestCommentsTool = Object.freeze({
    name: "azure_devops_resolve_pull_request_comments",
    description:
        "Resolve selected Azure DevOps pull request discussion threads by setting their status to fixed. Requires explicit thread IDs, prevalidates every thread before mutation, skips already-fixed threads, and refuses to overwrite closed, won't-fix, by-design, deleted, or missing threads. Authenticates with AzureAuth.",
    parameters: {
        type: "object",
        properties: {
            ...pullRequestReadProperties,
            threadIds: {
                type: "array",
                minItems: 1,
                maxItems: 100,
                uniqueItems: true,
                items: {
                    type: "integer",
                    minimum: 1,
                },
                description:
                    "Azure DevOps discussion thread IDs to resolve. Obtain these from azure_devops_get_pull_request_comments.",
            },
        },
        required: ["threadIds"],
        additionalProperties: false,
    },
});

export const refreshArtifactsAuthTool = Object.freeze({
    name: "azure_devops_refresh_artifacts_auth",
    description:
        "Refresh cached Azure Artifacts credentials for feeds in an existing .npmrc or NuGet.config without modifying the config file. Uses artifacts-npm-credprovider for npm and Microsoft.Artifacts.CredentialProvider.NuGet.Tool for NuGet, after validating feed URLs against the supplied Azure DevOps organization and project.",
    parameters: {
        type: "object",
        properties: {
            organization: {
                type: "string",
                description: "Azure DevOps organization name or URL.",
            },
            project: {
                type: "string",
                description: "Azure DevOps project containing the feed.",
            },
            filePath: {
                type: "string",
                description:
                    "Path to an existing .npmrc or NuGet.config. Relative paths resolve from the active Copilot CLI working directory.",
            },
        },
        required: ["organization", "project", "filePath"],
        additionalProperties: false,
    },
});
