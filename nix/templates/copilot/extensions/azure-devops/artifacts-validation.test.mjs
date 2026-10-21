import assert from "node:assert/strict";
import test from "node:test";
import { testables } from "./artifacts.mjs";
import { guardTool } from "./contracts.mjs";

const own = "https://pkgs.dev.azure.com/org/project/_packaging/feed/npm/registry/";
const foreign = "https://pkgs.dev.azure.com/foreign/other/_packaging/feed/npm/registry/";

test("npm discovery ignores indented comments and non-registry settings", () => {
    const contents = `registry=${own}
  # @old:registry=${foreign}
  ; @old:registry=${foreign}
proxy=${foreign}
`;
    assert.deepEqual(testables.foreignArtifactsRegistries(contents, "org", "project"), []);
    assert.equal(testables.npmRegistries(contents, "org", "project").length, 1);
});

test("npm discovery uses effective assignments and handles quoted values and environment references", () => {
    const contents = `registry=${foreign}
registry="\${FEED}" # active registry
`;
    assert.deepEqual(testables.foreignArtifactsRegistries(contents, "org", "project", { FEED: own }), []);
    assert.equal(testables.npmRegistries(contents, "org", "project", { FEED: own }).length, 1);
    assert.throws(
        () => testables.npmRegistries(contents, "org", "project", {}),
        /environment variable FEED is not set/,
    );
});

test("NuGet discovery ignores commented sections and individual entries", () => {
    const contents = `<configuration>
<!-- <packageSources><add key="old" value="${own}" /></packageSources> -->
<packageSources>
  <!-- <add key="disabled" value="${own}" /> -->
  <add key="active" value="${own.replace("/npm/registry/", "/nuget/v3/index.json")}" />
</packageSources></configuration>`;
    assert.deepEqual(testables.nugetSources(contents, "org", "project").map(source => source.name), ["active"]);
    assert.throws(
        () => testables.nugetSources(`<packageSources><!-- <add key="old" value="${own}" />`, "org", "project"),
        /unterminated XML comment/,
    );
});

test("feed validation failures never expose embedded credentials", async () => {
    const credential = "synthetic-credential-for-validation";
    for (const url of [
        `https://user:${credential}@pkgs.dev.azure.com/org/project/_packaging/feed/npm/registry/`,
        `http://user:${credential}@pkgs.dev.azure.com/org/project/_packaging/feed/npm/registry/`,
    ]) {
        const handler = guardTool(() => testables.parseArtifactsFeedUrl(url));
        const result = await handler({});
        assert.equal(result.resultType, "failure");
        assert(!result.textResultForLlm.includes(credential));
        assert(!result.textResultForLlm.includes("user:"));
    }
});

test("feed path decoding preserves plus characters in project names", () => {
    for (const project of ["project+tools", "project%2Btools"]) {
        assert(testables.matchesArtifactsScope(own.replace("/project/", `/${project}/`), "org", "project+tools"));
    }
});
