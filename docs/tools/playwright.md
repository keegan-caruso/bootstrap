# Playwright

`playwright-run` runs a command in a Chromium-focused FHS environment containing
the Linux libraries required by Playwright's downloaded browser builds.

StartRight pins `@playwright/test` independently from nixpkgs. Use the browser
download selected by the repository's Playwright version rather than
`playwright-driver.browsers`, which may contain incompatible browser revisions.

Install the repository dependencies and matching browser:

```bash
cd src/Web
pnpm install --frozen-lockfile
```

Run Playwright commands through the wrapper:

```bash
cd src/Web/Azdo/e2e
playwright-run pnpm exec playwright test --project=chromium
```

The wrapper uses `~/.cache/ms-playwright` unless
`PLAYWRIGHT_BROWSERS_PATH` is already set. The bootstrap Copilot sandbox policy
allows that cache to be written and exposes `/nix/store` read-only. WSLg's X11
socket remains available, so headed Chromium runs are supported:

```bash
playwright-run pnpm exec playwright test --headed --project=chromium
```
