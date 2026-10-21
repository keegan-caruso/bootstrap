export const maxClipboardFileBytes = 16 * 1024 * 1024;

export const writeTextTool = Object.freeze({
    name: "clipboard_write_text",
    description: "Writes the supplied string exactly to the current user's Linux clipboard.",
    parameters: {
        type: "object",
        properties: {
            text: {
                type: "string",
                description: "The exact text to place on the clipboard.",
            },
        },
        required: ["text"],
        additionalProperties: false,
    },
});

export const copyFileTool = Object.freeze({
    name: "clipboard_copy_file",
    description:
        "Copies the exact contents of a file up to 16 MiB to the current user's Linux clipboard.",
    parameters: {
        type: "object",
        properties: {
            path: {
                type: "string",
                minLength: 1,
                description:
                    "Absolute file path, or a path relative to the active Copilot CLI working directory.",
            },
        },
        required: ["path"],
        additionalProperties: false,
    },
});
