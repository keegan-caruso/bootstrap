<#
.SYNOPSIS
Attaches the data Btrfs VHD to WSL and starts its fstab mount and dependent mounts.
.EXAMPLE
.\Mount-DataBtrfs.ps1 -Distribution MyDistro
Run from an elevated PowerShell. Defaults to data-btrfs.vhdx beside this script
and /mnt/data. The distribution must be selected explicitly.
No disks are formatted and fstab is not changed.
Mounts are managed by the distribution's systemd in its mount namespace. Dependent
repository bind mounts are retried even when the data filesystem is already mounted.
.EXAMPLE
.\Mount-DataBtrfs.ps1 -Distribution MyDistro -WhatIf
Shows the intended operation without attaching or mounting anything.
.NOTES
To mount automatically at Windows sign-in, run Register-DataBtrfsStartup.ps1
once from an elevated PowerShell 7.
The scheduled task runs at Windows sign-in, not on subsequent WSL restarts.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $VhdPath = (Join-Path $PSScriptRoot 'data-btrfs.vhdx'),
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $Distribution,
    [ValidatePattern('^/')]
    [string] $MountPoint = '/mnt/data'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$VhdPath = (Get-Item -LiteralPath $VhdPath -ErrorAction Stop).FullName
if ([IO.Path]::GetExtension($VhdPath) -ne '.vhdx') {
    throw "Expected a .vhdx file: $VhdPath"
}

if (-not $PSCmdlet.ShouldProcess(
    "$VhdPath -> ${Distribution}:$MountPoint",
    'Attach the VHD to WSL and mount the Btrfs filesystem using /etc/fstab'
)) {
    return
}

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from PowerShell opened with "Run as administrator".'
}

$linuxScript = @'
set -eu
mode=$1
target=$2
fail() { printf '%s\n' "$*" >&2; exit 1; }

source=$(findmnt --fstab --mountpoint "$target" --noheadings --output SOURCE) ||
    fail "No /etc/fstab entry for $target."
fstype=$(findmnt --fstab --mountpoint "$target" --noheadings --output FSTYPE)
[ "$fstype" = btrfs ] || fail "The fstab entry for $target is not Btrfs."
case "$source" in
    UUID=?*) uuid=${source#UUID=} ;;
    *) fail "The fstab entry for $target must identify the filesystem by UUID." ;;
esac
fstab_options=$(findmnt --fstab --mountpoint "$target" --noheadings --raw --output OPTIONS)

mount_option() {
    remaining=$1
    key=$2
    value=''
    while [ -n "$remaining" ]; do
        option=${remaining%%,*}
        case "$remaining" in
            *,*) remaining=${remaining#*,} ;;
            *) remaining='' ;;
        esac
        case "$option" in
            "$key"=*) value=${option#*=} ;;
        esac
    done
    printf '%s\n' "$value"
}

verify_mount() {
    actual=$(findmnt --mountpoint "$target" --noheadings --output UUID) || return 1
    [ "$actual" = "$uuid" ] || fail "A different filesystem is already mounted at $target."
    actual_type=$(findmnt --mountpoint "$target" --noheadings --output FSTYPE) ||
        fail "Cannot read the mounted filesystem type for $target."
    [ "$actual_type" = btrfs ] || fail "The mounted filesystem at $target is not Btrfs."
    actual_options=$(findmnt --mountpoint "$target" --noheadings --raw --output OPTIONS) ||
        fail "Cannot read the mounted filesystem options for $target."
    actual_id=$(mount_option "$actual_options" subvolid)
    expected_id=$(mount_option "$fstab_options" subvolid)
    expected_path=$(mount_option "$fstab_options" subvol)

    if [ -n "$expected_path" ]; then
        expected_path="/${expected_path#/}"
        while [ "$expected_path" != / ] && [ "${expected_path%/}" != "$expected_path" ]; do
            expected_path=${expected_path%/}
        done
        actual_path=$(findmnt --mountpoint "$target" --noheadings --raw --output FSROOT) ||
            fail "Cannot read the mounted Btrfs subvolume path for $target."
        [ "$actual_path" = "$expected_path" ] ||
            fail "The Btrfs subvolume mounted at $target does not match fstab subvol=$expected_path."
    fi
    if [ "$expected_id" = 0 ] || { [ -z "$expected_id" ] && [ -z "$expected_path" ]; }; then
        default_subvolume=$(btrfs subvolume get-default "$target") ||
            fail "Cannot read the default Btrfs subvolume for $target."
        expected_id=$(printf '%s\n' "$default_subvolume" | awk '$1 == "ID" { print $2; exit }')
        [ -n "$expected_id" ] || fail "Cannot identify the default Btrfs subvolume for $target."
    fi
    if [ -n "$expected_id" ]; then
        [ "$actual_id" = "$expected_id" ] ||
            fail "The Btrfs subvolume mounted at $target does not match fstab subvolid=$expected_id."
    fi
    return 0
}

if verify_mount; then
    if [ "$mode" = check ]; then
        printf '%s\n' mounted
        exit 0
    fi
fi

device=''
attempt=0
while :; do
    if device=$(blkid -U "$uuid"); then
        actual_type=$(blkid -s TYPE -o value "$device")
        [ "$actual_type" = btrfs ] || fail "Filesystem $uuid is not Btrfs."
        break
    else
        status=$?
        [ "$status" -eq 2 ] || fail "blkid failed with exit code $status."
    fi
    [ "$mode" != check ] || break
    [ "$attempt" -lt 30 ] || fail "Filesystem $uuid was not found after attaching the VHD."
    attempt=$((attempt + 1))
    sleep 1
done

if [ "$mode" = check ]; then
    if [ -n "$device" ]; then
        printf '%s\n' attached
    else
        printf '%s\n' detached
    fi
    exit 0
fi

[ -n "$device" ] || fail "Filesystem $uuid was not found after attaching the VHD."
modprobe btrfs
unit=$(systemd-escape --path --suffix=mount -- "$target")
systemctl start "$unit"
verify_mount ||
    fail "Mount verification failed for $target."

# These fstab mounts may have failed before the VHD was attached.
dependents=$(systemctl show --property=RequiredBy --value "$unit")
for dependent in $dependents; do
    case "$dependent" in
        *.mount) systemctl start "$dependent" ;;
    esac
done
findmnt --mountpoint "$target" --output TARGET,SOURCE,FSTYPE,OPTIONS
'@
$linuxScript = $linuxScript.Replace("`r", '')

function Invoke-LinuxMount {
    param([string] $Mode)

    $command = $linuxScript
    if ($PSVersionTable.PSVersion -ge [version]'7.3') {
        $PSNativeCommandArgumentPassing = 'Standard'
    } else {
        # Legacy native argument passing strips the Linux command's double quotes.
        $command = $command.Replace('"', '\"')
    }
    $output = & wsl.exe --distribution $Distribution --user root --exec nsenter --mount=/proc/1/ns/mnt -- sh -c $command -- $Mode $MountPoint
    if ($LASTEXITCODE -ne 0) {
        throw "WSL $Mode failed with exit code $LASTEXITCODE. See the error above."
    }
    return ($output -join "`n").Trim()
}

$state = Invoke-LinuxMount -Mode check
switch ($state) {
    'mounted' { }
    'detached' {
        & wsl.exe --mount --vhd $VhdPath --bare
        if ($LASTEXITCODE -ne 0) {
            throw "Could not attach '$VhdPath' to WSL (exit code $LASTEXITCODE)."
        }
    }
    'attached' { }
    default { throw "Unexpected WSL mount state: $state" }
}

Invoke-LinuxMount -Mode mount
