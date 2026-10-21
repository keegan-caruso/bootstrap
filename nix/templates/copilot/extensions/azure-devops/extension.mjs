// Extension: azure-devops
// Read and resolve Azure DevOps pull request threads and comments, aggregate
// review state, and refresh Azure Artifacts credentials.
//
// This file only composes and registers the four public tools. All business
// logic lives in the focused modules imported below so it can be unit tested
// without a live Copilot session or live Azure DevOps calls.

import { joinSession } from "@github/copilot-sdk/extension";
import { withCancellation, guardTool } from "./contracts.mjs";
import {
    getPullRequestCommentsTool,
    getPullRequestReviewStateTool,
    refreshArtifactsAuthTool,
    resolvePullRequestCommentsTool,
} from "./contracts.mjs";
import { getPullRequestReviewState } from "./review-state.mjs";
import { getPullRequestComments, resolvePullRequestComments } from "./comments.mjs";
import { refreshArtifactsAuth } from "./artifacts.mjs";
import { workingDirectoryFromEvents } from "./working-directory.mjs";

const session = await joinSession({
    tools: [
        {
            ...getPullRequestReviewStateTool,
            handler: guardTool(withCancellation(getPullRequestReviewState)),
        },
        {
            ...getPullRequestCommentsTool,
            handler: guardTool(withCancellation(getPullRequestComments)),
        },
        {
            ...resolvePullRequestCommentsTool,
            handler: guardTool(withCancellation(resolvePullRequestComments)),
        },
        {
            ...refreshArtifactsAuthTool,
            handler: guardTool(async (args, invocation) => {
                invocation?.signal?.throwIfAborted();
                const events = await session.getEvents();
                const workingDirectory = workingDirectoryFromEvents(events);
                return refreshArtifactsAuth(args, workingDirectory, { signal: invocation?.signal });
            }),
        },
    ],
});
