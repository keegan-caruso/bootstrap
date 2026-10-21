// Shared response-shaping helpers: turning raw Azure DevOps REST payloads
// (identities, comments, threads, changes) into the compact shapes returned
// to the model, plus the URL builders every PR-scoped module needs.

export function identity(value) {
    if (!value) {
        return null;
    }
    return {
        id: value.id,
        displayName: value.displayName,
        uniqueName: value.uniqueName,
        url: value.url,
    };
}

export function simplifyComment(comment) {
    return {
        id: comment.id,
        parentCommentId: comment.parentCommentId ?? 0,
        author: identity(comment.author),
        content: comment.content ?? "",
        publishedDate: comment.publishedDate,
        lastUpdatedDate: comment.lastUpdatedDate,
        lastContentUpdatedDate: comment.lastContentUpdatedDate,
        commentType: comment.commentType,
        isDeleted: Boolean(comment.isDeleted),
        usersLiked: (comment.usersLiked ?? []).map(identity),
    };
}

export function simplifyThread(thread, includeDeleted) {
    const comments = (thread.comments ?? [])
        .filter((comment) => includeDeleted || !comment.isDeleted)
        .map(simplifyComment);

    return {
        id: thread.id,
        status: thread.status,
        isDeleted: Boolean(thread.isDeleted),
        publishedDate: thread.publishedDate,
        lastUpdatedDate: thread.lastUpdatedDate,
        threadContext: thread.threadContext ?? null,
        pullRequestThreadContext: thread.pullRequestThreadContext ?? null,
        properties: thread.properties ?? null,
        comments,
    };
}

export function pullRequestWebUrl(pullRequest) {
    const { organization, project, repository, pullRequestId } = pullRequest;
    return (
        `https://dev.azure.com/${encodeURIComponent(organization)}` +
        `/${encodeURIComponent(project)}/_git/${encodeURIComponent(repository)}` +
        `/pullrequest/${pullRequestId}`
    );
}

export function gitApiUrl(pullRequest, suffix) {
    const { organization, project, repository } = pullRequest;
    return new URL(
        `https://dev.azure.com/${encodeURIComponent(organization)}` +
        `/${encodeURIComponent(project)}/_apis/git/repositories/` +
        `${encodeURIComponent(repository)}${suffix}`,
    );
}
