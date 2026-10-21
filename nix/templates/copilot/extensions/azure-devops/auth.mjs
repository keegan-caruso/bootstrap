// Azure DevOps authentication via AzureAuth and credential-provider environment
// sanitization.

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { credentialProviderBuildVariables } from "./contracts.mjs";

const execFileAsync = promisify(execFile);
const maxAuthenticationErrorCharacters = 4_000;

function azureAuthEnvironment(sourceEnv = process.env) {
    const environment = { ...sourceEnv };
    delete environment.COPILOT_AGENT_SESSION_ID;
    return environment;
}

function authenticationErrorDetail(error) {
    const detail =
        typeof error?.stderr === "string" && error.stderr.trim()
            ? error.stderr.trim()
            : error instanceof Error
              ? error.message
              : String(error);
    return detail.slice(0, maxAuthenticationErrorCharacters);
}

function authenticationFailureMessage(error) {
    const detail = authenticationErrorDetail(error);
    if (error?.code === "ENOENT") {
        return "Azure DevOps authentication failed because AzureAuth is not installed or is not on PATH.";
    }
    if (error?.killed || error?.signal || error?.code === "ETIMEDOUT") {
        return `Azure DevOps authentication timed out while acquiring an AzureAuth token. ${detail}`;
    }
    return `Azure DevOps AzureAuth token acquisition failed. ${detail}`;
}

/**
 * Retrieves the Azure DevOps Authorization header value from AzureAuth.
 * @param {typeof execFileAsync} execFileImpl injectable for tests.
 */
export async function azureDevOpsAuthorizationValue(execFileImpl = execFileAsync, { signal } = {}) {
    signal?.throwIfAborted();
    try {
        const { stdout } = await execFileImpl(
            "azureauth",
            ["ado", "token", "--output", "headervalue"],
            {
                env: azureAuthEnvironment(),
                maxBuffer: 2 * 1024 * 1024,
                timeout: 120_000,
                signal,
            },
        );
        const headerValue = stdout.trim();
        if (!/^(?:Bearer|Basic) \S+$/i.test(headerValue)) {
            throw new Error("AzureAuth returned an empty or invalid Authorization header value.");
        }
        return headerValue;
    } catch (error) {
        signal?.throwIfAborted();
        throw new Error(authenticationFailureMessage(error));
    }
}

/** Builds the `Authorization` header value for Azure DevOps REST calls. */
export async function authorizationHeader(getValue = azureDevOpsAuthorizationValue, options = {}) {
    return getValue(undefined, options);
}

/**
 * Copy of process.env with Azure Artifacts credential-provider variables
 * removed, so refreshing one feed's credentials cannot inherit an ambient
 * token scoped to a different feed or organization.
 */
export function credentialProviderEnvironment(sourceEnv = process.env) {
    const environment = { ...sourceEnv };
    for (const name of credentialProviderBuildVariables) {
        delete environment[name];
    }
    return environment;
}
