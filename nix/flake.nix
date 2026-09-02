{
  description = "Personal Nix development environment.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      mkPackages =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          lib = pkgs.lib;
          gcmWsl = pkgs.writeShellApplication {
            name = "git-credential-manager-wsl";
            text = ''
              if ! command -v git.exe >/dev/null 2>&1; then
                echo "git-credential-manager-wsl: Git for Windows is not available on PATH" >&2
                exit 1
              fi

              exec git.exe credential-manager "$@"
            '';
          };
          agency = pkgs.writeShellApplication {
            name = "agency";
            text = ''
              agency_bin="$HOME/.config/agency/CurrentVersion/agency"
              if [[ ! -x "$agency_bin" ]]; then
                echo "agency: executable not found: $agency_bin" >&2
                exit 1
              fi

              exec "$agency_bin" "$@"
            '';
          };
          wslview = pkgs.writeShellApplication {
            name = "wslview";
            text = ''
              explorer=/mnt/c/Windows/explorer.exe
              if [[ ! -x "$explorer" ]]; then
                echo "wslview: $explorer not found (is WSL interop enabled?)" >&2
                exit 1
              fi

              target=''${1:-.}
              case "$target" in
                *://*)
                  "$explorer" "$target" || true
                  ;;
                *)
                  if [[ -e "$target" ]]; then
                    "$explorer" "$(wslpath -w -- "$target")" || true
                  else
                    "$explorer" "$target" || true
                  fi
                  ;;
              esac
            '';
          };
          dotnetSdk = pkgs.dotnetCorePackages.combinePackages [
            pkgs.dotnetCorePackages.sdk_8_0
            pkgs.dotnetCorePackages.sdk_10_0
          ];
          cliTools =
            with pkgs;
            [
              bat
              bottom
              cmark
              cmake
              coreutils
              csharpier
              delta
              doggo
              duf
              dust
              eza
              fd
              fnm
              fontconfig
              fzf
              gh
              git
              hyperfine
              jq
              jujutsu
              ncdu
              pandoc
              procs
              ripgrep
              ruff
              rust-analyzer
              sd
              shellcheck
              shfmt
              starship
              taplo
              tokei
              ty
              uv
              xh
              yamllint
              yq-go
              zellij
              zoxide
              zsh
              zsh-autosuggestions
              zsh-syntax-highlighting
              dotnetSdk
            ]
            ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
              fuse-overlayfs
              util-linux
              xclip
            ];
          wslTools = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
            gcmWsl
            wslview
          ];
          fonts = with pkgs; [
            nerd-fonts.jetbrains-mono
            nerd-fonts.symbols-only
            symbola
          ];
          desktopTools = with pkgs; [
            ghostty
          ];
        in
        {
          inherit
            agency
            cliTools
            desktopTools
            fonts
            pkgs
            wslTools
            ;
          default = pkgs.buildEnv {
            name = "dev-tools";
            paths = cliTools ++ fonts ++ wslTools;
          };
          desktop = pkgs.buildEnv {
            name = "desktop-tools";
            paths = desktopTools;
          };
          workstation = pkgs.buildEnv {
            name = "dev-workstation";
            paths = cliTools ++ fonts ++ desktopTools;
          };
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          p = mkPackages system;
        in
        {
          inherit (p) default desktop workstation;
        }
      );

      formatter = forAllSystems (system: (mkPackages system).pkgs.nixfmt);

      devShells = forAllSystems (
        system:
        let
          p = mkPackages system;
        in
        {
          default = p.pkgs.mkShell {
            packages = p.cliTools ++ p.fonts ++ [ p.agency ];
          };
        }
      );
    };
}
