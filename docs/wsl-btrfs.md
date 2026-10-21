# Btrfs data VHDX for WSL

Keep Linux repositories and other data on a separate Btrfs filesystem backed
by a Windows VHDX, rather than on a Windows drive through DrvFS. This is a
data disk, not a replacement for the distribution's `ext4.vhdx`.

The examples use `Q:\data-btrfs.vhdx`, `Ubuntu-26.04`, and `/mnt/data`.
Substitute your drive, distribution, and mount point consistently.

## Prerequisites

- WSL 2 with `wsl.exe --mount --vhd` support. Check `wsl.exe --version` and
  `wsl.exe --list --verbose` from Windows.
- PowerShell 7 on Windows, opened with **Run as administrator** as the Windows
  user who owns the WSL distribution. A different administrator account will
  not see the same per-user distributions.
- A WSL kernel with Btrfs support, and systemd enabled in the distribution.
- A Windows volume with space for the growing VHDX. The volume must be
  available before the mount script runs, including at sign-in.

Inside Ubuntu, install the filesystem and mount utilities:

```bash
sudo apt-get update
sudo apt-get install btrfs-progs util-linux kmod
sudo modprobe btrfs
grep -w btrfs /proc/filesystems
ps -p 1 -o comm=
```

The last command must report `systemd`. If necessary, merge the following
into `/etc/wsl.conf`, preserving other settings:

```ini
[boot]
systemd=true
```

Then save work in all distributions, run `wsl.exe --shutdown` from Windows,
and reopen Ubuntu. If loading Btrfs fails, stop here: `btrfs-progs` alone
does not add kernel support. Use a WSL kernel and matching modules with
Btrfs support before continuing.

## Put the scripts beside the VHDX

From a Windows-accessible checkout of this repository, copy both scripts to
the Windows directory that will hold the disk:

```powershell
Copy-Item .\Mount-DataBtrfs.ps1, .\Register-DataBtrfsStartup.ps1 Q:\
```

`Mount-DataBtrfs.ps1` defaults to `data-btrfs.vhdx` beside itself. It attaches
the disk only when needed, then starts the distribution's systemd mount unit
from `/etc/fstab`. It does not create or format disks, edit fstab, or change
ownership.

Keep these files in a trusted location: the sign-in task runs the mount
script elevated. Copies are not automatically updated when this repository
changes.

## Create and format a new data disk

