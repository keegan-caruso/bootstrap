import assert from "node:assert/strict";
import { constants } from "node:fs";
import { mkdtemp, open, rm, unlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { readClipboardFile } from "./clipboard.mjs";
import { maxClipboardFileBytes } from "./contracts.mjs";

function fakeFile(content, size = content.length) {
    let position = 0;
    const state = { closed: false, requests: [], bytesRead: 0 };
    return {
        state,
        stat: async () => ({ isFile: () => true, size }),
        close: async () => { state.closed = true; },
        read: async (buffer, offset, length) => {
            state.requests.push(length);
            const bytesRead = Math.min(length, content.length - position);
            content.copy(buffer, offset, position, position + bytesRead);
            position += bytesRead;
            state.bytesRead += bytesRead;
            return { bytesRead };
        },
    };
}

test("bounded reads preserve binary bytes and open nonblocking", async () => {
    const content = Buffer.from([0, 255, 65, 10]);
    const file = fakeFile(content);
    const result = await readClipboardFile("test-file", {
        maxBytes: content.length,
        openImpl: async (_path, flags) => {
            assert.equal(flags, constants.O_RDONLY | constants.O_NONBLOCK);
            return file;
        },
    });
    assert.deepEqual(result, content);
    assert(file.state.closed);
});

test("the default limit accepts exactly 16 MiB and bounds a growing read to 16 MiB plus one", async () => {
    const limit = 16 * 1024 * 1024;
    assert.equal(maxClipboardFileBytes, limit);
    const content = Buffer.alloc(limit + 1, 65);
    const exact = fakeFile(content.subarray(0, limit));
    const result = await readClipboardFile("exact-limit", { openImpl: async () => exact });
    assert.equal(result.length, limit);
    assert.deepEqual(result, content.subarray(0, limit));
    assert(exact.state.closed);
    const growing = fakeFile(content, 0);
    await assert.rejects(readClipboardFile("growing-file", { openImpl: async () => growing }), /16777216-byte/);
    assert.equal(growing.state.bytesRead, limit + 1);
    assert(growing.state.closed);
});

test("an initially oversized file is rejected without reading any content", async () => {
    const file = fakeFile(Buffer.alloc(9));
    await assert.rejects(readClipboardFile("large-file", {
        openImpl: async () => file, maxBytes: 8,
    }), /8-byte clipboard limit/);
    assert.equal(file.state.bytesRead, 0);
    assert(file.state.closed);
});

test("non-regular files and read errors close the opened handle", async () => {
    const directory = fakeFile(Buffer.alloc(0));
    directory.stat = async () => ({ isFile: () => false });
    await assert.rejects(readClipboardFile("directory", { openImpl: async () => directory }), /not a file/);
    assert(directory.state.closed);
    const file = fakeFile(Buffer.from("data"));
    file.read = async () => { throw new Error("read failed"); };
    await assert.rejects(readClipboardFile("file", { openImpl: async () => file }), /read failed/);
    assert(file.state.closed);
});

test("cancellation stops bounded reads and closes the file", async () => {
    const controller = new AbortController();
    const file = fakeFile(Buffer.alloc(128 * 1024));
    const read = file.read;
    file.read = async (...args) => {
        const result = await read(...args);
        controller.abort();
        return result;
    };
    await assert.rejects(readClipboardFile("file", {
        openImpl: async () => file, signal: controller.signal,
    }), { name: "AbortError" });
    assert.equal(file.state.requests.length, 1);
    assert(file.state.closed);
    await assert.rejects(readClipboardFile("file", {
        openImpl: () => assert.fail("cancelled read must not open a file"),
        signal: controller.signal,
    }), { name: "AbortError" });
});

test("replacing the path cannot change which opened file is copied", async (t) => {
    const root = await mkdtemp(join(tmpdir(), "clipboard-file-test-"));
    t.after(() => rm(root, { recursive: true, force: true }));
    const path = join(root, "file");
    await writeFile(path, "original\n");
    const result = await readClipboardFile(path, {
        openImpl: async (...args) => {
            const file = await open(...args);
            await unlink(path);
            await writeFile(path, "replacement\n");
            return file;
        },
    });
    assert.equal(result.toString(), "original\n");
});
