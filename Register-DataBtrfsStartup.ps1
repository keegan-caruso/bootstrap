#Requires -Version 7.0
#Requires -RunAsAdministrator
<#
.SYNOPSIS
Registers the data Btrfs mount script to run elevated at Windows sign-in.
.EXAMPLE
.\Register-DataBtrfsStartup.ps1
Run once from an elevated PowerShell 7. Rerunning updates the same task.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $UserId = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskName = 'Mount WSL Data Btrfs'
$mountScript = (Get-Item -LiteralPath (Join-Path $PSScriptRoot 'Mount-DataBtrfs.ps1')).FullName
$powerShell = Join-Path $PSHOME 'pwsh.exe'
$action = New-ScheduledTaskAction -Execute $powerShell `
    -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -File `"$mountScript`"" `
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
        -Description 'Mount the data Btrfs VHD at /mnt/data in Ubuntu WSL, 30 seconds after sign-in.' `
        -Force | Out-Null
    Get-ScheduledTask -TaskName $taskName
}
