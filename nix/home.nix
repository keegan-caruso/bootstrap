{
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
in
{
  home = {
    username = "keegancaruso";
    inherit homeDirectory;
    packages = fontPackages;
    stateVersion = "24.11";

    file = {
      ".zshenv" = {
        source = template "zsh/zshenv.sh";
        force = true;
      };
      ".config/codex-dev-shell/zshrc".text = joinTemplates [
        "zsh/path.sh"
        "zsh/interactive.sh"
        "zsh/prompt.sh"
        "zsh/shell-tools.sh"
        "zsh/syntax-highlighting.sh"
      ];
      ".config/codex-dev-shell/bashrc".source = template "bash/aliases.sh";
      ".config/starship.toml" = {
        source = template "starship.toml";
        force = true;
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
        force = true;
      };
      ".local/bin/typescript-language-server" = {
        source = template "typescript-language-server";
        executable = true;
        force = true;
      };
    }
    // lib.optionalAttrs (!isWsl) {
      ".config/ghostty/config" = {
        source = template "ghostty/config";
        force = true;
      };
    }
    // lib.optionalAttrs isWsl {
      ".local/bin/git-credential-manager-wsl" = {
        source = template "git-credential-manager-wsl";
        executable = true;
        force = true;
      };
      ".local/bin/wsl-browser" = {
        source = template "wsl-browser";
        executable = true;
        force = true;
      };
    };
  };

  fonts.fontconfig = {
    enable = pkgs.stdenv.hostPlatform.isLinux;
    defaultFonts.monospace = [
      "Ubuntu Mono"
      "Symbols Nerd Font Mono"
    ];
  };
}
