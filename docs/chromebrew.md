# chromebrew

Install, remove, update or inspect [Chromebrew](https://github.com/chromebrew/chromebrew),
and back up and restore its package list.

| | |
| --- | --- |
| Command | `chromebrew ACTION [options]`, or `chromebrew-scripts chromebrew ...` |
| Actions | exactly one of `--install` (`-i`), `--remove` (`-r`), `--update` (`-u`), `--status` (`-s`), `--backup [FILE]` (`-b`), `--restore FILE` |
| Runs as | you, the ChromeOS shell user (`chronos`); `--remove` uses `sudo` for `rm -rf` under the prefix. `--install` refuses to run as root |
| Needs | ChromeOS for `--install`, `--remove` and `--update`; `crew` for `--update`, `--backup` and `--restore`; `curl` for `--install` |
| Options | `--force` (`-f`) for `--install`, and the [common options](../README.md#usage) |
| Settings | `CREW_INSTALLER_URL`, `CREW_TIMEOUT`, `CREW_PREFIX`, `FORCE_INSTALL`, `MIN_FREE_MB`, `BACKUP_DIR` |
| Time limit | `CREW_TIMEOUT` (3600 s) per `crew` command and for the installer; `DOWNLOAD_TIMEOUT` (300 s) for the installer download |

## `--install`

Three steps:

1. **pre-flight checks**. The step fails, and nothing is downloaded, when
   * Chromebrew is already installed (`crew` is on `PATH` or in
     `PREFIX/bin`): `use --update, or --remove first`;
   * you are root: `Chromebrew must not be installed as root; run 'chromebrew
     --install' as the chronos user` (the installer refuses too);
   * `curl` is missing.

   These three cannot be overridden. The next three can, with `--force`
   (or `FORCE_INSTALL=1`, or the installer's own `CREW_FORCE_INSTALL=1`),
   because they are what the Chromebrew installer itself rejects or what is
   known to go wrong:
   * the release channel read from `/etc/lsb-release` is not `stable` or
     `ltc` (the installer rejects beta, dev and canary);
   * this is a Crostini (Linux) container (`/opt/google/cros-containers`
     exists); Chromebrew is for the ChromeOS shell, not for the container;
   * less than `MIN_FREE_MB` (1024) MiB are free on `/mnt/stateful_partition`.

   A channel that cannot be read, or a free space that cannot be
   determined, is a warning, not a failure. With `--force` the failed checks
   are listed, the step reports `N check(s) overridden by --force`, and the
   installer is run with `CREW_FORCE_INSTALL=1` too, which (per Chromebrew's
   installer) also makes it install the build tools.
2. **download the Chromebrew installer**: `CREW_INSTALLER_URL` (default
   `https://raw.githubusercontent.com/chromebrew/chromebrew/master/install.sh`)
   with `curl -fsSL`, https only, into a temporary directory.
3. **run the Chromebrew installer**: `yes | bash install.sh` under
   `timeout -k 10 CREW_TIMEOUT`, so its prompts are answered yes. The
   installer downloads and unpacks Chromebrew into `/usr/local` and appends a
   `source .../profile` line to `~/.bashrc`; this command ends with
   `Chromebrew installed; run: source ~/.bashrc`.

```
$ chromebrew --install
chromebrew-scripts 2.1.0 (git 1a2b3c4, single file) on Chrome OS 16093.68.0 (M130, stable-channel)

▶ pre-flight checks
  ✔ pre-flight checks: channel stable, 29.9 GiB free on /mnt/stateful_partition

▶ download the Chromebrew installer
  ✔ download the Chromebrew installer: downloaded https://raw.githubusercontent.com/chromebrew/chromebrew/master/install.sh

▶ run the Chromebrew installer
  · running the Chromebrew installer (answering yes to its prompts)
  ... the installer's own output ...
  ↑ run the Chromebrew installer: Chromebrew installed; run: source /home/chronos/user/.bashrc
```

What the installer does is Chromebrew's business and changes between
versions; its README and wiki (see the [References](../README.md#references))
describe it. This command only checks the ground first and runs it
unattended. A failed installer run is reported as `the Chromebrew installer
failed (exit code N)` with its output in the [log](../README.md#logs).

## `--remove`

Uninstall Chromebrew the way its wiki describes
([How to remove chromebrew](https://github.com/chromebrew/chromebrew/wiki/How-to-remove-chromebrew)),
after the confirmation `Are you sure you want to uninstall Chromebrew? This
clears /usr/local/* [y/N]`:

1. **strip the Chromebrew lines from ~/.bashrc**: `~/.bashrc` is copied to
   `~/.bashrc.chromebrew-scripts.YYYYmmdd-HHMMSS.bak`, then the lines
   matching `source.*profile`, `# DO NOT DELETE THIS LINE` and `# See
   .*profile for further details` are deleted. No `.bashrc`: skipped.
2. **clear /usr/local**: `sudo rm -rf` of every entry under the Chromebrew
   prefix (`CREW_PREFIX`, default `/usr/local`) **except this toolkit**: the
   `chromebrew-scripts` file or tree and the command symlinks that point at
   it are kept (`keeping /usr/local/bin/chromebrew-scripts`), and a
   directory that holds them is cleared entry by entry. The commands keep
   working afterwards.

It refuses a prefix that is not an existing absolute directory, and a prefix
that is plainly not Chromebrew's (`/`, `/usr`, `/home`, `/mnt`,
`/mnt/stateful_partition`, `/etc`, `/opt`, `/var`, ...): `refusing to clear
'...': not a safe Chromebrew prefix`. When `crew` is not found it warns and
still clears whatever is left under the prefix (a half-removed Chromebrew).
`sudo dev_install --reinstall`, which Ed Reel's original ran, is gone from
current ChromeOS and is not run.

Note that the `source.*profile` pattern also removes any other `source ...
profile` line of yours in `~/.bashrc`; the backup has it.

## `--update`

Two steps, both failing cleanly with `chromebrew is not installed` when there
is no `crew`:

1. **crew update**: `timeout -k 10 3600 crew update` (the package index).
2. **crew upgrade**: `yes | timeout -k 10 3600 crew upgrade` (every
   installed package; `yes` answers its prompts, which is what the Chromebrew
   FAQ suggests for a non-interactive upgrade).

A `crew upgrade` can take a long time and download a lot; `CREW_TIMEOUT`
raises the limit. Its output is on the terminal unless `--quiet`, and always
in the log.

## `--status`

Read-only, runs anywhere (no ChromeOS needed, no `sudo`): the toolkit's
version and location, whether ChromeOS was detected, the Chromebrew prefix,
and `crew`'s path and version or `not installed`. For a fuller picture see
[`cbs-check`](check.md).

## `--backup [FILE]`

Writes the names of the installed Chromebrew packages (`crew list installed`,
colour codes stripped, one name per line, sorted) with a header:

```
# chromebrew-scripts package list (chromebrew-scripts 2.1.0 (git 1a2b3c4, single file))
# saved    2026-10-31 20:15:00 +0000
# crew     1.59.0 (/usr/local/bin/crew)
# os       Chrome OS 16093.68.0 (M130, stable-channel)
# restore  chromebrew --restore /home/chronos/user/MyFiles/Downloads/chromebrew-packages-20261031-201500.txt
gcc_lib
python3
vim
```

Where it goes, when no `FILE` is given: `BACKUP_DIR` if set; else
`~/MyFiles/Downloads` or `~/Downloads` when one of them exists (that is the
Downloads folder in the Files app, from where the file can be copied to
Google Drive or a USB stick); else `~/.config/chromebrew-scripts/backups`.
The name is `chromebrew-packages-YYYYmmdd-HHMMSS.txt`. A relative `FILE` is
taken from the current directory.

It needs `crew` and fails without it. A `crew` that reports no packages
produces an empty list with a warning. `--dry-run` says `would write N
package name(s) to FILE` and writes nothing.

The point of it: a [powerwash](powerwash.md) erases Chromebrew with
everything else. Back up, copy the file off the device, powerwash, install
Chromebrew again, restore.

## `--restore FILE`

Reads the package names from `FILE` (comments and blank lines are ignored;
a line that is not a package name is skipped with a warning), asks `crew
list installed` what is already there, and installs the rest **one package
at a time** with `yes | timeout -k 10 3600 crew install NAME`. A package
that fails does not stop the others; they are listed at the end:
`2 failed: foo bar (5 installed, 3 already installed)`, exit status 1.

It needs `crew` (install Chromebrew first) and a readable `FILE`. A file
that lists nothing is a skip. `--dry-run` prints the `crew install` command
for each missing package. Restoring a backup onto the machine it was taken
from is a no-op: `every package in FILE is already installed`.

The file format is plain text, so a list written by hand works too, and a
backup from another device or architecture can be restored; packages that
do not exist for this architecture simply fail and are reported.

## Dry run

`chromebrew ACTION --dry-run` runs the checks and prints every command as
`would run: ...` or `would download ...` without downloading, installing,
removing or writing anything. `--remove -n` lists what it would delete and
keep.

## Unattended use

`--install`, `--update`, `--backup` and `--restore` ask no question;
`--remove` needs `--yes` without a terminal. All of them close stdin for the
commands they run and feed `yes` where Chromebrew prompts, and every `crew`
command and the installer have the `CREW_TIMEOUT` limit, so a hung command
cannot hang the script forever. The exit status is 1 when a step failed.

A typical sequence, for instance from a script that rebuilds a device:

```
chromebrew --backup ~/MyFiles/Downloads/packages.txt   # before the powerwash; copy it away
...
chromebrew --install --yes                            # after the powerwash, as chronos
source ~/.bashrc
chromebrew --restore /path/to/packages.txt --yes
```

## Troubleshooting

| You see | Why | What to do |
| --- | --- | --- |
| `chromebrew is currently installed (...); use --update, or --remove first` | `crew` was found | nothing, or `--remove` first for a clean reinstall |
| `Chromebrew must not be installed as root` | the shell is root (`sudo -i`, or a root shell in crosh) | run it as the normal shell user |
| `the dev channel is not supported by the Chromebrew installer (stable and ltc are)` | `CHROMEOS_RELEASE_TRACK` in `/etc/lsb-release` | switch the device to the stable channel, or `--force` and expect the installer to complain |
| `this is a Crostini container (...)` | you are in the Linux terminal, not the ChromeOS shell | open crosh (Ctrl+Alt+T), `shell`, and run it there |
| `only 512.0 MiB free on /mnt/stateful_partition (MIN_FREE_MB=1024)` | little space for Chromebrew's packages | free space, or lower `MIN_FREE_MB` / `--force` |
| `N check(s) failed; pass --force (or set CREW_FORCE_INSTALL=1) to install anyway` | one of the three overridable checks | read the lines above it; `--force` if you know better |
| `the Chromebrew installer failed (timed out after 3600s)` | a slow connection or a stuck installer | look at the log; `CREW_TIMEOUT=7200` |
| `crew upgrade failed (exit code 1)` | a package failed to build or install | the log has `crew`'s output; `crew upgrade` by hand shows the same |
| `refusing to clear '/usr': not a safe Chromebrew prefix` | `CREW_PREFIX` points somewhere that is not a Chromebrew prefix | fix `CREW_PREFIX` (or the old `CBS_PREFIX`) |
| `cannot write FILE` on `--backup` | the directory is not writable | `--backup /some/other/file`, or `BACKUP_DIR` |

## Not verified here

`crew list installed` as the way to list the installed packages, `crew
version` for the version, and the installer's prompts and `CREW_FORCE_INSTALL`
behaviour are taken from Chromebrew's documentation and tested against a stub
`crew` and a stub installer, not against a device. The missing-`curl` check
cannot be tested either (the test machines have `curl`). If `crew list
installed` prints something the parser does not expect, the backup will be
short: check the file before you rely on it.
