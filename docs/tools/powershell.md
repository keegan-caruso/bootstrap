# PowerShell

PowerShell provides the Linux-native `pwsh` command for scripts and tools that
require PowerShell without invoking Windows executables through WSL interop.

## Common Commands

- `pwsh`: start an interactive PowerShell session
- `pwsh -NoProfile -Command 'Get-Location'`: run one command
- `pwsh -NoProfile -File ./script.ps1`: run a script

PowerShell is installed only on Linux. Copilot CLI can discover it through the
Nix profile without requiring access to `/mnt/c`.
