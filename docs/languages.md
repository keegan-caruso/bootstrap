# Language Support

## JavaScript / JSX / TypeScript / TSX

Config file:

- `doom/config/javascript.el`

Behavior:

- `.jsx` opens in `rjsx-mode`
- `.tsx` opens in `tsx-ts-mode`
- `.ts` opens in `typescript-ts-mode`
- `eglot` prefers `node_modules/.bin/typescript-language-server`
- falls back to a machine-level `typescript-language-server`
- formatting uses `prettier`
- linting uses ESLint through `flymake-collection`

## .NET / C Sharp

Config file:

- `doom/config/dotnet.el`

Behavior:

- `.sln` and `.slnx` use `conf-mode`
- `.csproj`, `.props`, `.targets`, `.runsettings`, `.nuspec` use `nxml-mode`
- `.slnx` is preferred over `.sln`, then `.csproj` for project target discovery
- `eglot` prefers:
  - `dnx roslyn-language-server --yes --prerelease -- --stdio --autoLoadProjects`
  - `csharp-ls`
  - `omnisharp -lsp`
  - `OmniSharp -lsp`
- formatting support improves when `csharpier` is installed

Commands under `SPC o d`:

- `a`: `dotnet add package`
- `b`: `dotnet build`
- `c`: `dotnet clean`
- `f`: `dotnet format`
- `r`: `dotnet run`
- `s`: `dotnet restore`
- `t`: `dotnet test`
- `w`: `dotnet watch run`

## Python

Config file:

- `doom/config/python.el`

This setup intentionally limits Python support to:

- `uv`
- `ruff`
- `ty`

Behavior:

- `eglot` uses `ty server`, or `uvx ty server` as fallback
- formatting uses `ruff format`

Commands under `SPC o p`:

- `s`: `uv sync`
- `r`: `uv run python`
- `c`: `ruff check`
- `f`: `ruff format .`
- `t`: `ty check`

## Rust

Config file:

- `doom/config/rust.el`

Behavior:

- `eglot` uses `ra-multiplex` or `rust-analyzer`
- formatting uses `rustfmt`

Commands under `SPC o r`:

- `b`: `cargo build`
- `c`: `cargo check`
- `l`: `cargo clippy`
- `t`: `cargo test`
- `n`: `cargo nextest run`
- `r`: `cargo run`
- `f`: `cargo fmt`

## TOML

Config file:

- `doom/config/toml.el`

Behavior:

- `*.toml` uses the best available TOML mode:
  - `toml-ts-mode`
  - `conf-toml-mode`
  - `toml-mode`
  - fallback `conf-mode`
- `eglot` uses `taplo lsp stdio`
- formatting uses `taplo fmt`

## Shared Shell / Markup / Data Formats

These are configured in `doom/config/core.el`.

Support includes:

- shell via `shfmt` and `shellcheck`
- Markdown via `prettier` and `markdownlint-cli2`
- YAML via `prettier` and `yamllint`
- JSON via `prettier`
