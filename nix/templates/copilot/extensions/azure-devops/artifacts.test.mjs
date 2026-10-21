import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import {
    artifactsRefreshTimeoutMs,
    refreshArtifactsAuth,
    testables,
} from "./artifacts.mjs";

const {
    credentialProviderErrorDetail,
    foreignArtifactsRegistries,
    matchesArtifactsScope,
    npmRegistries,
    nugetSources,
    parseArtifactsFeedUrl,
} = testables;

async function scratchDirectory(t) {
    const directory = await mkdtemp(join(tmpdir(), "artifacts-test-"));
    t.after(() => rm(directory, { recursive: true, force: true }));
    return directory;
}

test("parseArtifactsFeedUrl recognizes pkgs.dev.azure.com feeds", () => {
    const feed = parseArtifactsFeedUrl(
        "https://pkgs.dev.azure.com/my-org/my-project/_packaging/my-feed/npm/registry/",
    );
    assert.equal(feed.organization, "my-org");
    assert.equal(feed.project, "my-project");
});

test("parseArtifactsFeedUrl recognizes organization-scoped feeds (no project segment)", () => {
    const feed = parseArtifactsFeedUrl(
        "https://pkgs.dev.azure.com/my-org/_packaging/my-feed/nuget/v3/index.json",
    );
    assert.equal(feed.organization, "my-org");
    assert.equal(feed.project, null);
});

test("parseArtifactsFeedUrl recognizes *.pkgs.visualstudio.com feeds", () => {
    const feed = parseArtifactsFeedUrl(
        "https://my-org.pkgs.visualstudio.com/my-project/_packaging/my-feed/npm/registry/",
    );
    assert.equal(feed.organization, "my-org");
    assert.equal(feed.project, "my-project");
});

test("parseArtifactsFeedUrl returns null for non-Artifacts URLs", () => {
    assert.equal(parseArtifactsFeedUrl("https://example.com/not-a-feed"), null);
    assert.equal(parseArtifactsFeedUrl("not a url"), null);
});

test("parseArtifactsFeedUrl rejects a non-HTTPS Azure Artifacts feed URL", () => {
    assert.throws(
        () =>
            parseArtifactsFeedUrl(
                "http://pkgs.dev.azure.com/my-org/my-project/_packaging/feed/npm/registry/",
            ),
        /must use HTTPS/,
    );
});

test("parseArtifactsFeedUrl rejects an Azure Artifacts feed URL with embedded credentials", () => {
    assert.throws(
        () =>
            parseArtifactsFeedUrl(
                "https://user:pass@pkgs.dev.azure.com/my-org/my-project/_packaging/feed/npm/registry/",
            ),
        /must not embed credentials/,
    );
});

test("parseArtifactsFeedUrl rejects an Azure Artifacts feed URL with an unexpected port", () => {
    assert.throws(
        () =>
            parseArtifactsFeedUrl(
                "https://pkgs.dev.azure.com:8443/my-org/my-project/_packaging/feed/npm/registry/",
            ),
        /must not specify a port/,
    );
});

test("matchesArtifactsScope requires organization match and optional project match", () => {
    const url = "https://pkgs.dev.azure.com/my-org/my-project/_packaging/feed/npm/registry/";
    assert.equal(matchesArtifactsScope(url, "my-org", "my-project"), true);
    assert.equal(matchesArtifactsScope(url, "my-org", "other-project"), false);
    assert.equal(matchesArtifactsScope(url, "other-org", "my-project"), false);

    const orgScoped = "https://pkgs.dev.azure.com/my-org/_packaging/feed/nuget/v3/index.json";
    assert.equal(matchesArtifactsScope(orgScoped, "my-org", "any-project"), true);
});

test("npmRegistries extracts matching registry auth keys from .npmrc contents", () => {
    const contents = [
        "@my-scope:registry=https://pkgs.dev.azure.com/my-org/my-project/_packaging/feed/npm/registry/",
        "//pkgs.dev.azure.com/my-org/my-project/_packaging/feed/npm/registry/:_authToken=ignored",
        "registry=https://registry.npmjs.org/",
    ].join("\n");

    const registries = npmRegistries(contents, "my-org", "my-project");
    assert.deepEqual(registries, [
        "//pkgs.dev.azure.com/my-org/my-project/_packaging/feed/npm/registry/",
    ]);
});

