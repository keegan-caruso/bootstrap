{
  description = "Personal WSL development environment (alternative to the Homebrew bootstrap).";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Minimal in-tree replacement for `wslview` (from the archived `wslu`
      # project, which was removed from nixpkgs). Behaves well enough for
      # `$BROWSER=wslview` and `xdg-open URL` use:
      #   * URLs (scheme://...) are handed to explorer.exe directly,
      #     which routes them through the default Windows browser.
      #   * Existing paths are translated with `wslpath -w` (shipped with
      #     WSL itself) and opened via explorer.exe with the Windows
      #     file-type association.
      #   * Anything else is passed through verbatim.
      wslview = pkgs.writeShellApplication {
        name = "wslview";
        runtimeInputs = [ ];
        text = ''
          explorer=/mnt/c/Windows/explorer.exe
          if [ ! -x "$explorer" ]; then
            echo "wslview: $explorer not found (is WSL interop enabled?)" >&2
            exit 1
          fi

          target=''${1:-.}
          case "$target" in
            *://*)
              "$explorer" "$target" || true
              ;;
            *)
              if [ -e "$target" ]; then
                win=$(wslpath -w -- "$target")
                "$explorer" "$win" || true
              else
                "$explorer" "$target" || true
              fi
              ;;
          esac
        '';
      };

      # Mirrors the CLI subset of BREW_PACKAGES in bootstrap-dev-shell.sh.
      # `wslview` is provided locally because the upstream `wslu` package
      # was removed from nixpkgs after its project was archived.
      # The VS Code launcher is intentionally out of scope here; Nerd Fonts
      # are bundled separately below.
      cliTools = with pkgs; [
        # search & navigation
        fzf
        fd
        bat
        eza
        zoxide
        ripgrep
        sd

        # core build / docs
        cmake
        cmark
        coreutils
        pandoc

        # VCS
        git
        gh
        jujutsu
        delta

        # data / structured text
        jq
        yq-go
        yamllint
        taplo

        # JS / TS
        fnm
        prettier
        typescript
        typescript-language-server
        eslint_d
        markdownlint-cli2

        # languages / linters
        rust-analyzer
        shellcheck
        shfmt
        ruff
        uv

        # observability / metrics
        duf
        dust
        bottom
        procs
        hyperfine
        tokei
        ncdu

        # http / dns
        xh
        doggo

        # clipboard (X11; works on WSL via WSLg)
        xclip

        # terminal UX
        zellij
        starship
        zsh-autosuggestions
        zsh-syntax-highlighting

        # WSL <-> Windows integration
        wslview
      ];

      # Mirrors the Nerd Font casks installed by bootstrap-dev-shell.sh
      # (font-jetbrains-mono-nerd-font, font-symbols-only-nerd-font).
      # These drop TTFs under `share/fonts/` in the profile; fontconfig
      # discovery on non-NixOS is wired up by bootstrap-wsl-nix.sh.
      fonts = with pkgs; [
        nerd-fonts.jetbrains-mono
        nerd-fonts.symbols-only
      ];
    in
    {
      packages.${system}.default = pkgs.buildEnv {
        name = "wsl-dev-tools";
        paths = cliTools ++ fonts;
      };

      # `nix develop` users get the same toolset plus the BROWSER hint.
      devShells.${system}.default = pkgs.mkShell {
        packages = cliTools ++ fonts;
        shellHook = ''
          export BROWSER=wslview
        '';
      };
    };
}
