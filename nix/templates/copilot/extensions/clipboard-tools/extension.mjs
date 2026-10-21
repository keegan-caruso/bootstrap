// Extension: clipboard-tools
// Exposes tools to copy text or exact file contents to the Linux clipboard.

import { joinSession } from "@github/copilot-sdk/extension";
import {
    copyFileTool,
    writeTextTool,
} from "./contracts.mjs";
import {
    errorMessage,
    readClipboardFile,
    resolveClipboardFilePath,
    workingDirectoryFromEvents,
    writeClipboard,
} from "./clipboard.mjs";

function success(message) {
    return { textResultForLlm: message, resultType: "success" };
}

function failure(error) {
    return { textResultForLlm: errorMessage(error), resultType: "failure" };
}

const session = await joinSession({
    tools: [
        {
            ...writeTextTool,
            handler: async ({ text }, invocation) => {
                try {
                    const command = await writeClipboard(Buffer.from(text, "utf8"), undefined, {
                        signal: invocation?.signal,
                    });
                    return success(`Copied ${Buffer.byteLength(text, "utf8")} bytes using ${command}.`);
                } catch (error) {
                    return failure(error);
                }
            },
        },
        {
            ...copyFileTool,
            handler: async ({ path }, invocation) => {
                try {
                    const signal = invocation?.signal;
                    signal?.throwIfAborted();
                    const events = await session.getEvents();
                    const resolvedPath = resolveClipboardFilePath(
                        path,
                        workingDirectoryFromEvents(events),
                    );
                    const content = await readClipboardFile(resolvedPath, { signal });
                    const command = await writeClipboard(content, undefined, { signal });
                    return success(`Copied ${content.length} bytes from ${resolvedPath} using ${command}.`);
                } catch (error) {
                    return failure(error);
                }
            },
        },
    ],
});
