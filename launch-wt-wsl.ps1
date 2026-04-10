[CmdletBinding()]
param(
    [string]$Distro,
    [string]$WorkingDirectory = "~",
    [string]$Shell = "zsh",
    [string]$WtPath,
    [switch]$NewWindow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-WslPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return $Path -match '^(/|~($|/))'
}

function Resolve-WtPath {
    param(
        [string]$OverridePath
    )

    if ($OverridePath) {
        if (-not (Test-Path -LiteralPath $OverridePath)) {
            throw "Windows Terminal executable not found at '$OverridePath'."
        }

        return (Resolve-Path -LiteralPath $OverridePath).Path
    }

    $command = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @(
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe",
        "$env:ProgramFiles\WindowsApps\Microsoft.WindowsTerminal_*\wt.exe"
    )

    foreach ($candidate in $candidates) {
        $resolved = Get-Item -Path $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($resolved) {
            return $resolved.FullName
        }
    }

    throw "Unable to find wt.exe. Install Windows Terminal or pass -WtPath."
}

function Get-WslArgs {
    param(
        [string]$TargetDistro,
        [string]$TargetDirectory,
        [string]$TargetShell
    )

    $args = @()

    if ($TargetDistro) {
        $args += @("--distribution", $TargetDistro)
    }

    if ($TargetDirectory) {
        if (-not (Test-WslPath -Path $TargetDirectory)) {
            throw "WorkingDirectory must be a WSL path such as '~', '/home/keegan', or '/mnt/c/...'."
        }

        $args += @("--cd", $TargetDirectory)
    }

    $args += @("--exec", $TargetShell, "-il")

    return $args
}

$wtExe = Resolve-WtPath -OverridePath $WtPath
$wslArgs = Get-WslArgs -TargetDistro $Distro -TargetDirectory $WorkingDirectory -TargetShell $Shell

$terminalArgs = @()

if ($NewWindow) {
    $terminalArgs += @("-w", "new")
}

$terminalArgs += @("new-tab", "wsl.exe") + $wslArgs

Write-Host "Launching Windows Terminal with WSL..." -ForegroundColor Cyan
Write-Host "Windows Terminal: $wtExe"
Write-Host "Distro: $(if ($Distro) { $Distro } else { 'default' })"
Write-Host "Shell: $Shell"
Write-Host "Working directory: $WorkingDirectory"

& $wtExe @terminalArgs
