// Refreshes cached Azure Artifacts credentials for feeds referenced by an
// existing .npmrc or NuGet.config, without modifying the config file itself.
// Delegates to the ecosystem credential-provider tools rather than talking to
// Azure DevOps directly.

import { execFile } from "node:child_process";
import { mkdtemp, readFile, realpath, rm, stat, writeFile } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { basename, join } from "node:path";
import { promisify } from "node:util";
import { credentialProviderEnvironment } from "./auth.mjs";
import { normalizeOrganization, requireNonEmptyString } from "./validation.mjs";
import { resolveAgainstWorkingDirectory } from "./working-directory.mjs";

const execFileAsync = promisify(execFile);
export const credentialProviderTimeoutMs = 120_000;
export const artifactsRefreshTimeoutMs = 180_000;
const maxCredentialProviderErrorCharacters = 2_000;

function credentialProviderErrorDetail(error) {
    const detail =
        typeof error?.stderr === "string" && error.stderr.trim()
            ? error.stderr.trim()
            : error instanceof Error
              ? error.message
              : String(error);
    return detail
        .replace(/(authorization:\s*bearer\s+)\S+/gi, "$1[redacted]")
        .replace(/("(?:accessToken|password|token)"\s*:\s*")[^"]+/gi, "$1[redacted]")
        .replace(/(https?:\/\/)[^/@\s]+@/gi, "$1[redacted]@")
        .slice(0, maxCredentialProviderErrorCharacters);
}

function remainingTimeout(deadline, description) {
    const remaining = deadline - Date.now();
    if (remaining <= 0) {
        throw new Error(
            `Azure Artifacts credential refresh exceeded its ${artifactsRefreshTimeoutMs / 1000}-second total time budget ${description}.`,
        );
    }
    return Math.min(credentialProviderTimeoutMs, remaining);
}

function decodePathPart(value) {
    return decodeURIComponent(value);
}

function parseArtifactsFeedUrl(value) {
    let url;
    try {
        url = new URL(value);
    } catch {
        return null;
    }

    const hostname = url.hostname.toLowerCase();
    const parts = url.pathname.split("/").filter(Boolean).map(decodePathPart);
    const packagingIndex = parts.findIndex((part) => part.toLowerCase() === "_packaging");
    if (packagingIndex < 0) {
        return null;
    }

    let organization;
    let project;
    if (hostname === "pkgs.dev.azure.com") {
        organization = parts[0];
        project = packagingIndex > 1 ? parts[1] : null;
    } else if (hostname.endsWith(".pkgs.visualstudio.com")) {
        organization = hostname.slice(0, -".pkgs.visualstudio.com".length);
        project = packagingIndex > 0 ? parts[0] : null;
    } else {
        return null;
    }

    if (!organization) {
        return null;
    }

    // Recognized as an Azure Artifacts feed URL from here on - hold it to a
    // higher security bar than an arbitrary registry, since credentials are
    // about to be minted for it. A non-HTTPS scheme, embedded credentials,
    // or a non-default port are all signs of a misconfigured or spoofed
    // feed URL, so we refuse clearly rather than silently proceeding.
    if (url.protocol !== "https:") {
        throw new Error(
            `Azure Artifacts feed URL must use HTTPS (found "${url.protocol.replace(":", "")}").`,
        );
    }
    if (url.username || url.password) {
        throw new Error("Azure Artifacts feed URL must not embed credentials.");
    }
    if (url.port !== "") {
        throw new Error("Azure Artifacts feed URL must not specify a port.");
    }

    return { url, organization, project };
}

function matchesArtifactsScope(value, organization, project) {
    const feed = parseArtifactsFeedUrl(value);
    if (!feed || feed.organization.toLowerCase() !== organization.toLowerCase()) {
        return false;
    }

    return !feed.project || feed.project.toLowerCase() === project.toLowerCase();
}

