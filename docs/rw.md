# rw

Mount the root filesystem read/write, and allow executables on the stateful
partition and in the user's home. `rw --undo` (or `--ro`) reverses it.

| | |
| --- | --- |
| Command | `rw`, `rw --undo`, or `chromebrew-scripts rw [--undo]` |
| Runs as | you; each `mount` goes through `sudo` |
| Needs | ChromeOS (refuses elsewhere), a terminal or `--yes`, and for `/` [rootfs verification removed](rootfs.md) |
| Options | `--undo` / `--ro` and the [common options](../README.md#usage) |
| Reversible | Yes: `rw --undo`, or simply a reboot (mount options do not survive one) |

## What it does

After the confirmation (`Are you sure you want to mount the filesystem
read/write? [y/N]`), three steps, each skipped when `/proc/mounts` already
shows the wanted state:

| Step | Command | Skipped when |
| --- | --- | --- |
| remount / read/write | `sudo mount -o remount,rw /` | `/` is mounted `rw` |
| allow executables on /mnt/stateful_partition | `sudo mount -o remount,exec /mnt/stateful_partition` | it is mounted without `noexec` |
| allow executables on /home/chronos/user | `sudo mount -i -o remount,exec /home/chronos/user` | it is mounted without `noexec` |

`-i` on the last one tells `mount` not to call a mount helper for that
filesystem. The commands run with a `TIMEOUT` of 300 seconds each.

`rw --undo` runs the opposite three in the same order: `remount,ro /`, then
`remount,noexec` on the stateful partition and the user home (`-i` again),
with the same skip rule.

```
$ rw
chromebrew-scripts 2.1.0 (git 1a2b3c4, single file) on Chrome OS 16093.68.0 (M130, stable-channel)
⚠ Are you sure you want to mount the filesystem read/write? [y/N]: y

▶ remount / read/write
  ↑ remount / read/write: remounted rw

▶ allow executables on /mnt/stateful_partition
  ↑ allow executables on /mnt/stateful_partition: remounted exec

▶ allow executables on /home/chronos/user
  – allow executables on /home/chronos/user: already mounted exec
  · you should now have full read/write access (rw --undo reverses it)

Summary
  ↑ updated  remount / read/write                          remounted rw
  ↑ updated  allow executables on /mnt/stateful_partition remounted exec
  – skipped  allow executables on /home/chronos/user      already mounted exec
  0 ok, 2 updated, 1 skipped, 0 failed, 0 dry-run
  log: /home/chronos/user/.local/state/chromebrew-scripts/20261031-201500-rw-4231.log
```

A `mount` that fails stops the command: `mount -o remount,rw / failed (exit
code 32)`, the later steps do not run, and the exit status is 1. The most
common cause is rootfs verification still being on; `cbs-check` shows it.

## What will be affected

* `/` becomes writable until the next reboot. Anything written there
  changes the ChromeOS system image; a mistake can leave the device unable
  to boot, and recovery (a USB recovery image) is the way back. ChromeOS
  updates install into the other root partition and leave your changes
  behind.
* Programs on the stateful partition and in the user home can be executed.
  ChromeOS mounts both `noexec` on purpose; `exec` weakens that protection
  for everything on them, not only for what you intended to run.
* Nothing persists: mount options are reset at boot. Run `rw` again after a
  reboot when you need it, or make the change in `/etc/fstab`-equivalents
  yourself (this toolkit does not).

Chromebrew does **not** need any of this. `crew` installs into `/usr/local`,
which is already writable and executable in developer mode. `rw` is for
editing the root filesystem itself.

## Dry run

`rw --dry-run` (`-n`) prints the three `mount` commands (or the skips) and
changes nothing; `rw --undo -n` does the same for the reverse. Both still
need the confirmation or `--yes`.

```
$ rw -ny
dry run: nothing will be changed
  · confirmed by --yes: Are you sure you want to mount the filesystem read/write?

▶ remount / read/write
  ◦ would run: sudo mount -o remount,rw /
  ◦ remount / read/write: would remount rw
...
  0 ok, 0 updated, 0 skipped, 0 failed, 3 dry-run
```

## Unattended use

`rw --yes` needs no terminal. Because steps that are already in the wanted
state are skipped, running it from a script at every login is harmless when
nothing changed. Exit status 0 when every step succeeded or was skipped, 1
when a mount failed. Without `--yes` and without a terminal it refuses.

## Troubleshooting

| You see | Why | What to do |
| --- | --- | --- |
| `remount / read/write: mount -o remount,rw / failed (exit code 32)` | the root filesystem is verified (dm-verity) and cannot be made writable | `cbs-check` shows `Rootfs verification: on`; run [`rootfs`](rootfs.md) and reboot first |
| `already mounted rw` / `already mounted exec` | nothing to do | nothing; the state is read from `/proc/mounts` |
| the device refuses to boot after you edited files under `/` | the system image is damaged | recover the device with a recovery USB stick; see the References in the README |
| `sudo: a password is required` | the shell asks for the developer password | type it; `rw` does not store or pass passwords |

## Not verified here

The tests run `rw` against a fake root with a stubbed `mount` and a fake
`/proc/mounts`; the remount commands are Ed Reel's original ones and are not
exercised on a real device by CI.