test("npmRegistries excludes feeds for a different organization or project", () => {
    const contents = "registry=https://pkgs.dev.azure.com/other-org/proj/_packaging/feed/npm/registry/";
    assert.deepEqual(npmRegistries(contents, "my-org", "my-project"), []);
});

test("foreignArtifactsRegistries reports Azure Artifacts npm feeds outside the requested org/project", () => {
    const contents = [
        "registry=https://pkgs.dev.azure.com/my-org/my-project/_packaging/feed/npm/registry/",
        "@other-scope:registry=https://pkgs.dev.azure.com/my-org/other-project/_packaging/feed2/npm/registry/",
        "registry=https://registry.npmjs.org/",
    ].join("\n");

    const foreign = foreignArtifactsRegistries(contents, "my-org", "my-project");
    assert.deepEqual(foreign, [
        "https://pkgs.dev.azure.com/my-org/other-project/_packaging/feed2/npm/registry/",
    ]);
});

test("foreignArtifactsRegistries is empty when every Azure Artifacts feed matches the scope", () => {
    const contents =
        "registry=https://pkgs.dev.azure.com/my-org/my-project/_packaging/feed/npm/registry/\n" +
        "registry=https://registry.npmjs.org/\n";
    assert.deepEqual(foreignArtifactsRegistries(contents, "my-org", "my-project"), []);
});

test("npm registry parsing rejects recognized Azure Artifacts feeds over HTTP", () => {
    const contents =
        "registry=http://pkgs.dev.azure.com/my-org/my-project/_packaging/feed/npm/registry/";
    assert.throws(
        () => npmRegistries(contents, "my-org", "my-project"),
        /must use HTTPS/,
    );
});

test("nugetSources parses <add key=.. value=..> entries scoped to the org/project", () => {
    const contents = `<?xml version="1.0"?>
<configuration>
  <packageSources>
    <add key="MyFeed" value="https://pkgs.dev.azure.com/my-org/my-project/_packaging/feed/nuget/v3/index.json" />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
</configuration>`;

    const sources = nugetSources(contents, "my-org", "my-project");
    assert.deepEqual(sources, [
        {
            name: "MyFeed",
            url: "https://pkgs.dev.azure.com/my-org/my-project/_packaging/feed/nuget/v3/index.json",
        },
    ]);
});

test("nugetSources throws when there is no packageSources section", () => {
    assert.throws(
        () => nugetSources("<configuration></configuration>", "my-org", "my-project"),
        /packageSources section/,
    );
});

test("refreshArtifactsAuth resolves a relative filePath against the supplied working directory", async (t) => {
    const scratchDir = await scratchDirectory(t);
    await writeFile(
        join(scratchDir, ".npmrc"),
        "registry=https://pkgs.dev.azure.com/my-org/my-project/_packaging/feed/npm/registry/\n",
        "utf8",
    );

    await assert.rejects(
        refreshArtifactsAuth(
            { organization: "my-org", project: "my-project", filePath: ".npmrc" },
            scratchDir,
            {
                execFileImpl: async () => {
                    const error = new Error("mock provider failure");
                    error.stderr = "mock provider failure";
                    throw error;
                },
            },
        ),
        /artifacts-npm-credprovider was unable to refresh credentials.*mock provider failure/,
    );
});

