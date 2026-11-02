# Command reference

One page per command: what it runs, what it changes, what the dry run
shows, what to watch out for, and how to run it from a script. Start with
the [main README](../README.md) for installation, the common options,
configuration, logs and self-update.

| Command | Page | What it does | Changes the device? |
| --- | --- | --- | --- |
| `chromebrew` | [chromebrew.md](chromebrew.md) | install, remove, update or inspect Chromebrew; back up and restore its package list | `--install`, `--remove`, `--update` and `--restore` do; `--status` and `--backup` do not |
| `powerwash` | [powerwash.md](powerwash.md) | schedule a factory reset and reboot | **yes, irreversibly**: every local file and account is erased |
| `rootfs` | [rootfs.md](rootfs.md) | remove rootfs verification with `make_dev_ssd.sh` and reboot | yes: the device no longer passes verified boot |
| `rw` | [rw.md](rw.md) | remount `/` read/write and the stateful partition and user home `exec`; `--undo` reverses it | yes, until the next reboot |
| `cbs-check` | [check.md](check.md) | report the release, channel, developer mode, rootfs verification, mounts, free space, Chromebrew and the toolkit's own state | no, never |

Every command is the same program: `chromebrew-scripts COMMAND [options]`
works too, and `chromebrew-scripts check` is `cbs-check`.

## What every command does the same way

* **Confirmation.** A command that changes something asks `[y/N]` first and
  continues only on a real `y` or `Y`. `--yes` (`-y`) answers it. Without a
  terminal on stdin and without `--yes` the command refuses, so a script
  cannot wipe a device by accident.
* **Dry run.** `--dry-run` (`-n`) prints every command that would run as
  `would run: ...` and changes nothing. The summary is marked `(dry run)`.
  The confirmation is still asked, so `-ny` is the usual way to see a plan.
* **Steps and the summary.** Each command is a few steps; every step prints
  one result line and the run ends with a summary and the totals
  (`N ok, N updated, N skipped, N failed, N dry-run`). A failed step stops
  the command: nothing later runs on a broken premise.
* **Exit status.** 0 when nothing failed, 1 when a step failed or the
  confirmation was refused, 2 for a usage error.
* **ChromeOS only.** `chromebrew --install/--remove/--update`, `powerwash`,
  `rootfs` and `rw` refuse to run when `/etc/lsb-release` does not describe
  ChromeOS (`not ChromeOS`). `cbs-check`, `chromebrew --status`, `--backup`
  and `--restore` run anywhere.
* **A log of every run**, with the full output of every command, in
  `~/.local/state/chromebrew-scripts/` (see [Logs](../README.md#logs)).
* **`sudo` only where needed.** `mount`, `make_dev_ssd.sh`, the powerwash
  marker, `reboot` and `rm -rf` under the Chromebrew prefix go through
  `sudo` (`CBS_SUDO`); everything else, including the whole of `cbs-check`,
  runs as you. Nothing is run as root that does not have to be, and
  `chromebrew --install` refuses to run as root at all.
* **Timeouts.** Every command that is run has a time limit: `TIMEOUT` (300
  seconds) for `mount`, `make_dev_ssd.sh` and `reboot`, `CREW_TIMEOUT`
  (3600) for `crew` and the Chromebrew installer, `DOWNLOAD_TIMEOUT` (300)
  for downloads.

Result icons: `✔ ok`, `↑ updated`, `– skipped`, `◦ dry-run`, `⚠ warn`,
`✖ failed` (in a non-UTF-8 locale `OK`, `UP`, `--`, `..`, `!!`, `XX`).
