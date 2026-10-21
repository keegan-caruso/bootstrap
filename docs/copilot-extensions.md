# Copilot CLI extensions

The bootstrap tracks these user-scoped extensions under
`nix/templates/copilot/extensions/` and installs them through Home Manager:

| Extension | Platforms |
| --- | --- |
| `azure-devops` | All bootstrap platforms |
| `clipboard-tools` | Linux, including WSL |

Each is installed at `~/.copilot/extensions/<extension-name>/`.

Each directory contains an `extension.mjs` entry point, its local modules,
and Node.js tests. Copilot CLI supplies `@github/copilot-sdk/extension`
when loading an extension; no separate npm install is needed.

## Installation and updates

Run `./bootstrap-nix.sh` to install or reconcile the tracked extensions with
the rest of the Home Manager configuration. Start a new Copilot CLI session
after activation to load them.

Home Manager owns each installed extension directory as a symlink to the
tracked version. Bootstrap refuses to replace an existing directory or
user-managed symlink. Back up and move those entries aside before retrying;
if an entry is a symlink, move the link itself, not its source directory.
Other user-installed extensions are left alone.

Edit the tracked modules in this repository, not the generated links under
`~/.copilot/extensions/`, then rerun bootstrap. Keep the extensions
user-scoped: adding the same tools under `.github/extensions/` would also
register them for this repository.

## Azure DevOps

`azure-devops` exposes four tools:

- `azure_devops_get_pull_request_review_state`: a compact PR snapshot with
  reviewers, active discussions, policies, and build metadata.
- `azure_devops_get_pull_request_comments`: discussion threads, replies,
  status, and file/line context.
- `azure_devops_resolve_pull_request_comments`: marks explicitly selected
  active or pending threads as fixed, after validating the whole selection.
- `azure_devops_refresh_artifacts_auth`: refreshes credentials for feeds in
  an existing `.npmrc` or `NuGet.config` without editing that config file.

PR tools accept a full Azure DevOps PR URL or explicit organization,
project, repository, and PR ID fields. Reads can be pinned with `commitId`;
the review-state tool requires the current PR head. Resolution skips
already-fixed threads and refuses deleted, missing, or conflicting thread
outcomes. Mutating HTTP requests are not automatically retried.

Cancellation is forwarded to authentication, requests, retry delays, and
credential providers. Cancelling a resolution stops further thread updates;
updates already applied cannot be rolled back, and partial failures report
which threads were resolved.

Authentication uses `azureauth ado token --output headervalue`, not
`az login` or a PAT stored in the extension. AzureAuth must be installed,
available on Copilot's `PATH`, and able to authenticate to the requested
organization. Bootstrap provisions AzureAuth on Ubuntu, including WSL;
other platforms need it installed separately.

Credential refresh additionally needs `artifacts-npm-credprovider` for npm
or `nuget-plugin-microsoft-artifacts-credential-provider` for NuGet. The
bootstrap provisions the npm provider; install the NuGet tool separately
when needed. Feed URLs are checked against the supplied organization and
project before invoking a provider. Relative config paths resolve against
the active Copilot session's working directory.

For npm, the provider receives a private temporary workspace containing
only the validated registry URLs. Its temporary home prevents discovery of
unrelated project or user Yarn feeds, while the normal npm credential output
and authentication cache locations are retained. Ambient npm configuration
overrides are not passed through. The temporary workspace is removed on
success, failure, or cancellation.

Use a project `.npmrc`, not the provider's user credential output
(`~/.npmrc`, or `NPM_CONFIG_USERCONFIG` when set). The tool refuses inputs
that alias that output, including symlinks and hard links, so the supplied
file stays unchanged. Commented-out npm and NuGet sources are ignored;
npm registry environment references are expanded before scope validation.
Feed validation errors do not echo credential-bearing URLs.

## Clipboard tools

`clipboard-tools` exposes:

- `clipboard_write_text`: copies the supplied text exactly.
- `clipboard_copy_file`: copies a file's exact contents, up to 16 MiB.

The extension uses Linux-native `wl-copy` from `wl-clipboard`, which the
Linux Nix profile includes. It requires a usable Wayland session, such as
WSLg; a headless session without a clipboard cannot service these tools.
It does not fall back to Windows executables or macOS clipboard commands,
so Home Manager installs it only on Linux.

Relative file paths resolve against the active Copilot session's working
directory. Missing files, oversized files, clipboard failures, and timeouts
are returned as tool failures rather than reported as successful copies.

Files are opened once and read with a strict 16 MiB limit, checking at most
one extra byte to detect growth. Cancellation closes the file and terminates
an active copy process. Failed or timed-out subprocesses are terminated and
reaped, escalating to a forced kill after one second if needed. A successful
`wl-copy` parent exit completes the tool without waiting for its background
clipboard-serving daemon to exit.

## Checks

Run the dependency-free unit tests from the repository root:

```bash
node --test nix/templates/copilot/extensions/*/*.test.mjs
```

These tests use mocks for Azure DevOps and credential providers and do not
need live credentials or write to the real clipboard. `./test-nix.sh` also
runs them and checks that the built Home Manager files match the tracked
extension directories.