**Skip creation and formatting if the VHDX already contains data.** Attach
the existing VHDX, identify its Btrfs device, and continue with
[Configure the fstab mount](#configure-the-fstab-mount).

In elevated Windows PowerShell, start `diskpart`, then enter the following
DiskPart commands to create a dynamically expanding disk with a 256 GiB
maximum. Choose a new file path; do not select an existing distribution disk.

```text
create vdisk file="Q:\data-btrfs.vhdx" maximum=262144 type=expandable
exit
```

Do not initialize or format this disk in Windows. Before attaching it, run
this inside Ubuntu and note the existing devices:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS
```

Attach it from elevated Windows PowerShell without asking WSL to mount it
as ext4:

```powershell
wsl.exe --mount --vhd "Q:\data-btrfs.vhdx" --bare
```

Inside Ubuntu, run `lsblk` again. Identify the newly added, empty 256 GiB
disk by comparing the two listings. Device names can change after every
attachment; never assume the disk is `/dev/sdb`.

**The next command creates a filesystem and can destroy data on the selected
device.** Replace `/dev/sdX` only after verifying it is the new empty data
disk, not the disk containing `/`, swap, or another filesystem. This example
formats the whole disk, without a partition table:

```bash
sudo mkfs.btrfs -L wsl-data /dev/sdX
```

Do not add `-f` to override an existing filesystem signature. Investigate any
unexpected signature instead.

## Configure the fstab mount

Inside Ubuntu, get the UUID of the Btrfs filesystem on the identified device
(use the partition device instead if your existing disk is partitioned):

```bash
sudo blkid /dev/sdX
sudo mkdir -p /mnt/data
sudoedit /etc/fstab
```

Add one entry, replacing `<UUID>` with the actual filesystem UUID:

```fstab
UUID=<UUID> /mnt/data btrfs compress=zstd,nofail,x-systemd.device-timeout=5s 0 0
```

The mount script requires a `UUID=` source and a `btrfs` filesystem type.
Do not use a transient `/dev/sdX` name or the VHDX's Windows path. `nofail`
allows Ubuntu to boot without the data disk; the device timeout limits the
wait when it is absent. Compression applies to newly written data.

Reload the generated systemd mount units inside Ubuntu:

```bash
sudo systemctl daemon-reload
```

From elevated Windows PowerShell, mount and verify:

```powershell
Q:\Mount-DataBtrfs.ps1 -WhatIf
Q:\Mount-DataBtrfs.ps1
```

`-WhatIf` still requires an existing VHDX file, but does not attach it or run
the Linux mount checks. The real run checks the fstab entry and mounted UUID,
waits up to 30 seconds for an attached filesystem to appear, and prints the
resulting mount. Rerunning is safe when that filesystem is already mounted.

The script enters PID 1's mount namespace with `nsenter` and asks systemd
to start the mount, so the filesystem is not mounted only in a transient
`wsl.exe` session.

In Ubuntu, confirm the filesystem is mounted before creating a writable
directory for your user:

```bash
findmnt --mountpoint /mnt/data -o TARGET,SOURCE,FSTYPE,UUID,OPTIONS
mountpoint -q /mnt/data && sudo mkdir -p /mnt/data/repos
mountpoint -q /mnt/data && sudo chown "$(id -u):$(id -g)" /mnt/data/repos
```

The guards avoid creating a fallback directory on the distribution disk
when the data filesystem is missing.

For non-default settings, pass all relevant parameters:

```powershell
Q:\Mount-DataBtrfs.ps1 -VhdPath "R:\storage\work.vhdx" `
    -Distribution Ubuntu -MountPoint /mnt/work
```

Create the corresponding mount point and fstab entry in that distribution.

## Optional repository bind mount

To expose `/mnt/data/repos` as `/home/YOUR_USER/repos`, first ensure the
destination is an empty directory. A bind mount hides existing contents; it
does not migrate them. Back up and move existing repositories separately,
with tools and shells using them stopped.

Create the empty destination and add this fstab entry, replacing `YOUR_USER`:

<!-- markdownlint-disable MD013 -- fstab entries must stay on one line. -->
```fstab
/mnt/data/repos /home/YOUR_USER/repos none bind,nofail,x-systemd.requires-mounts-for=/mnt/data 0 0
```
<!-- markdownlint-enable MD013 -->

Run `sudo systemctl daemon-reload`, then rerun the Windows mount script.
The explicit dependency orders the bind mount after the data mount and
makes it appear in the data unit's `RequiredBy` list. The script starts
those dependent `.mount` units even if the data filesystem was already
mounted, recovering mounts that failed before the VHDX was attached.

## Mount automatically at Windows sign-in

After a successful manual mount, run once from **elevated PowerShell 7 on
Windows**, as the same Windows user:

```powershell
Q:\Register-DataBtrfsStartup.ps1 -WhatIf
Q:\Register-DataBtrfsStartup.ps1
```

This creates or updates the `Mount WSL Data Btrfs` scheduled task. It runs
the adjacent mount script using that PowerShell 7 installation,
with highest privileges in the user's interactive session, 30 seconds
after sign-in. It allows battery operation and retries failures up to
three times at one-minute intervals.

The task passes no parameters to the mount script. For automatic mounting
with non-default settings, edit the parameter defaults in the deployed
`Mount-DataBtrfs.ps1` before registering it. Keep both scripts and the
PowerShell installation at their registered paths; rerun registration if
those paths change. Avoid overwriting customized defaults when refreshing
the deployed copy.

Inspect or manually run the task from elevated Windows PowerShell:

```powershell
Get-ScheduledTaskInfo -TaskName 'Mount WSL Data Btrfs'
Start-ScheduledTask -TaskName 'Mount WSL Data Btrfs'
```

The trigger is **Windows sign-in, not WSL startup**. After `wsl.exe --shutdown`,
a distribution termination, or a manual detach, rerun the mount script
when the disk needs mounting again. Do not expect the task to rerun just
because Ubuntu was reopened.

To remove only the automation, without deleting the VHDX or fstab entries:

```powershell
Unregister-ScheduledTask -TaskName 'Mount WSL Data Btrfs' -Confirm
```

## Troubleshooting and disk care

Inside Ubuntu, inspect the mount unit and its logs in systemd's mount
namespace:

```bash
sudo nsenter --mount=/proc/1/ns/mnt -- findmnt --mountpoint /mnt/data
sudo systemctl status mnt-data.mount
sudo journalctl -b -u mnt-data.mount
```

For a different mount point, get the unit name with
`systemd-escape --path --suffix=mount /mnt/work`.

- **Missing or wrong fstab entry:** check the mount path, `UUID=`, and Btrfs
  type, then run `sudo systemctl daemon-reload`.
- **UUID not found after attachment:** compare `sudo blkid` with fstab and
  confirm the script's Windows path identifies the intended VHDX. Do not
  reformat the disk to fix a UUID mismatch.
- **A different filesystem is already mounted:** investigate with `findmnt`;
  the script deliberately refuses to replace it.
- **Bind mount failed:** confirm its source directory exists on the mounted
  data disk and its fstab dependency is present, reload units, and rerun the
  mount script.
- **Sign-in task failed:** check Task Scheduler history and
  `Get-ScheduledTaskInfo`, then run the mount script interactively to see
  the error. Check that `Q:` is available and that the task uses the Windows
  account owning the distribution.

Before detaching, stop processes using the disk, unmount dependent bind
mounts first, and stop the data mount inside Ubuntu:

```bash
sudo systemctl stop mnt-data.mount
```

Then detach from elevated Windows PowerShell:

```powershell
wsl.exe --unmount "Q:\data-btrfs.vhdx"
```

Do not force an unmount if the filesystem is busy. For a whole-VHDX backup,
copy the file only after it is unmounted and detached. Btrfs snapshots in
the same VHDX are not independent backups. A dynamically expanding VHDX
still needs free space on its Windows host volume; deleting Linux files
does not necessarily shrink the Windows file automatically.

See Microsoft's [WSL disk mounting reference](https://learn.microsoft.com/en-us/windows/wsl/wsl2-mount-disk)
for WSL requirements and attachment behavior.
