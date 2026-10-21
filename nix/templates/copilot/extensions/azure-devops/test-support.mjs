export function jsonResponse(status, body, headers = {}) {
    return {
        ok: status >= 200 && status < 300,
        status,
        statusText: `status-${status}`,
        headers: { get: (name) => headers[name.toLowerCase()] ?? null },
        text: async () => (typeof body === "string" ? body : JSON.stringify(body)),
        json: async () => body,
        body: { cancel: async () => {} },
    };
}
