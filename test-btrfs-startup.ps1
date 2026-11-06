$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    $scriptText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Register-DataBtrfsStartup.ps1') -Raw
    $scriptText = $scriptText -replace '(?m)^#Requires -RunAsAdministrator\r?\n', ''
    $registrationScript = Join-Path $testRoot 'Register-DataBtrfsStartup.ps1'
    Set-Content -LiteralPath $registrationScript -Value $scriptText
    Set-Content -LiteralPath (Join-Path $testRoot 'Mount-DataBtrfs.ps1') -Value @'
param($VhdPath, $Distribution, $MountPoint)
[pscustomobject]@{ VhdPath = $VhdPath; Distribution = $Distribution; MountPoint = $MountPoint }
'@
    $vhd = Join-Path $testRoot "my 'data disk'.vhdx"
    New-Item -ItemType File -Path $vhd | Out-Null
    $global:BtrfsTestRegisteredAction = $null
    function New-ScheduledTaskAction {
        param($Execute, $Argument, $WorkingDirectory)
        [pscustomobject]@{ Execute = $Execute; Argument = $Argument; WorkingDirectory = $WorkingDirectory }
    }
    function New-ScheduledTaskTrigger {
        [pscustomobject]@{ Delay = '' }
    }
    function New-ScheduledTaskPrincipal { @{} }
    function New-ScheduledTaskSettingsSet { @{} }
    function Register-ScheduledTask {
        param($TaskName, $Action, $Trigger, $Principal, $Settings, $Description, [switch]$Force)
        $global:BtrfsTestRegisteredAction = $Action
    }
    function Get-ScheduledTask { }

    $distribution = "Test 'distribution' with spaces"
    $mountPoint = "/mnt/my 'data'"
    & $registrationScript -VhdPath $vhd -Distribution $distribution -MountPoint $mountPoint -UserId 'test-user'
    if ($null -eq $global:BtrfsTestRegisteredAction) { throw 'No scheduled action was registered.' }
    $encoded = ($global:BtrfsTestRegisteredAction.Argument -split ' -EncodedCommand ', 2)[1]
    $command = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))
    $invocation = & ([scriptblock]::Create($command))
    if ($invocation.VhdPath -ne $vhd -or $invocation.Distribution -ne $distribution -or
        $invocation.MountPoint -ne $mountPoint) {
        throw 'Scheduled action did not preserve the exact mount arguments.'
    }
    $global:BtrfsTestRegisteredAction = $null
    & $registrationScript -VhdPath $vhd -Distribution $distribution -MountPoint $mountPoint `
        -UserId 'test-user' -WhatIf
    if ($null -ne $global:BtrfsTestRegisteredAction) { throw 'WhatIf registered a scheduled task.' }
    'Btrfs scheduled argument checks passed (mocked; no task registered)'
} finally {
    Remove-Variable -Name BtrfsTestRegisteredAction -Scope Global -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
