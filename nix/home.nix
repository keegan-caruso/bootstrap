{
  dotnetRoot,
  fontPackages,
  isWsl,
  lib,
  pkgs,
  ...
}:
let
  template = path: ./templates + "/${path}";
  joinTemplates =
    paths: lib.concatMapStringsSep "\n\n" (path: builtins.readFile (template path)) paths;
  homeDirectory =
    if pkgs.stdenv.hostPlatform.isDarwin then "/Users/keegancaruso" else "/home/keegancaruso";
  dotnetEnvironment = ''
    export DOTNET_ROOT=${lib.escapeShellArg dotnetRoot}
    export DOTNET_CLI_TELEMETRY_OPTOUT=true
  '';
  runtimeEnvironment = dotnetEnvironment + builtins.readFile (template "node-path.sh");
in
{
  submoduleSupport.externalPackageInstall = true;

  home = {
    username = "keegancaruso";
    inherit homeDirectory;
    packages = fontPackages;
    stateVersion = "24.11";

    file = {
      ".zshenv" = {
        text = runtimeEnvironment + builtins.readFile (template "zsh/zshenv.sh");
      };
      ".config/codex-dev-shell/zshrc".text = joinTemplates [
        "zsh/path.sh"
        "zsh/interactive.sh"
        "zsh/prompt.sh"
        "zsh/shell-tools.sh"
        "zsh/syntax-highlighting.sh"
      ];
      ".config/codex-dev-shell/bashrc".text =
        runtimeEnvironment + builtins.readFile (template "bash/aliases.sh");
      ".config/starship.toml" = {
        source = template "starship.toml";
      };
      ".config/git/bootstrap.config".text = ''
        [core]
          pager = delta
        [interactive]
          diffFilter = delta --color-only
        [delta]
          light = true
          navigate = true
          line-numbers = true
          side-by-side = true
        [merge]
          conflictStyle = zdiff3
        [fetch]
          prune = true
        [init]
          defaultBranch = main
      '';
      ".copilot/instructions/playwright.instructions.md" = {
        source = template "copilot/playwright.instructions.md";
      };
      ".copilot/lsp-config.json".text = builtins.toJSON {
        lspServers.csharp = {
          command = "${pkgs.csharp-ls}/bin/csharp-ls";
          args = [ ];
          fileExtensions = {
            ".cs" = "csharp";
            ".csx" = "csharp";
          };
        };
      };
      ".local/bin/typescript-language-server" = {
        source = template "typescript-language-server";
        executable = true;
      };
    }
    // lib.optionalAttrs (!isWsl) {
      ".config/ghostty/config" = {
        source = template "ghostty/config";
      };
    }
    // lib.optionalAttrs isWsl {
      ".local/bin/git-credential-manager-wsl" = {
        source = template "git-credential-manager-wsl";
        executable = true;
      };
      ".local/bin/wsl-browser" = {
        source = template "wsl-browser";
        executable = true;
      };
    };
  };

  manual.manpages.enable = false;

  fonts.fontconfig = {
    enable = pkgs.stdenv.hostPlatform.isLinux;
    defaultFonts.monospace = [
      "Ubuntu Mono"
      "Symbols Nerd Font Mono"
    ];
  };
}
