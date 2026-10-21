import assert from "node:assert/strict";
import { link, mkdir, mkdtemp, readFile, rm, stat, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { refreshArtifactsAuth } from "./artifacts.mjs";

const feed = "https://pkgs.dev.azure.com/org/project/_packaging/feed/npm/registry/";
const foreign = "https://pkgs.dev.azure.com/foreign/other/_packaging/feed/npm/registry/";

async function fixture(t) {
    const root = await mkdtemp(join(tmpdir(), "npm-auth-test-"));
    t.after(() => rm(root, { recursive: true, force: true }));
    const home = join(root, "home");
    await mkdir(home);
    const input = join(root, ".npmrc");
    const contents = `registry=${feed}\n`;
    await writeFile(input, contents);
    const environment = { HOME: home, PATH: process.env.PATH };
    return {
        root, home, input, contents, environment,
        args: { organization: "org", project: "project", filePath: input },
    };
}

test("npm refresh exposes only validated registries in an isolated workspace and HOME", async (t) => {
    const f = await fixture(t);
    await writeFile(join(f.root, ".yarnrc.yml"), `npmRegistryServer: ${foreign}\n`);
    await writeFile(join(f.home, ".yarnrc.yml"), `npmRegistryServer: ${foreign}\n`);
    f.environment.NPM_CONFIG_REGISTRY = foreign;
    f.environment.npm_config_global = "true";
    let workspace;
    const result = await refreshArtifactsAuth(f.args, f.root, {
        environment: f.environment,
        execFileImpl: async (command, args, options) => {
            assert.equal(command, "artifacts-npm-credprovider");
            workspace = options.cwd;
            assert.notEqual(workspace, f.root);
            assert.equal(options.env.HOME, workspace);
            assert.equal(options.env.USERPROFILE, workspace);
            assert.equal(options.env.NPM_CONFIG_USERCONFIG, join(f.home, ".npmrc"));
            assert.equal(options.env.NPM_CONFIG_REGISTRY, undefined);
            assert.equal(options.env.npm_config_global, undefined);
            assert.equal(options.env.XDG_DATA_HOME, join(f.home, ".local", "share"));
            assert.equal(options.env.DOTNET_CLI_HOME, f.home);
            assert.equal(options.env.PREFERRED_WORKSPACE_MANAGER, "npm");
            assert.equal(args[1], join(workspace, ".npmrc"));
            const snapshot = await readFile(args[1], "utf8");
            assert(snapshot.includes(feed));
            assert(!snapshot.includes(foreign));
            assert.equal(JSON.parse(await readFile(join(workspace, "package.json"), "utf8")).private, true);
            await assert.rejects(stat(join(workspace, ".yarnrc.yml")), { code: "ENOENT" });
        },
    });
    assert.equal(JSON.parse(result).sourceCount, 1);
    assert.equal(await readFile(f.input, "utf8"), f.contents);
    assert.equal(await readFile(join(f.home, ".yarnrc.yml"), "utf8"), `npmRegistryServer: ${foreign}\n`);
    await assert.rejects(stat(workspace), { code: "ENOENT" });
});

test("npm refresh refuses user config output aliases before starting the provider", async (t) => {
    const f = await fixture(t);
    const aliases = [f.input, join(f.root, "symlink.npmrc"), join(f.root, "hardlink.npmrc")];
    await symlink(f.input, aliases[1]);
    await link(f.input, aliases[2]);
    for (const output of aliases) {
        await assert.rejects(refreshArtifactsAuth(f.args, f.root, {
            environment: { ...f.environment, NPM_CONFIG_USERCONFIG: output },
            execFileImpl: () => assert.fail("provider must not start"),
        }), /also the credential provider's user config output/);
    }
    await writeFile(join(f.home, ".npmrc"), f.contents);
    await assert.rejects(refreshArtifactsAuth({ ...f.args, filePath: join(f.home, ".npmrc") }, f.root, {
        environment: f.environment,
        execFileImpl: () => assert.fail("provider must not start"),
    }), /also the credential provider's user config output/);
    assert.equal(await readFile(f.input, "utf8"), f.contents);
});

test("npm provider failure removes its isolated workspace", async (t) => {
    const f = await fixture(t);
    let workspace;
    await assert.rejects(refreshArtifactsAuth(f.args, f.root, {
        environment: f.environment,
        execFileImpl: async (_command, _args, options) => {
            workspace = options.cwd;
            throw new Error("provider failed");
        },
    }), /provider failed/);
    await assert.rejects(stat(workspace), { code: "ENOENT" });
});

test("credential refresh passes cancellation to providers and stops between NuGet sources", async (t) => {
    const f = await fixture(t);
    const controller = new AbortController();
    let calls = 0;
    await refreshArtifactsAuth(f.args, f.root, {
        environment: f.environment,
        signal: controller.signal,
        execFileImpl: async (_command, _args, options) => assert.equal(options.signal, controller.signal),
    });
    const config = join(f.root, "NuGet.config");
    await writeFile(config, `<configuration><packageSources>
<add key="first" value="${feed.replace("/npm/registry/", "/nuget/v3/index.json")}" />
<add key="second" value="${feed.replace("/feed/", "/other/").replace("/npm/registry/", "/nuget/v3/index.json")}" />
</packageSources></configuration>`);
    await assert.rejects(refreshArtifactsAuth({ ...f.args, filePath: config }, f.root, {
        environment: f.environment,
        signal: controller.signal,
        execFileImpl: async (_command, _args, options) => {
            assert.equal(options.signal, controller.signal);
            calls += 1;
            controller.abort();
        },
    }), { name: "AbortError" });
    assert.equal(calls, 1);
});