test("refreshArtifactsAuth reports NuGet source progress and provider diagnostics", async (t) => {
    const scratchDir = await scratchDirectory(t);
    await writeFile(
        join(scratchDir, "NuGet.config"),
        `<configuration><packageSources>
          <add key="First" value="https://pkgs.dev.azure.com/my-org/my-project/_packaging/first/nuget/v3/index.json" />
          <add key="Second" value="https://pkgs.dev.azure.com/my-org/my-project/_packaging/second/nuget/v3/index.json" />
        </packageSources></configuration>`,
        "utf8",
    );
    let invocationCount = 0;

    await assert.rejects(
        refreshArtifactsAuth(
            { organization: "my-org", project: "my-project", filePath: "NuGet.config" },
            scratchDir,
            {
                execFileImpl: async () => {
                    invocationCount += 1;
                    if (invocationCount === 2) {
                        const error = new Error("provider failed");
                        error.stderr = "interactive authentication failed";
                        throw error;
                    }
                    return { stdout: "" };
                },
            },
        ),
        /source 'Second' after completing 1 of 2 sources.*interactive authentication failed/,
    );
});

test("refreshArtifactsAuth applies the remaining total budget to provider calls", async (t) => {
    const scratchDir = await scratchDirectory(t);
    await writeFile(
        join(scratchDir, ".npmrc"),
        "registry=https://pkgs.dev.azure.com/my-org/my-project/_packaging/feed/npm/registry/\n",
        "utf8",
    );
    let commandTimeout;

    await refreshArtifactsAuth(
        { organization: "my-org", project: "my-project", filePath: ".npmrc" },
        scratchDir,
        {
            totalTimeoutMs: 2_000,
            execFileImpl: async (_file, _args, options) => {
                commandTimeout = options.timeout;
                return { stdout: "" };
            },
        },
    );

    assert.ok(commandTimeout > 0 && commandTimeout <= 2_000);
    assert.equal(artifactsRefreshTimeoutMs, 180_000);
});

test("credential provider diagnostics redact common credential shapes", () => {
    const error = new Error("failed");
    error.stderr =
        'Authorization: Bearer secret-value {"accessToken":"secret","password":"also-secret"}';
    const detail = credentialProviderErrorDetail(error);
    assert.doesNotMatch(detail, /secret-value|also-secret|"secret"/);
    assert.match(detail, /\[redacted\]/);
});

test("refreshArtifactsAuth rejects a missing file with a clear error", async (t) => {
    const scratchDir = await scratchDirectory(t);
    await assert.rejects(
        refreshArtifactsAuth(
            { organization: "my-org", project: "my-project", filePath: "does-not-exist.npmrc" },
            scratchDir,
        ),
        /Unable to read does-not-exist\.npmrc/,
    );
});

test("refreshArtifactsAuth rejects a file with no matching Azure Artifacts feed", async (t) => {
    const scratchDir = await scratchDirectory(t);
    await writeFile(join(scratchDir, ".npmrc"), "registry=https://registry.npmjs.org/\n", "utf8");

    await assert.rejects(
        refreshArtifactsAuth(
            { organization: "my-org", project: "my-project", filePath: ".npmrc" },
            scratchDir,
        ),
        /No Azure Artifacts npm registry for my-org\/my-project/,
    );
});

test("refreshArtifactsAuth rejects a mixed-scope .npmrc referencing a feed outside the requested org/project", async (t) => {
    const scratchDir = await scratchDirectory(t);
    await writeFile(
        join(scratchDir, ".npmrc"),
        [
            "registry=https://pkgs.dev.azure.com/my-org/my-project/_packaging/feed/npm/registry/",
            "@foreign-scope:registry=https://pkgs.dev.azure.com/other-org/other-project/_packaging/feed2/npm/registry/",
            "registry=https://registry.npmjs.org/",
        ].join("\n"),
        "utf8",
    );

    await assert.rejects(
        refreshArtifactsAuth(
            { organization: "my-org", project: "my-project", filePath: ".npmrc" },
            scratchDir,
        ),
        /references Azure Artifacts npm feed outside my-org\/my-project.*other-org\/other-project/,
    );
});

test("refreshArtifactsAuth rejects an unsupported file name", async (t) => {
    const scratchDir = await scratchDirectory(t);
    await writeFile(join(scratchDir, "config.txt"), "irrelevant", "utf8");

    await assert.rejects(
        refreshArtifactsAuth(
            { organization: "my-org", project: "my-project", filePath: "config.txt" },
            scratchDir,
        ),
        /must point to an existing \.npmrc or NuGet\.config file/,
    );
});
