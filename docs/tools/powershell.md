# PowerShell

PowerShell provides the Linux-native `pwsh` command for scripts and tools that
require PowerShell without invoking Windows executables through WSL interop.

## Common Commands

- `pwsh`: start an interactive PowerShell session
- `pwsh -NoProfile -Command 'Get-Location'`: run one command
- `pwsh -NoProfile -File ./script.ps1`: run a script
- `pwsh -NoProfile -Command 'Invoke-ScriptAnalyzer -Path ./script.ps1'`: lint a script

PowerShell is installed only on Linux. Copilot CLI can discover it through the
Nix profile without requiring access to `/mnt/c`.

PSScriptAnalyzer is bundled with PowerShell in the Nix profile and development
shell, so script analysis works without installing modules from PowerShell Gallery.
