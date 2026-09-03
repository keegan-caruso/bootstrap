# Playwright in `sr-wt` sessions

- Run repository-owned Playwright through `playwright-run`:

  ```bash
  playwright-run pnpm exec playwright test --project=chromium
  ```

- Add `--headed` to use WSLg.
- Install browser binaries using the consuming repository's Playwright package.
  The shared browser cache is `~/.cache/ms-playwright`.
- Do not use nixpkgs `playwright-driver.browsers` unless its `browsers.json`
  revisions match the consuming npm Playwright package. Matching package names
  or nearby semantic versions is insufficient.
- `playwright-run` supplies Chromium's Linux runtime libraries through the
  bootstrap Nix FHS environment. Do not run `playwright install-deps` or install
  duplicate host packages unless the wrapper is proven insufficient.
- Preserve `privateTmp = false` in the FHS environment so WSLg's X11 socket is
  visible for headed tests.
- The Copilot sandbox must expose `/nix/store` read-only and
  `~/.cache/ms-playwright` read-write. These paths are maintained by the
  bootstrap repository's `configure-copilot-sandbox.sh`.
