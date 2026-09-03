{
  description = "Personal Nix development environment.";

  inputs.home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    {
      home-manager,
      nixpkgs,
      ...
    }:
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
          playwrightFhs = pkgs.buildFHSEnv {
            name = "playwright-fhs";
            targetPkgs =
              fhsPkgs: with fhsPkgs; [
                alsa-lib
                at-spi2-atk
                atk
                cairo
                cups
                dbus
                expat
                fontconfig
                freetype
                glib
                gtk3
                libdrm
                libgbm
                libx11
                libxcb
                libxcomposite
                libxdamage
                libxext
                libxfixes
                libxkbcommon
                libxrandr
                mesa
                nspr
                nss
                pango
                systemd
              ];
            runScript = "bash";
            privateTmp = false;
          };
          playwrightRun = pkgs.writeShellApplication {
            name = "playwright-run";
            text = ''
              if (( $# == 0 )); then
                echo "Usage: playwright-run <command> [args...]" >&2
                echo "Example: playwright-run pnpm exec playwright test" >&2
                exit 2
              fi

              export PLAYWRIGHT_BROWSERS_PATH="''${PLAYWRIGHT_BROWSERS_PATH:-$HOME/.cache/ms-playwright}"
              exec ${playwrightFhs}/bin/playwright-fhs \
                -c 'exec "$@"' playwright-run "$@"
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
              azure-cli
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
              home-manager.packages.${system}.default
            ]
            ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
              bubblewrap
              fuse-overlayfs
              playwrightRun
              powershell
              util-linux
              wl-clipboard
            ];
          wslTools = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
            wslview
          ];
          fonts = with pkgs; [
            nerd-fonts.symbols-only
            symbola
            ubuntu-classic
          ];
          desktopTools = with pkgs; [
            ghostty
          ];
        in
        {
          inherit
            cliTools
            desktopTools
            fonts
            pkgs
            playwrightRun
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
      mkHomeConfiguration =
        {
          system,
          isWsl ? false,
        }:
        let
          p = mkPackages system;
        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = p.pkgs;
          extraSpecialArgs = {
            inherit isWsl;
            fontPackages = p.fonts;
          };
          modules = [ ./home.nix ];
        };
    in
    {
      homeConfigurations = {
        "keegancaruso@x86_64-linux-wsl" = mkHomeConfiguration {
          system = "x86_64-linux";
          isWsl = true;
        };
        "keegancaruso@x86_64-linux" = mkHomeConfiguration {
          system = "x86_64-linux";
        };
        "keegancaruso@aarch64-linux" = mkHomeConfiguration {
          system = "aarch64-linux";
        };
        "keegancaruso@aarch64-darwin" = mkHomeConfiguration {
          system = "aarch64-darwin";
        };
      };

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
            packages = p.cliTools ++ p.fonts;
          };
        }
      );
    };
}
