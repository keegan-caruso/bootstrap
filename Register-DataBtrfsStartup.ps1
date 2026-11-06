#Requires -Version 7.0
#Requires -RunAsAdministrator
<#
.SYNOPSIS
Registers the data Btrfs mount script to run elevated at Windows sign-in.
.EXAMPLE
.\Register-DataBtrfsStartup.ps1 -Distribution MyDistro -VhdPath Q:\data-btrfs.vhdx
Run once from an elevated PowerShell 7. Rerunning updates the same task.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $VhdPath = (Join-Path $PSScriptRoot 'data-btrfs.vhdx'),
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $Distribution,
    [ValidatePattern('^/')]
    [string] $MountPoint = '/mnt/data',
    [string] $UserId = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskName = 'Mount WSL Data Btrfs'
$mountScript = (Get-Item -LiteralPath (Join-Path $PSScriptRoot 'Mount-DataBtrfs.ps1')).FullName
$VhdPath = (Get-Item -LiteralPath $VhdPath -ErrorAction Stop).FullName
if ([IO.Path]::GetExtension($VhdPath) -ne '.vhdx') {
    throw "Expected a .vhdx file: $VhdPath"
}
$powerShell = Join-Path $PSHOME 'pwsh.exe'
$command = "& '{0}' -VhdPath '{1}' -Distribution '{2}' -MountPoint '{3}'" -f `
    $mountScript.Replace("'", "''"), $VhdPath.Replace("'", "''"), `
    $Distribution.Replace("'", "''"), $MountPoint.Replace("'", "''")
$encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
$action = New-ScheduledTaskAction -Execute $powerShell `
    -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand $encodedCommand" `
    -WorkingDirectory $PSScriptRoot
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $UserId
$trigger.Delay = 'PT30S'
$principal = New-ScheduledTaskPrincipal -UserId $UserId -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

if ($PSCmdlet.ShouldProcess($taskName, "Register an elevated sign-in task for $UserId")) {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings `
        -Description "Mount $VhdPath at $MountPoint in $Distribution, 30 seconds after sign-in." `
        -Force | Out-Null
    Get-ScheduledTask -TaskName $taskName
}