function npmRegistryValues(contents, environment) {
    const values = new Map();
    for (const line of contents.split(/\r?\n/)) {
        const trimmed = line.trim();
        if (!trimmed || /^[#;]/.test(trimmed)) {
            continue;
        }
        const assignment = /^((?:@[^:\s=]+:)?registry)\s*=\s*(.*)$/i.exec(trimmed);
        if (!assignment) {
            continue;
        }
        let value = assignment[2].trim();
        if (/^["']/.test(value)) {
            const quoted = /^(["'])(.*?)\1\s*(?:[#;].*)?$/.exec(value);
            if (!quoted) {
                throw new Error("Invalid quoted npm registry value.");
            }
            value = quoted[2];
        } else {
            value = value.replace(/\s+[#;].*$/, "").trim();
        }
        value = value.replace(/\$\{([^}]+)\}/g, (_match, name) => {
            if (environment[name] === undefined) {
                throw new Error(`The npm registry environment variable ${name} is not set.`);
            }
            return environment[name];
        });
        values.set(assignment[1].toLowerCase(), value);
    }
    return [...values.values()];
}

function npmRegistries(contents, organization, project, environment = process.env) {
    const registries = new Map();
    for (const value of npmRegistryValues(contents, environment)) {
        const feed = parseArtifactsFeedUrl(value);
        if (
            !feed ||
            !feed.url.pathname.toLowerCase().includes("/npm/registry") ||
            !matchesArtifactsScope(value, organization, project)
        ) {
            continue;
        }

        const pathname = feed.url.pathname.endsWith("/") ? feed.url.pathname : `${feed.url.pathname}/`;
        const authKey = `//${feed.url.host}${pathname}`;
        registries.set(authKey.toLowerCase(), authKey);
    }
    return [...registries.values()];
}

/**
 * Finds Azure Artifacts npm registry URLs in `contents` that belong to a
 * *different* organization or project than requested. `artifacts-npm-
 * credprovider` operates on the whole config file at once, so if such a
 * foreign feed is present we must refuse rather than let the credential
 * provider mint or refresh credentials for it as a side effect of this call.
 */
function foreignArtifactsRegistries(contents, organization, project, environment = process.env) {
    const foreign = new Map();
    for (const value of npmRegistryValues(contents, environment)) {
        const feed = parseArtifactsFeedUrl(value);
        if (!feed || !feed.url.pathname.toLowerCase().includes("/npm/registry")) {
            continue;
        }
        if (matchesArtifactsScope(value, organization, project)) {
            continue;
        }
        const safeUrl = feed.url.origin + feed.url.pathname;
        foreign.set(safeUrl.toLowerCase(), safeUrl);
    }
    return [...foreign.values()];
}

async function npmProviderEnvironment(filePath, workingDirectory, environment) {
    const home = environment.HOME || environment.USERPROFILE || homedir();
    const userConfig = resolveAgainstWorkingDirectory(
        environment.NPM_CONFIG_USERCONFIG ?? environment.npm_config_userconfig ?? join(home, ".npmrc"),
        workingDirectory,
    );
    let outputStat;
    try {
        outputStat = await stat(userConfig);
    } catch (error) {
        if (error.code !== "ENOENT") {
            throw error;
        }
    }
    const inputStat = await stat(filePath);
    if (outputStat && inputStat.dev === outputStat.dev && inputStat.ino === outputStat.ino) {
        throw new Error(
            "The supplied .npmrc is also the credential provider's user config output. " +
            "Use a separate project .npmrc so refreshing credentials cannot modify the supplied file.",
        );
    }
    const result = credentialProviderEnvironment(environment);
    for (const key of Object.keys(result)) {
        if (/^npm_config_/i.test(key)) {
            delete result[key];
        }
    }
    return {
        ...result,
        NPM_CONFIG_USERCONFIG: userConfig,
        PREFERRED_WORKSPACE_MANAGER: "npm",
        XDG_CACHE_HOME: environment.XDG_CACHE_HOME || join(home, ".cache"),
        XDG_CONFIG_HOME: environment.XDG_CONFIG_HOME || join(home, ".config"),
        XDG_DATA_HOME: environment.XDG_DATA_HOME || join(home, ".local", "share"),
        DOTNET_CLI_HOME: environment.DOTNET_CLI_HOME || home,
    };
}

async function refreshNpmAuth(
    filePath,
    contents,
    organization,
    project,
    { execFileImpl, deadline, signal, environment, workingDirectory },
) {
    const foreign = foreignArtifactsRegistries(contents, organization, project, environment);
    if (foreign.length > 0) {
        throw new Error(
            `${filePath} references Azure Artifacts npm ${foreign.length === 1 ? "feed" : "feeds"} outside ` +
                `${organization}/${project}: ${foreign.join(", ")}. Refusing to refresh credentials for the ` +
                `whole file because artifacts-npm-credprovider processes every registry it contains. Split ` +
                `unrelated feeds into a separate .npmrc, or call this tool once per organization/project.`,
        );
    }

    const registries = npmRegistries(contents, organization, project, environment);
    if (registries.length === 0) {
        throw new Error(
            `No Azure Artifacts npm registry for ${organization}/${project} was found in ${filePath}.`,
        );
    }

    const providerEnv = await npmProviderEnvironment(filePath, workingDirectory, environment);
    signal?.throwIfAborted();
    const workspace = await mkdtemp(join(tmpdir(), "copilot-npm-auth-"));
    try {
        const config = join(workspace, ".npmrc");
        await writeFile(join(workspace, "package.json"), '{"private":true}\n', { mode: 0o600 });
        await writeFile(
            config,
            registries.map((registry, index) => `@feed-${index}:registry=https:${registry}`).join("\n") + "\n",
            { mode: 0o600 },
        );
        // Only the validated registry snapshot is discoverable; auth caches and
        // the separate user npm credential output retain their normal locations.
        try {
            signal?.throwIfAborted();
            await execFileImpl("artifacts-npm-credprovider", ["--config-file", config], {
                cwd: workspace,
                env: { ...providerEnv, HOME: workspace, USERPROFILE: workspace },
                maxBuffer: 2 * 1024 * 1024,
                timeout: remainingTimeout(deadline, "before refreshing the npm feed"),
                signal,
            });
        } catch (error) {
            signal?.throwIfAborted();
            if (error?.code === "ENOENT") {
                throw new Error(
                    "artifacts-npm-credprovider is not installed or is not on PATH. Install @microsoft/artifacts-npm-credprovider globally.",
                );
            }
            throw new Error(
                `artifacts-npm-credprovider was unable to refresh credentials for the matching feed. ${credentialProviderErrorDetail(error)}`,
            );
        }
    } finally {
        await rm(workspace, { recursive: true, force: true });
    }
    return registries.length;
}

function decodeXmlAttribute(value) {
    return value
        .replace(/&quot;/gi, '"')
        .replace(/&apos;/gi, "'")
        .replace(/&lt;/gi, "<")
        .replace(/&gt;/gi, ">")
        .replace(/&amp;/gi, "&");
}

function xmlAttributes(value) {
    const attributes = new Map();
    const attribute = /([:\w.-]+)\s*=\s*(["'])([\s\S]*?)\2/g;
    for (const match of value.matchAll(attribute)) {
        attributes.set(match[1].toLowerCase(), decodeXmlAttribute(match[3]));
    }
    return attributes;
}

function nugetSources(contents, organization, project) {
    const uncommented = contents.replace(/<!--[\s\S]*?-->/g, "");
    if (uncommented.includes("<!--")) {
        throw new Error("NuGet.config contains an unterminated XML comment.");
    }
    const packageSources = uncommented.match(
        /<packageSources\b[^>]*>([\s\S]*?)<\/packageSources>/i,
    );
    if (!packageSources) {
        throw new Error("NuGet.config does not contain a packageSources section.");
    }

    const sources = new Map();
    const addElement = /<add\b([\s\S]*?)\/?>/gi;
    for (const match of packageSources[1].matchAll(addElement)) {
        const attributes = xmlAttributes(match[1]);
        const name = attributes.get("key");
        const value = attributes.get("value");
        if (name && value && matchesArtifactsScope(value, organization, project)) {
            sources.set(value.toLowerCase(), { name, url: value });
        }
    }
    return [...sources.values()];
}

async function refreshNugetAuth(
    filePath,
    contents,
    organization,
    project,
    { execFileImpl, deadline, signal, environment },
) {
    const sources = nugetSources(contents, organization, project);
    if (sources.length === 0) {
        throw new Error(
            `No Azure Artifacts NuGet source for ${organization}/${project} was found in ${filePath}.`,
        );
    }

    let completedSourceCount = 0;
    for (const source of sources) {
        try {
            signal?.throwIfAborted();
            await execFileImpl(
                "nuget-plugin-microsoft-artifacts-credential-provider",
                ["-U", source.url, "-I", "-R", "-V", "Warning", "-F", "Json"],
                {
                    env: credentialProviderEnvironment(environment),
                    maxBuffer: 2 * 1024 * 1024,
                    timeout: remainingTimeout(
                        deadline,
                        `after refreshing ${completedSourceCount} of ${sources.length} NuGet sources`,
                    ),
                    signal,
                },
            );
            completedSourceCount += 1;
        } catch (error) {
            signal?.throwIfAborted();
            if (error?.code === "ENOENT") {
                throw new Error(
                    "Microsoft.Artifacts.CredentialProvider.NuGet.Tool is not installed or is not on PATH.",
                );
            }
            throw new Error(
                `The Azure Artifacts NuGet credential provider was unable to refresh source ` +
                    `'${source.name}' after completing ${completedSourceCount} of ${sources.length} sources. ` +
                    credentialProviderErrorDetail(error),
            );
        }
    }
    return sources.length;
}

/**
 * @param {object} args tool arguments (`organization`, `project`, `filePath`).
 * @param {string} workingDirectory the active Copilot CLI working directory,
 *   used to resolve a relative `filePath` - not the extension process's own
 *   (potentially stale) working directory.
 */
export async function refreshArtifactsAuth(
    args,
    workingDirectory,
    {
        execFileImpl = execFileAsync,
        totalTimeoutMs = artifactsRefreshTimeoutMs,
        signal,
        environment = process.env,
    } = {},
) {
    signal?.throwIfAborted();
    const organization = normalizeOrganization(
        requireNonEmptyString(args.organization, "organization"),
    );
    const project = requireNonEmptyString(args.project, "project");
    const requestedPath = requireNonEmptyString(args.filePath, "filePath");

    const absolutePath = resolveAgainstWorkingDirectory(requestedPath, workingDirectory);
    let filePath;
    let contents;
    try {
        filePath = await realpath(absolutePath);
        contents = await readFile(filePath, "utf8");
    } catch (error) {
        throw new Error(
            `Unable to read ${requestedPath}: ${error instanceof Error ? error.message : String(error)}`,
        );
    }

    const fileName = basename(filePath).toLowerCase();
    if (fileName !== ".npmrc" && fileName !== "nuget.config") {
        throw new Error("filePath must point to an existing .npmrc or NuGet.config file.");
    }

    const deadline = Date.now() + totalTimeoutMs;
    const sourceCount =
        fileName === ".npmrc"
            ? await refreshNpmAuth(filePath, contents, organization, project, {
                  execFileImpl,
                  deadline,
                  signal,
                  environment,
                  workingDirectory,
              })
            : await refreshNugetAuth(filePath, contents, organization, project, {
                  execFileImpl,
                  deadline,
                  signal,
                  environment,
              });

    return JSON.stringify(
        {
            filePath,
            fileType: fileName === ".npmrc" ? "npm" : "nuget",
            organization,
            project,
            sourceCount,
            message:
                "Azure Artifacts credentials refreshed through the ecosystem credential provider. The supplied config file was not modified.",
        },
        null,
        2,
    );
}

export const testables = {
    parseArtifactsFeedUrl,
    matchesArtifactsScope,
    npmRegistries,
    foreignArtifactsRegistries,
    nugetSources,
    decodeXmlAttribute,
    xmlAttributes,
    credentialProviderErrorDetail,
};
