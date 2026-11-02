# rootfs

Remove rootfs verification, so that the root filesystem can be mounted
read/write (see [rw](rw.md)), and reboot.

| | |
| --- | --- |
| Command | `rootfs [--no-reboot] [-- make_dev_ssd.sh arguments]`, or `chromebrew-scripts rootfs ...` |
| Runs as | you; `make_dev_ssd.sh` and `reboot` go through `sudo` |
| Needs | ChromeOS in developer mode (refuses off ChromeOS), a terminal or `--yes` |
| Options | `--no-reboot`, anything after `--` is passed to `make_dev_ssd.sh`, and the [common options](../README.md#usage) |
| Reversible | Not by this toolkit. The device no longer passes verified boot until the root partition is rewritten (an OS update or a recovery image) |

## What it does

After the confirmation, two steps:

1. **remove rootfs verification**:
   `sudo /usr/share/vboot/bin/make_dev_ssd.sh --remove_rootfs_verification`,
   followed by whatever you put after `--`. This is the ChromeOS developer
   tool that rewrites the kernel's command line on disk so that the next
   boot does not use dm-verity for the root partition (that is what makes
   `/` read-only and tamper-evident). When `/proc/cmdline` already shows
   verification removed, the step says so (`/proc/cmdline suggests rootfs
   verification is already removed; running make_dev_ssd.sh anyway`) and
   still runs the tool, because the kernel partition on disk may differ
   from the booted one.
2. **reboot**: `sudo reboot`, only when step 1 succeeded, and not with
   `--no-reboot`. The change takes effect at the next boot either way.

```
$ rootfs -- --partitions 2
chromebrew-scripts 2.1.0 (git 1a2b3c4, single file) on Chrome OS 16093.68.0 (M130, stable-channel)
⚠ Are you sure you want to remove rootfs verification? [y/N]: y

▶ remove rootfs verification
  ... make_dev_ssd.sh's own output ...
  ↑ remove rootfs verification: rootfs verification removed; takes effect after a reboot

▶ reboot
  ✔ reboot: rebooting
```

A failing `make_dev_ssd.sh` stops the command (`make_dev_ssd.sh failed (exit
code N); not rebooting`, exit status 1) and the device is left as it was. A
failing reboot leaves the change made: `reboot failed (exit code N); reboot
by hand to apply the change`. With `--no-reboot` the command ends with
`rootfs verification removed; reboot to apply it`.

### `--partitions`

Recent ChromeOS versions make `make_dev_ssd.sh` refuse to guess which kernel
partition to change and ask you to rerun it with `--partitions N`. Pass that
through:

```
$ rootfs -- --partitions 2
```

`N` is the kernel partition the device booted from: `rootdev -s` prints the
root partition (for example `/dev/mmcblk0p3` or `/dev/nvme0n1p5`), and the
kernel partition is normally the one before it (`2` for root `3`, `4` for
root `5`). `make_dev_ssd.sh --help` lists its other options; everything
after `--` goes to it unchanged, and a dry run shows the complete command.

## What will be affected

* **Verified boot is gone for that root partition.** The ChromeOS developer
  documentation is explicit that once the root filesystem is writable the
  device will not pass verification again, even if nothing is changed. The
  developer-mode boot screen keeps appearing anyway (the device is already
  in developer mode), but the integrity guarantee for `/` is lost until the
  partition is rewritten.
* **OS updates undo it.** ChromeOS installs an update into the other root
  partition and boots from it, verified. After an update `/` is read-only
  and verified again, and `rootfs` has to be run again (this is also why
  changes made under `/` disappear after an update).
* **A recovery image restores everything**, and so does an update as far as
  the root partition is concerned; a [powerwash](powerwash.md) does not
  touch the root partition.
* Nothing else changes at this point: files under `/` are still read-only
  until you run [`rw`](rw.md) after the reboot.

Chromebrew does **not** need this. It installs into `/usr/local`, which is
on the stateful partition and writable in developer mode without touching
the root filesystem. Run `rootfs` only when you want to edit the system
image itself.

## Dry run

`rootfs --dry-run` (`-n`) prints the `make_dev_ssd.sh` command, with the
arguments after `--`, and the reboot, and changes nothing:

```
$ rootfs -ny -- --partitions 2
dry run: nothing will be changed
  · confirmed by --yes: ...

▶ remove rootfs verification
  ◦ would run: sudo /usr/share/vboot/bin/make_dev_ssd.sh --remove_rootfs_verification --partitions 2
  ◦ remove rootfs verification: would run make_dev_ssd.sh --remove_rootfs_verification

▶ reboot
  ◦ would run: sudo reboot
  ◦ reboot: would reboot
```

## Unattended use

`rootfs --yes` needs no terminal; `--yes --no-reboot` leaves the reboot to
you. Exit status 0 when both steps ran (or the reboot was skipped), 1 when
`make_dev_ssd.sh` or the reboot failed. `make_dev_ssd.sh` itself may ask a
question on some versions; it runs with stdin closed and a `TIMEOUT` of 300
seconds, so a question ends the step with a failure rather than a hang.
Check the log for what it printed.

## Troubleshooting

| You see | Why | What to do |
| --- | --- | --- |
| `make_dev_ssd.sh failed (exit code 1)` and its output asks for `--partitions` | newer ChromeOS: the tool wants to know the kernel partition | `rootfs -- --partitions 2` (see above) |
| `sudo: /usr/share/vboot/bin/make_dev_ssd.sh: command not found` | not a ChromeOS developer shell (a Crostini container, ChromeOS Flex without the tool) | run it from crosh's `shell` on a device in developer mode |
| `/proc/cmdline suggests rootfs verification is already removed` | the booted kernel has no dm-verity root | nothing wrong; the tool is run anyway |
| after the reboot `rw` still fails with `mount -o remount,rw / failed` | the other kernel partition was changed, or the device booted the other root | `cbs-check` shows `Rootfs verification`; try the other `--partitions` value (`2` or `4`) |
| `/` is read-only again after an update | updates rewrite the root partition | run `rootfs` again, then `rw` |

## Where the method comes from

`make_dev_ssd.sh --remove_rootfs_verification` is the documented way in the
Chromium OS developer guide ([Developer mode](https://www.chromium.org/chromium-os/developer-library/guides/device/developer-mode/),
"Making changes to the filesystem"), which also carries the warning about
verification. See the [References](../README.md#references).

## Not verified here

The tests run this command against a fake root with a stub
`make_dev_ssd.sh`, `sudo` and `reboot`, and check the argument pass-through
and the no-reboot-on-failure rule. What `make_dev_ssd.sh` does on a current
device, and the `--partitions` prompt, are documented behaviour that CI
cannot exercise.
