# cbs-check

A read-only report of everything the other commands depend on. It never
asks for `sudo`, never changes anything, and runs on any system (off
ChromeOS it says so and fills the rest with `unknown`).

| | |
| --- | --- |
| Command | `cbs-check`, or `chromebrew-scripts check` |
| Runs as | you, without `sudo`; works as root too |
| Needs | nothing; the network only for the toolkit update row (skipped with `--offline`) |
| Options | `--offline` and the [common options](../README.md#usage) |
| Exit status | 0 (2 for a usage error); the rows are information, not a verdict |

## What it shows

```
$ cbs-check
chromebrew-scripts 2.1.0 (git 1a2b3c4, single file) on Chrome OS 16093.68.0 (M130, stable-channel)
  ChromeOS:              yes: Chrome OS 16093.68.0 (M130, stable-channel)
  Release:               16093.68.0 (Official Build) stable-channel octopus
  Release channel:       stable (supported by the Chromebrew installer)
  Board:                 octopus (lsb-release, informational)
  Developer mode:        yes (crossystem devsw_boot)
  Developer shell:       yes (crossystem cros_debug)
  Rootfs verification:   on (dm-verity in /proc/cmdline)
  Crostini container:    no
  / mount:               read-only (ro)
  stateful mount:        noexec (executables blocked)
  user home mount:       noexec (executables blocked)
  Free on stateful:      29.9 GiB (/mnt/stateful_partition)
  Chromebrew prefix:     /usr/local
  crew:                  /usr/local/bin/crew, version 1.59.0
  Toolkit:               chromebrew-scripts 2.1.0 (git 1a2b3c4), single file at /usr/local/bin/chromebrew-scripts
  Toolkit update:        current (matches the latest release)
  Logs:                  /home/chronos/user/.local/state/chromebrew-scripts (newest 20 kept)
  Config:                /home/chronos/user/.config/chromebrew-scripts/config (absent), /etc/chromebrew-scripts.conf (absent)
  Settings (non-default): (defaults)
  log: /home/chronos/user/.local/state/chromebrew-scripts/20261031-201500-cbs-check-4310.log
```

| Row | Read from | Values |
| --- | --- | --- |
| ChromeOS | `/etc/lsb-release`: `CHROMEOS_RELEASE_NAME`, `_VERSION`, `_CHROME_MILESTONE`, `_TRACK` | `yes: ...` or `no: not ChromeOS (...)` |
| Release | `CHROMEOS_RELEASE_DESCRIPTION` | the full description line, when present |
| Release channel | `CHROMEOS_RELEASE_TRACK` without `-channel` | `stable` and `ltc` are what the Chromebrew installer supports; `beta`, `dev` and `canary` are flagged; `unknown` when the file has no track |
| Board | `CHROMEOS_RELEASE_BOARD` | informational only: the lsb-release format documentation says not to rely on this field |
| Developer mode | `crossystem devsw_boot` | `yes` (1), `no` (0), `unknown` when `crossystem` is missing or fails (ChromeOS Flex, a container) |
| Developer shell | `crossystem cros_debug` | the same; `yes` means the developer shell (`shell` in crosh) is available |
| Rootfs verification | `/proc/cmdline` | `on` when the kernel was booted from a dm-verity device (`root=/dev/dm-0` or a `dm=` argument), `off` when neither is there, `unknown` when the file cannot be read |
| Crostini container | `/opt/google/cros-containers` exists | `yes` inside the Linux (Crostini) container, where none of the other commands make sense |
| / mount | `/proc/mounts` options of `/` | `read/write (rw)`, `read-only (ro)`, or `unknown (not found ...)` |
| stateful mount, user home mount | `/proc/mounts` options of `/mnt/stateful_partition` and `/home/chronos/user` | `exec (executables allowed)` or `noexec (executables blocked)` |
| Free on stateful | `df -Pk /mnt/stateful_partition` | GiB or MiB; `unknown (df failed ...)` |
| Chromebrew prefix | the `CREW_PREFIX` setting (default `/usr/local`) | |
| crew | `crew` on `PATH` or `PREFIX/bin/crew`, then `crew version` | path and version, or `not installed` |
| Toolkit | this program | version, git commit, `single file at FILE` or `git checkout at DIR` or `tree install at DIR` |
| Toolkit update | the network (see below) | `current ...`, `update available: run --self-update`, `differs from ORIGIN: run --self-update --dry-run`, `not checked (--offline)` or `unknown (...)` |
| Logs | the `LOGGING`, `LOG_DIR` and `LOG_KEEP` settings | the directory and how many are kept, or `off (LOGGING=0)` |
| Config | the two config file paths | each marked `(absent)` when it does not exist |
| Settings (non-default) | the merged configuration | every setting that is not at its default, with where it came from: `(FILE:LINE)`, `(env)`, `(env OLD_NAME)` or `(flag)` |

Every probe degrades to `unknown` with the reason in parentheses instead of
failing: a missing `crossystem`, an unreadable `/proc/cmdline`, a mount that
is not in `/proc/mounts`, a `df` that fails.

### The toolkit update row

This is the one row that uses the network, and the only part of the command
that can be slow (30 seconds at most):

* A **single file** fetches `chromebrew-scripts.sha256` from the latest
  GitHub release of `SELF_UPDATE_REPO` and compares it with its own
  checksum: `current (matches the latest release)` or `update available: run
  --self-update`. When there is no release or no network: `unknown (could
  not fetch the latest release checksum from ...)`.
* A **git checkout** runs `git ls-remote` on its origin (or on
  `SELF_UPDATE_REPO` when that is configured) and compares the remote `HEAD`
  with the local one: `current (HEAD matches ...)` or `differs from ...: run
  --self-update --dry-run` (a checkout on a development branch differs by
  design).
* A **tree installation** without `.git` cannot tell: `unknown for a tree
  install: run --self-update --dry-run`.

`--offline` skips it: `not checked (--offline)`. Nothing is downloaded or
changed in any case.

## When to use it

* Before `chromebrew --install`, to see the channel and the free space the
  installer's pre-flight checks will look at.
* Before `rw`, to see whether rootfs verification is still on (then `rw`
  cannot remount `/`).
* After `rootfs` and a reboot, to confirm `Rootfs verification: off`.
* When a command behaves unexpectedly: the `Settings (non-default)` row shows
  which configuration is in effect and where it came from, and `Logs` where
  the run logs are.
* From a script: the rows are `  Label:  value` lines that are easy to
  `grep`. The output is the same with `--quiet`.

## Dry run and `--yes`

`cbs-check` changes nothing, so `--dry-run` and `--yes` make no difference;
they are accepted so that the common options can be passed to every command
alike. It takes no other options: `cbs-check --fix` is a usage error (exit
status 2).

## Not verified here

The probes are written from the documentation and tested against fixtures:
a fake `/etc/lsb-release`, `/proc/cmdline`, `/proc/mounts` and a stubbed
`crossystem`. What has not been checked on a device:

* `crossystem devsw_boot` and `cros_debug` as the source for developer mode
  and the developer shell, and what `crossystem` reports on ChromeOS Flex
  (where there is no Chromebook firmware; `unknown` is the expected answer).
* The dm-verity detection in `/proc/cmdline` on current ChromeOS kernels
  (`root=/dev/dm-0` and the `dm=` table are what older documentation shows).
* `crew version` and `crew list installed` as the way to ask Chromebrew for
  its version and the installed packages.

A row that reads `unknown` on your device, or one that is plainly wrong, is
worth an issue with the output of `cat /etc/lsb-release`, `cat
/proc/cmdline`, `crossystem devsw_boot cros_debug` and `grep -E ' / | stateful| chronos' /proc/mounts`.
