import assert from "node:assert/strict";
import test from "node:test";
import {
    authorizationHeader,
    azureDevOpsAuthorizationValue,
    credentialProviderEnvironment,
} from "./auth.mjs";

test("azureDevOpsAuthorizationValue requests the complete header value from AzureAuth", async () => {
    const value = await azureDevOpsAuthorizationValue(async (file, args, options) => {
        assert.equal(file, "azureauth");
        assert.deepEqual(args, ["ado", "token", "--output", "headervalue"]);
        assert.equal(options.timeout, 120_000);
        return { stdout: "  Bearer my-token \n" };
    });
    assert.equal(value, "Bearer my-token");
});

test("azureDevOpsAuthorizationValue does not pass the Copilot agent session to AzureAuth", async () => {
    const originalSessionId = process.env.COPILOT_AGENT_SESSION_ID;
    process.env.COPILOT_AGENT_SESSION_ID = "copilot/session/invalid";

    try {
        await azureDevOpsAuthorizationValue(async (_file, _args, options) => {
            assert.equal(options.env.COPILOT_AGENT_SESSION_ID, undefined);
            return { stdout: "Bearer token" };
        });
    } finally {
        if (originalSessionId === undefined) {
            delete process.env.COPILOT_AGENT_SESSION_ID;
        } else {
            process.env.COPILOT_AGENT_SESSION_ID = originalSessionId;
        }
    }
});

test("azureDevOpsAuthorizationValue rejects an empty or invalid header without echoing it", async () => {
    await assert.rejects(
        azureDevOpsAuthorizationValue(async () => ({ stdout: "" })),
        /Azure DevOps AzureAuth token acquisition failed.*empty or invalid Authorization header/,
    );
    await assert.rejects(
        azureDevOpsAuthorizationValue(async () => ({ stdout: "Bearer secret\nextra" })),
        (error) => !error.message.includes("secret"),
    );
});

test("azureDevOpsAuthorizationValue reports a missing AzureAuth executable", async () => {
    await assert.rejects(
        azureDevOpsAuthorizationValue(async () => {
            const error = new Error("spawn azureauth ENOENT");
            error.code = "ENOENT";
            throw error;
        }),
        /AzureAuth is not installed or is not on PATH/,
    );
});

test("azureDevOpsAuthorizationValue reports AzureAuth failures without az login guidance", async () => {
    await assert.rejects(
        azureDevOpsAuthorizationValue(async () => {
            const error = new Error("command failed");
            error.stderr = "No cached AzureAuth account";
            throw error;
        }),
        (error) =>
            /AzureAuth token acquisition failed.*No cached AzureAuth account/.test(error.message) &&
            !error.message.includes("az login"),
    );
});

test("azureDevOpsAuthorizationValue preserves AAD failures", async () => {
    await assert.rejects(
        azureDevOpsAuthorizationValue(async () => {
            const error = new Error("command failed");
            error.stderr = "AADSTS901001: Invalid request.";
            throw error;
        }),
        (error) =>
            /AzureAuth token acquisition failed/.test(error.message) &&
            /AADSTS901001/.test(error.message),
    );
});

test("authorizationHeader preserves the AzureAuth scheme for AAD and PAT credentials", async () => {
    const header = await authorizationHeader(async () => "Bearer abc123");
    assert.equal(header, "Bearer abc123");
    assert.equal(await authorizationHeader(async () => "Basic cGF0"), "Basic cGF0");
});

test("credentialProviderEnvironment strips every known credential-provider variable", () => {
    const sourceEnv = {
        PATH: "/usr/bin",
        ARTIFACTS_CREDENTIALPROVIDER_ACCESSTOKEN: "leaked",
        VSS_NUGET_ACCESSTOKEN: "leaked-too",
    };
    const sanitized = credentialProviderEnvironment(sourceEnv);
    assert.equal(sanitized.PATH, "/usr/bin");
    assert.equal(sanitized.ARTIFACTS_CREDENTIALPROVIDER_ACCESSTOKEN, undefined);
    assert.equal(sanitized.VSS_NUGET_ACCESSTOKEN, undefined);
    // The source environment object itself must be untouched.
    assert.equal(sourceEnv.ARTIFACTS_CREDENTIALPROVIDER_ACCESSTOKEN, "leaked");
});
