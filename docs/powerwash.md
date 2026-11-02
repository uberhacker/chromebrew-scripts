# powerwash

Reset the device to factory settings: schedule a powerwash and reboot.

| | |
| --- | --- |
| Command | `powerwash`, or `chromebrew-scripts powerwash` |
| Runs as | you; the two commands go through `sudo` |
| Needs | ChromeOS (refuses elsewhere), a terminal or `--yes` |
| Options | `--no-reboot` and the [common options](../README.md#usage) |
| Reversible | **No.** Every local file and every user account on the device is erased on the next boot |

## What it does

After the confirmation (`Are you sure you want to reset this device to factory
settings? Every local file and account will be erased. [y/N]`), two steps:

1. **schedule the powerwash**: `echo clobber | sudo tee /mnt/stateful_partition/.update_available`.
   ChromeOS reads this marker when it boots and wipes the stateful partition,
   which is where everything local lives: user profiles, Downloads and
   MyFiles, Crostini (Linux) containers, Android apps, Chromebrew, and these
   scripts if they are installed under `/usr/local`.
2. **reboot**: `sudo reboot`. Skipped with `--no-reboot`; the powerwash then
   happens whenever the device next boots.

The reboot only runs when the marker was written. If `tee` fails the command
stops with `could not write .../.update_available; not rebooting` and exit
status 1. If the reboot itself fails, the marker stays: `reboot failed; the
powerwash runs on the next boot`.

```
$ powerwash
chromebrew-scripts 2.1.0 (git 1a2b3c4, single file) on Chrome OS 16093.68.0 (M130, stable-channel)
⚠ Are you sure you want to reset this device to factory settings? Every local file and account will be erased. [y/N]: y

▶ schedule the powerwash
clobber
  ↑ schedule the powerwash: powerwash scheduled for the next boot

▶ reboot
  ✔ reboot: rebooting
```

## What will be affected

* **Everything on the stateful partition is deleted**: all accounts and
  their data, Downloads and MyFiles, Crostini containers and everything in
  them, Android apps and their data, saved networks, Chromebrew and every
  package installed with `crew`, and this toolkit when it lives in
  `/usr/local`.
* The root filesystem is not touched. Rootfs verification that was removed
  with [`rootfs`](rootfs.md) stays removed, and a device in developer mode
  stays in developer mode (leaving developer mode is done from the firmware
  screen at boot, which itself powerwashes).
* Files on Google Drive, in Google Photos, and the settings synced with your
  Google account are not on the device and are not affected.

## Before you run it

Back up first. `chromebrew --backup` saves the list of installed Chromebrew
packages to `~/MyFiles/Downloads` (see [chromebrew](chromebrew.md)); copy that
file and anything else you need to Google Drive, a USB stick or another
machine **before** the reboot, because `Downloads` is erased too. After the
powerwash and a new `chromebrew --install`, `chromebrew --restore FILE` puts
the packages back.

On a managed (enterprise- or school-enrolled) device a powerwash may be
forbidden by policy, or the device re-enrolls at the next boot. Use the
device's own Powerwash option in the settings if you are unsure; this
command exists for the shell-only cases.

## Dry run

`powerwash --dry-run` (`-n`) prints both commands and changes nothing:

```
$ powerwash -n
dry run: nothing will be changed
...
▶ schedule the powerwash
  ◦ would run: echo clobber | sudo tee /mnt/stateful_partition/.update_available
  ◦ schedule the powerwash: would write clobber to /mnt/stateful_partition/.update_available

▶ reboot
  ◦ would run: sudo reboot
  ◦ reboot: would reboot
```

`--dry-run` still asks for the confirmation (or needs `--yes`), so that a
script that works with `-n` works without it.

## Unattended use

Without a terminal on stdin the command refuses unless `--yes` is given:
`refusing to continue: stdin is not a terminal and --yes was not given`.
`powerwash --yes` wipes the device without any question; `powerwash --yes
--no-reboot` only schedules it. The exit status is 0 when both steps ran, 1
otherwise. Every run is written to the [log](../README.md#logs), which is
on the stateful partition and is erased with the rest.

## Undoing a scheduled powerwash

With `--no-reboot` nothing has happened yet: the powerwash is only the
marker file. Remove it and the next boot is a normal one:

```
$ sudo rm /mnt/stateful_partition/.update_available
```

## Where the method comes from

Writing `clobber` to `.update_available` is the command-line powerwash that
Neverware documented for CloudReady (now ChromeOS Flex); it is what Ed Reel's
original script does. Google's own instructions for a powerwash from the
settings and from the sign-in screen are at
[Reset your Chromebook to factory settings](https://support.google.com/chromebook/answer/183084?hl=en).
See the [References](../README.md#references).

## Not verified here

The test suite runs this command against a fake root with stubbed `sudo`,
`tee` and `reboot`; the marker's effect on a real device is documented
behaviour, not something CI can check. Test on a device you can afford to
reset.
