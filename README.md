# chromebrew-scripts

**Shell helpers for a ChromeOS device in developer mode**: install, remove,
update, back up and restore [Chromebrew](https://github.com/chromebrew/chromebrew),
powerwash the device, remove rootfs verification, remount the root
filesystem read/write (and back), and a read-only check that shows the state
of all of that first.

```
$ cbs-check                 # release, channel, developer mode, rootfs verification, mounts, free space, crew
$ chromebrew --install      # pre-flight checks, then Chromebrew's installer, unattended
$ rw --dry-run              # what rw would run; nothing changes
```

It is plain bash (4.4 or newer) with coreutils, `grep` and `sed`, plus `curl`
for downloads; everything ChromeOS already has in its developer shell. Every
command asks before it changes anything, has a real dry run, writes a log of
what it did, and refuses to run unattended unless you say `--yes`.

This is a modular rewrite of [Ed Reel's](https://github.com/uberhacker)
[chromebrew-scripts](https://github.com/uberhacker/chromebrew-scripts). The
commands, their names and what they do are his; see
[Changes from the original](#changes-from-the-original).

### Highlights

* **Five commands, one program.** `chromebrew`, `powerwash`, `rootfs`, `rw`
  and `cbs-check` are symlinks to one file, `chromebrew-scripts`, which also
  runs them as `chromebrew-scripts COMMAND`. It installs as that single
  file, or as a checkout you can `git pull`.
* **A real dry run for everything** (`--dry-run`): every command that would
  run is printed as `would run: ...`, and nothing runs.
* **Confirmation that cannot be skipped by accident.** Destructive commands
  ask `[y/N]` and accept only a real `y`; without a terminal they refuse
  unless `--yes` is given.
* **Pre-flight checks before installing Chromebrew**: not root, `curl`
  present, not a Crostini container, a channel the installer supports,
  enough free space. `--force` when you know better.
* **Back up and restore the Chromebrew package list** (`chromebrew --backup`,
  `--restore`), so a powerwash is not the end of your packages.
* **`rw --undo`** puts the mounts back; **`cbs-check`** tells you where you
  stand without `sudo`.
* **A log of every run**, with each command's complete output, exit status
  and timing, in a private directory.
* **Configuration** from a small `KEY=value` file, the environment or flags,
  parsed and never sourced.
* **`--self-update`** for every install method, verifying a published
  checksum before a single file is replaced.
* **Documented command by command.** Every command has a page in
  [`docs/`](docs/README.md) saying what it runs, what it changes, and what
  to watch out for.

## WARNING

If used improperly, these scripts can render your system useless. Proceed
with caution and do not execute unless you know what you're doing. Review the
[References](#references) section to understand the impact of the changes. As
true of any open source software, nobody is responsible if you brick your
system.

That warning is Ed's and it still holds. `powerwash` erases everything on the
device. `rootfs` and `rw` turn off the protection that makes a Chromebook hard
to break. Run `cbs-check` and `--dry-run` first, and read
[Before you run it](#before-you-run-it).

## Contents

* [Quick start](#quick-start)
* [What it does](#what-it-does)
* [Before you run it](#before-you-run-it)
* [Dry run](#dry-run)
* [Installation](#installation), [single file](#single-file), [tree layout](#the-tree-layout) and [tab completion](#tab-completion)
* [Usage](#usage) and [examples](#examples)
* [Configuration](#configuration) · [Logs](#logs) · [Self-update](#self-update)
* [Running it from a script](#running-it-from-a-script) · [Troubleshooting](#troubleshooting)
* [Development](#development)
* [Changes from the original](#changes-from-the-original) · [References](#references) · [License](#license)

## Quick start

On the device, open crosh (Ctrl+Alt+T), type `shell`, then:

```
$ curl -fLO https://github.com/uberhacker/chromebrew-scripts/releases/latest/download/chromebrew-scripts
$ curl -fLO https://github.com/uberhacker/chromebrew-scripts/releases/latest/download/chromebrew-scripts.sha256
$ sha256sum -c chromebrew-scripts.sha256
$ sudo install -m 0755 chromebrew-scripts /usr/local/bin/chromebrew-scripts
$ chromebrew-scripts check              # where do we stand? (read-only)
$ chromebrew-scripts chromebrew -i      # install Chromebrew
```

Or clone it (with `git` from Chromebrew, or on any Linux machine to look at
it) and install from the checkout, which also sets up the command names and
tab completion:

```
$ git clone https://github.com/uberhacker/chromebrew-scripts.git
$ cd chromebrew-scripts
$ ./bin/cbs-check                       # runs from the checkout as well
$ ./install.sh                          # /usr/local/bin/chromebrew-scripts + chromebrew, powerwash, rootfs, rw, cbs-check
$ rw --dry-run
```

Run the commands as yourself (the `chronos` shell user), not with `sudo`:
they ask for `sudo` themselves where a step needs it, and `chromebrew
--install` must not run as root. See [Installation](#installation) for the
details and the single-file and tree layouts.

## What it does

| Command | What it does | Details |
| --- | --- | --- |
| `chromebrew -i` / `--install` | pre-flight checks, then downloads Chromebrew's `install.sh` and runs it with its prompts answered yes | [docs/chromebrew.md](docs/chromebrew.md) |
| `chromebrew -r` / `--remove` | backs up `~/.bashrc` and strips Chromebrew's lines, then clears `/usr/local/*` except this toolkit | [docs/chromebrew.md](docs/chromebrew.md#--remove) |
| `chromebrew -u` / `--update` | `crew update`, then `yes \| crew upgrade`, each under a time limit | [docs/chromebrew.md](docs/chromebrew.md#--update) |
| `chromebrew -s` / `--status` | is `crew` installed? version, prefix, ChromeOS detected? (read-only) | [docs/chromebrew.md](docs/chromebrew.md#--status) |
| `chromebrew -b` / `--backup [FILE]` | saves the installed package list to `~/MyFiles/Downloads` (or `FILE`) | [docs/chromebrew.md](docs/chromebrew.md#--backup-file) |
| `chromebrew --restore FILE` | installs every package in `FILE` that is missing, one by one | [docs/chromebrew.md](docs/chromebrew.md#--restore-file) |
| `powerwash [--no-reboot]` | writes `clobber` to `/mnt/stateful_partition/.update_available` and reboots: factory reset on the next boot | [docs/powerwash.md](docs/powerwash.md) |
| `rootfs [--no-reboot] [-- args]` | `sudo make_dev_ssd.sh --remove_rootfs_verification`, then reboots only if that succeeded | [docs/rootfs.md](docs/rootfs.md) |
| `rw` | `mount -o remount,rw /`, `remount,exec` on `/mnt/stateful_partition` and `/home/chronos/user` | [docs/rw.md](docs/rw.md) |
| `rw --undo` (`--ro`) | the reverse: `/` read-only, both partitions `noexec` again | [docs/rw.md](docs/rw.md) |
| `cbs-check` (`chromebrew-scripts check`) | release and channel, developer mode, rootfs verification, mounts, free space, Chromebrew, toolkit version and whether it is current; never `sudo` | [docs/check.md](docs/check.md) |

A run looks like this:

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

Every command is a short sequence of steps. Each step prints one result
line, and the run ends with a summary, the totals and the path of its log:

| Result | Meaning | Exit status |
| --- | --- | --- |
| `✔ ok` | done, or nothing needed doing | unchanged |
| `↑ updated` | something was changed | unchanged |
| `– skipped` | not applicable, already in the wanted state (the note says why) | unchanged |
| `◦ dry-run` | what would happen; nothing was changed | unchanged |
| `⚠ warn` | done, but look at the note (a pre-flight check overridden with `--force`) | unchanged |
| `✖ failed` | the step's command failed; the later steps of that command do not run | **1** |

The exit status is 0 unless a step failed or the confirmation was refused,
and 2 for a usage error. In a terminal without UTF-8 the icons are `OK`,
`UP`, `--`, `..`, `!!` and `XX`.

`cbs-check` is the one command that only reads:

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
```

## Before you run it

The per-command pages say exactly what each one changes. The short version:

* **`powerwash` erases the device.** Every account, every local file
  (Downloads, MyFiles, Crostini containers, Android apps), Chromebrew and
  its packages, and this toolkit if it lives in `/usr/local`. Nothing comes
  back. `chromebrew --backup` first, and copy that file somewhere else
  (Google Drive, a USB stick), because Downloads is erased too. On a managed
  device, policy may forbid it or re-enroll the device.
* **`rootfs` disables verified boot for the root partition.** Once the root
  filesystem is writable the device no longer passes verification, even if
  you change nothing. An OS update installs a fresh, verified root and undoes
  it (and your changes under `/` with it); a recovery image restores
  everything.
* **`rw` makes `/` writable and lets programs run from the stateful partition
  and your home**, until the next reboot. A mistake under `/` can leave the
  device unbootable; recovery is the way back.
* **Chromebrew needs none of that.** `crew` installs into `/usr/local`,
  which is writable and executable in developer mode. `rootfs` and `rw` are
  for people who want to edit the system image itself.
* **`chromebrew --install` runs Chromebrew's installer**, a script fetched
  from GitHub over https and run with its prompts answered yes, as you (never
  as root). What it does is Chromebrew's business; the pre-flight checks only
  make sure the ground is what the installer expects.
* **`chromebrew --remove` deletes everything under `/usr/local`** except this
  toolkit, and edits `~/.bashrc` (with a backup next to it).
* **Nothing is undoable by the toolkit except `rw`** (`rw --undo`, or a
  reboot).
* **Developer mode is assumed.** The developer shell (`shell` in crosh),
  `sudo`, `make_dev_ssd.sh` and `/usr/local` being writable all come with
  developer mode. Turning developer mode on or off is done from the firmware
  screens at boot and itself powerwashes the device; none of these commands
  does that.

Run `cbs-check`, then the command with `--dry-run`, before the real thing.

## Dry run

`--dry-run` (`-n`) makes every command print what it would run and change
nothing. The confirmation is still asked (or answered by `--yes`), so a
command line that works with `-n` works without it:

```
$ powerwash -ny
chromebrew-scripts 2.1.0 (git 1a2b3c4, single file) on Chrome OS 16093.68.0 (M130, stable-channel)
dry run: nothing will be changed
  · confirmed by --yes: Are you sure you want to reset this device to factory settings? Every local file and account will be erased.

▶ schedule the powerwash
  ◦ would run: echo clobber | sudo tee /mnt/stateful_partition/.update_available
  ◦ schedule the powerwash: would write clobber to /mnt/stateful_partition/.update_available

▶ reboot
  ◦ would run: sudo reboot
  ◦ reboot: would reboot

Summary (dry run)
  ◦ dry-run  schedule the powerwash would write clobber to /mnt/stateful_partition/.update_available
  ◦ dry-run  reboot                 would reboot
  0 ok, 0 updated, 0 skipped, 0 failed, 2 dry-run
  log: /home/chronos/user/.local/state/chromebrew-scripts/20261031-201500-powerwash-4302.log
```

A dry run still reads: `/etc/lsb-release`, `/proc/mounts`, `df`, `crew list
installed` for `--backup`, and the pre-flight checks of `--install`. It never
downloads anything, never calls `sudo`, and writes nothing but its log.
`--self-update --dry-run` fetches what it needs to say what it would do
(see [Self-update](#self-update)) and changes nothing.

## Installation

Requirements: bash 4.4 or newer, GNU coreutils (`install`, `mktemp`,
`sha256sum`, `timeout`), `grep`, `sed`, and `curl` for the downloads
(`chromebrew --install`, `--self-update`). A ChromeOS developer shell has all
of them; so does any Linux distribution, where everything but the ChromeOS
commands themselves works (`cbs-check`, `chromebrew --status`, `--backup`,
`--restore`, `--help`, `--dry-run` with `CBS_ASSUME_CHROMEOS=1` for testing).

`install.sh` installs the **single file** `chromebrew-scripts` plus the five
command symlinks next to it, and the bash completion. System wide, which is
the layout for a ChromeOS device:

```
$ git clone https://github.com/uberhacker/chromebrew-scripts.git
$ cd chromebrew-scripts
$ ./install.sh                  # -> /usr/local/bin/chromebrew-scripts, chromebrew, powerwash, rootfs, rw, cbs-check
```

`install.sh` asks for `sudo` only when `/usr/local` is not writable by you
(on a device with Chromebrew it usually is). `/usr/local` is on the stateful
partition and is executable in developer mode, `chromebrew --remove` leaves
the toolkit there alone, and a powerwash erases it with everything else.

Other layouts:

```
$ ./install.sh --user           # ~/.local/bin and ~/.local/share/chromebrew-scripts, no sudo
$ ./install.sh --prefix DIR     # DIR/bin and DIR/share
$ ./install.sh --tree           # the whole checkout under PREFIX/share/chromebrew-scripts, see below
$ ./install.sh --uninstall      # with the same --user / --prefix as the install
$ ./install.sh --update         # download the configured branch and reinstall (the 2.0.0 way; --self-update does the same)
```

`--user` is for a Linux machine or a test: on ChromeOS the home directory is
mounted `noexec`, so a script in `~/.local/bin` cannot be executed directly
(after `rw` it can, until the reboot). Install into `/usr/local` on the
device.

A 2.0.0 installation (`/usr/local/share/chromebrew-scripts` with symlinks
in `/usr/local/bin`) is recognised and replaced; foreign files with the same
names are left alone and reported. An installation made as root, or into a
directory only root can write, belongs to root and is updated with `sudo`.
Running the commands from the checkout (`./bin/rw`) works too.

### Single file

The whole toolkit is **one executable file**, which is what `install.sh`
installs and what the [releases](https://github.com/uberhacker/chromebrew-scripts/releases)
publish. It is the same bash code with every module inlined (nothing is
compiled), it needs the same bash 4.4 and coreutils, and it behaves exactly
like the checkout: the test suite runs every test against both.

From a release (each `v*` tag publishes `chromebrew-scripts` and its
`.sha256`), without `git`:

```
$ curl -fLO https://github.com/uberhacker/chromebrew-scripts/releases/latest/download/chromebrew-scripts
$ curl -fLO https://github.com/uberhacker/chromebrew-scripts/releases/latest/download/chromebrew-scripts.sha256
$ sha256sum -c chromebrew-scripts.sha256
$ sudo install -m 0755 chromebrew-scripts /usr/local/bin/chromebrew-scripts
$ cd /usr/local/bin && for c in chromebrew powerwash rootfs rw cbs-check; do sudo ln -s chromebrew-scripts "$c"; done
```

The symlinks are a convenience: `chromebrew-scripts rw`, `chromebrew-scripts
chromebrew -i` and `chromebrew-scripts check` work without them. The file
dispatches on the name it was called by, or on its first argument.

Or build it from a checkout:

```
$ ./build.sh                         # writes dist/chromebrew-scripts
$ ./build.sh ~/bin/chromebrew-scripts
```

`chromebrew-scripts --version` says `single file` and which commit it was
built from. Tab completion is built in (`source <(chromebrew-scripts
--completion bash)`), and `--self-update` replaces the file with the latest
release after verifying its checksum (see [Self-update](#self-update)). A
build is never edited by hand: change the modules and rebuild.

### The tree layout

`install.sh --tree` copies the checkout (with its `.git` directory, when it
is one) to `PREFIX/share/chromebrew-scripts` and links the commands into
`PREFIX/bin`. Choose it when you want `--self-update` to follow a **branch**
(`git pull --ff-only`, or the branch tarball for a tree without `.git`)
instead of the releases. `install.sh --update` keeps a tree a tree; `install.sh`
without `--tree` replaces it with the single file.

### Tab completion

`install.sh` puts the [bash completion](completions/chromebrew-scripts.bash)
into bash-completion's directory (`/usr/local/share/bash-completion/completions`,
or `~/.local/share/bash-completion/completions` with `--user`), so new shells
complete the command names after `chromebrew-scripts`, every option of each
command, and the values of `--color`, `--completion` and `--config`:

```
$ chromebrew-scripts <Tab><Tab>       ->  chromebrew  powerwash  rootfs  rw  check  --dry-run ...
$ chromebrew --re<Tab><Tab>           ->  --remove  --restore
$ rw --u<Tab>                         ->  rw --undo
```

This needs the `bash-completion` package, which the ChromeOS shell does not
have (Chromebrew packages it). Without it, or in zsh:

```
$ source <(chromebrew-scripts --completion bash)                                 # bash, any layout
$ autoload -U bashcompinit && bashcompinit && source <(chromebrew-scripts --completion bash)   # zsh
```

The option lists in the completion are checked against each command's
`--help` by the test suite, so they cannot drift.

## Usage

```
Usage: chromebrew-scripts COMMAND [options]
       chromebrew-scripts --self-update [--dry-run] [--source URL]
       chromebrew-scripts --completion bash | --version | --help

Chromebrew and ChromeOS helpers. Commands:
  chromebrew   install, remove, update or inspect Chromebrew; back up and
               restore its package list (--backup / --restore)
  powerwash    reset the device to factory settings
  rootfs       remove rootfs verification
  rw           mount the root filesystem read/write (--undo: read-only again)
  check        read-only report: release, channel, developer mode, rootfs
               verification, mounts, free space, Chromebrew, toolkit version

Installed as symlinks named after the commands (chromebrew, powerwash,
rootfs, rw, cbs-check) this file runs that command directly.
"chromebrew-scripts COMMAND --help" shows a command's options.

Common options (every command):
  -n, --dry-run           print what would be done; change nothing
  -y, --yes               answer the [y/N] confirmation (required without a terminal)
  -v, --verbose           show every command that is run
  -q, --quiet             hide third-party output; show only status lines
      --no-color          disable colours (NO_COLOR and non-TTY output do too)
      --color WHEN        auto (default), always or never
      --timeout SECONDS   per-command timeout (default 300; crew: CREW_TIMEOUT)
      --config FILE       read this config file instead of the user config
      --log FILE          write this run's log to FILE
      --no-log            do not write a log file for this run
      --self-update       update chromebrew-scripts itself and exit
      --source URL        source for --self-update (https only; a fork)
      --branch NAME       branch for --self-update (git checkout or tree install)
      --version           print the version and exit
  -h, --help              show this help and exit
```

The commands' own options:

| Command | Options |
| --- | --- |
| `chromebrew` | exactly one action: `-i`/`--install`, `-r`/`--remove`, `-u`/`--update`, `-s`/`--status`, `-b`/`--backup [FILE]`, `--restore FILE`; and `-f`/`--force` for `--install` |
| `powerwash` | `--no-reboot` |
| `rootfs` | `--no-reboot`; anything after `--` goes to `make_dev_ssd.sh` (`rootfs -- --partitions 2`) |
| `rw` | `--undo` (or `--ro`) |
| `cbs-check` | `--offline` (skip the network lookup of the newest toolkit version) |

Short flags combine: `-ny` is `--dry-run --yes`. `--opt=value` works for
every option that takes a value. Destructive commands (`powerwash`, `rootfs`,
`rw`, `chromebrew --remove`) ask for confirmation and accept only a real
`y`/`Y`; without a terminal on stdin they refuse unless `--yes` is given.
`--verbose` shows each command as it is run (`$ sudo mount ...`); `--quiet`
hides the output of `crew`, the installer and `mount`, keeping this
program's own status lines, warnings and the summary (the hidden output is
still in the log).

Every command refuses to run on anything that is not ChromeOS (`not
ChromeOS`), except `cbs-check`, `chromebrew --status`, `--backup`,
`--restore`, `--help`, `--version` and `--self-update`. `CBS_ASSUME_CHROMEOS=1`
skips the check, for tests and CI only.

### Examples

```
$ cbs-check                                   # the lay of the land, read-only
$ chromebrew --install                        # pre-flight checks, then Chromebrew's installer
$ chromebrew --install --force                # ... even on the beta channel or with little space
$ chromebrew --update                         # crew update; yes | crew upgrade
$ chromebrew --backup                         # package list -> ~/MyFiles/Downloads/chromebrew-packages-<date>.txt
$ chromebrew --backup -n                      # how many packages, which file; writes nothing
$ chromebrew --restore ~/MyFiles/Downloads/chromebrew-packages-20261031-201500.txt
$ chromebrew --remove --dry-run               # what --remove would delete and keep
$ rw -n                                       # the three mount commands, nothing runs
$ rw                                          # remount / rw, stateful and home exec
$ rw --undo                                   # and back
$ rootfs -- --partitions 2                    # remove rootfs verification (newer ChromeOS wants the kernel partition)
$ rootfs --no-reboot -- --partitions 2        # the same, reboot yourself later
$ powerwash -n                                # the plan
$ powerwash                                   # erase the device after a y
$ powerwash --yes --no-reboot                 # schedule it from a script; the next boot does it
$ chromebrew-scripts --self-update --dry-run  # is a newer version available? nothing changes
$ chromebrew-scripts --self-update            # update this toolkit
$ rw --verbose --no-color                     # show the commands, plain output
```

## Configuration

Settings come, lowest precedence first, from the built-in defaults,
`/etc/chromebrew-scripts.conf`, `${XDG_CONFIG_HOME:-~/.config}/chromebrew-scripts/config`
(or `--config FILE`), environment variables of the same name, and command
line flags. Files are `KEY=value` lines that are parsed, never sourced, so
nothing in them can run code; quotes around a value are optional; unknown
keys and invalid values are reported and ignored. See
[`config.example`](config.example). `cbs-check` shows every setting that is
not at its default and where it came from (`Settings (non-default)`), and the
run log's header records the same.

| Key | Default | Meaning |
| --- | --- | --- |
| `SELF_UPDATE_REPO` | `https://github.com/uberhacker/chromebrew-scripts` | source for `--self-update` (https only); unset, a git checkout follows its own origin |
| `SELF_UPDATE_BRANCH` | empty | branch for `--self-update` of a git checkout or tree install; empty follows the checkout's branch if the remote has it, else the remote's default branch. A single file follows the releases and ignores it |
| `TIMEOUT` | `300` | seconds a command may run (`mount`, `make_dev_ssd.sh`, `reboot`); also `--timeout` |
| `CREW_TIMEOUT` | `3600` | seconds a `crew` command or the Chromebrew installer may run |
| `DOWNLOAD_TIMEOUT` | `300` | seconds a download may take |
| `CREW_INSTALLER_URL` | `https://raw.githubusercontent.com/chromebrew/chromebrew/master/install.sh` | the installer `chromebrew --install` downloads and runs (https only) |
| `CREW_PREFIX` | empty (`/usr/local`) | the Chromebrew prefix, which `--remove` clears and `--status`/`cbs-check` report |
| `FORCE_INSTALL` | `0` | install anyway when an overridable pre-flight check fails; also `--force` and `CREW_FORCE_INSTALL=1` |
| `MIN_FREE_MB` | `1024` | free MiB required on `/mnt/stateful_partition` before `--install` |
| `BACKUP_DIR` | empty | where `--backup` writes without a `FILE`; empty is `~/MyFiles/Downloads`, `~/Downloads` or `~/.config/chromebrew-scripts/backups` |
| `COLOR` | `auto` | `auto` (a terminal, unless `NO_COLOR`), `always`, `never`; also `--color`, `--no-color` |
| `LOGGING` | `1` | write a [log](#logs) for every run; `--no-log` for one run |
| `LOG_DIR` | empty | where logs go; empty is `/var/log/chromebrew-scripts` as root, `${XDG_STATE_HOME:-~/.local/state}/chromebrew-scripts` otherwise |
| `LOG_KEEP` | `20` | how many logs to keep; `0` keeps all |

The 2.0.0 environment names still work, with the lowest priority among the
environment: `CBS_CREW_INSTALLER_URL`, `CBS_CREW_TIMEOUT`, `CBS_CURL_TIMEOUT`
(now `DOWNLOAD_TIMEOUT`), `CBS_PREFIX` (now `CREW_PREFIX`),
`CREW_FORCE_INSTALL` (now `FORCE_INSTALL`), `CBS_REF` (now
`SELF_UPDATE_BRANCH`), and `CBS_REPO=owner/name` for `install.sh --update`.
`cbs-check` shows them as `(env CBS_PREFIX)` and so on.

A second set of variables relocates every path the toolkit touches, so that
the tests and CI can run against a fake root; they are not configuration and
have no config-file form: `CBS_ROOT` (prefix for all of the following),
`CBS_LSB_RELEASE`, `CBS_STATEFUL`, `CBS_VBOOT_BIN`, `CBS_USER_HOME`,
`CBS_ROOTFS_MOUNT`, `CBS_PROC_MOUNTS`, `CBS_PROC_CMDLINE`, `CBS_CROSTINI_DIR`,
`CBS_CROSSYSTEM`, `CBS_HOME`, `CBS_SYSTEM_CONFIG`, `CBS_SUDO` (the privilege
command, default `sudo`; empty never escalates) and `CBS_ASSUME_CHROMEOS=1`.

## Logs

Every run (real or dry) writes a log file; the summary ends with its path:

```
  0 ok, 2 updated, 1 skipped, 0 failed, 0 dry-run
  log: /home/chronos/user/.local/state/chromebrew-scripts/20261031-201500-rw-4231.log
```

The terminal shows what you need to follow the run (`--quiet` keeps only this
program's own lines; `crew`'s or the installer's output then exists only in
the log); the log has everything, so a failed step can be looked at
afterwards:

* **A header** describing the run: version and commit, start time, host and
  kernel, the ChromeOS release and board, user, the full command line, the
  program file (and `(single file)`), dry or real run, and every setting
  that differs from its default and where it came from.
* **Every message**, timestamped and without colours, including the ones
  `--quiet` hides and the verbose-only ones (the commands as they are run).
* **Every command**: its command line, its complete output (stdout and
  stderr), then `-> exit N after Ns`.
* **The confirmation** and your answer.
* **A footer** with the end time, exit status and duration.

```
# chromebrew-scripts 2.1.0 (git 1a2b3c4)
# started  2026-10-31 20:15:00 +0000
# host     localhost (Linux 6.6.x x86_64)
# os       Chrome OS 16093.68.0 (M130, stable-channel)
# board    octopus, Official Build (from lsb-release, informational)
# user     chronos (uid 1000)
# command  powerwash -y --no-reboot
# program  /usr/local/bin/chromebrew-scripts (single file)
# mode     real run

20:15:00 chromebrew-scripts 2.1.0 (git 1a2b3c4, single file) on Chrome OS 16093.68.0 (M130, stable-channel)
20:15:00   · confirmed by --yes: Are you sure you want to reset this device to factory settings? ...

20:15:00 ▶ schedule the powerwash
20:15:00   $ echo clobber | sudo tee /mnt/stateful_partition/.update_available
clobber
20:15:00   -> exit 0 after 0s
20:15:00   ↑ schedule the powerwash: powerwash scheduled for the next boot
...
# finished 2026-10-31 20:15:01 +0000, exit status 0, 1s
```

| | |
| --- | --- |
| Where | `${XDG_STATE_HOME:-~/.local/state}/chromebrew-scripts/` (`/home/chronos/user/.local/state/...` on the device), `/var/log/chromebrew-scripts/` when run as root, or `LOG_DIR` |
| Names | `YYYYmmdd-HHMMSS-<command>-PID.log`, plus `latest.log` pointing at the newest |
| Kept | the newest `LOG_KEEP` (20); older ones are deleted at the start of a run |
| Permissions | 0600, in a 0700 directory created on first use: logs show package lists, paths and the hostname |
| Off | `--no-log` for one run, `LOGGING=0` for good |
| One file | `--log FILE` writes to exactly that file and prunes nothing |
| Never | `--help`, `--version`, `--completion` and usage errors write no log |

`cbs-check` shows where logs go. A log directory that cannot be created is a
warning (`this run is not logged`), never a reason to stop. On ChromeOS the
logs live on the stateful partition, so a powerwash erases them too.

## Self-update

`chromebrew-scripts --self-update` (or `rw --self-update`, any command name
works) updates the toolkit itself and exits. What it does depends on how it
was installed:

* **A git checkout** (also a `--tree` install from a checkout): `git fetch`
  and `git pull --ff-only` from the remote the checkout was cloned from
  (`origin`), on the configured branch. When `SELF_UPDATE_REPO` or
  `--source` names a repository, `origin` must be that repository;
  `--source` re-points it, a config value that differs is refused. It
  refuses a checkout with local changes, follows only `https`, `ssh` or
  `git+ssh` remotes, and never runs `git reset --hard`. A checkout on a
  branch the remote does not have is **switched** to the configured branch
  (the remote's default, usually `master`), and the dry run says so (`would
  switch from my-branch to master at ...`).
* **A tree without `.git`**: downloads the branch tarball of
  `SELF_UPDATE_REPO` over https, checks that it looks like this toolkit
  (`bin/chromebrew-scripts` and `lib/core` present, every file passes `bash
  -n`), and swaps the directory in with two renames; the old tree is removed
  only after the swap succeeded.
* **A single file**: fetches `chromebrew-scripts.sha256` from the latest
  GitHub release of `SELF_UPDATE_REPO` and compares it with the file it is
  running from. When they differ it downloads `chromebrew-scripts`, verifies
  it against that checksum, checks that it parses and is a single-file build,
  and renames it over the old file (as the file's owner, through `sudo` for a
  root-owned `/usr/local/bin`). It follows releases, so `--branch` does not
  apply, and **nothing is replaced without a published checksum**: a release
  without `chromebrew-scripts.sha256`, or a fork that has no releases, is
  refused with `refusing an unverified update`.

`--self-update --dry-run` fetches and compares but changes nothing:

```
$ chromebrew-scripts --self-update --dry-run
▶ self-update
  · source: https://github.com/uberhacker/chromebrew-scripts/releases/latest/download/chromebrew-scripts
  · installed: chromebrew-scripts 2.1.0 (git 1a2b3c4, single file)
  ◦ would replace /usr/local/bin/chromebrew-scripts: 2.1.0 (git 1a2b3c4) -> 2.2.0 (git 5d6e7f8)
```

`cbs-check` runs the same comparison without changing anything (`Toolkit
update: update available: run --self-update`).

To follow a fork instead, for every install method:

```
$ chromebrew-scripts --self-update --source https://github.com/<fork>/chromebrew-scripts
```

or put `SELF_UPDATE_REPO=https://github.com/<fork>/chromebrew-scripts` in the
config file (`config.example` has an example; a single file can only follow a fork that
publishes releases with a checksum). `install.sh --update` from a checkout or
tree does the tarball download and reinstall with the same settings
(`SELF_UPDATE_REPO`, `SELF_UPDATE_BRANCH`, or the 2.0.0 `CBS_REPO=owner/name`
and `CBS_REF`).

## Running it from a script

Nothing here prompts when you tell it not to: `--yes` answers the
confirmation, every command this toolkit runs has stdin closed and a time
limit, `yes |` feeds the installer and `crew upgrade`, and output without a
terminal has no colours. So a script can do

```
chromebrew --backup "$HOME/MyFiles/Downloads/packages.txt" || exit 1   # then copy the file away
powerwash --yes --no-reboot                                            # and reboot when ready
```

or, on a freshly reset device,

```
chromebrew --install --yes --quiet && source ~/.bashrc && chromebrew --restore /path/to/packages.txt --yes
```

Rules worth knowing:

* **Without `--yes` and without a terminal every destructive command refuses**
  (`refusing to continue: stdin is not a terminal and --yes was not given`),
  exit status 1. That is deliberate: a cron job or a pipe cannot powerwash a
  device by accident.
* **The exit status is the result**: 0 when every step succeeded or was
  skipped, 1 when a step failed or the confirmation was refused, 2 for a
  usage error. A failed step stops the command, so a `rw` whose first
  `mount` failed has not touched the other two.
* **Steps that are already done are skipped**, so `rw --yes` at every login
  is harmless when nothing changed, and `chromebrew --restore` of a list that
  is already installed does nothing.
* **`--quiet`** keeps only this program's lines and the summary; the hidden
  output is in the [log](#logs), whose path is the last line of the summary.
  `--no-color` is implied when stdout is not a terminal.
* **`sudo` is still `sudo`.** In the ChromeOS developer shell `sudo` works
  without a password unless you have set one with `chromeos-setdevpasswd`;
  a script that runs where `sudo` asks for a password will stop there.
* **Not from Crostini.** The Linux container is not ChromeOS: the commands
  refuse there (`not ChromeOS`), and `chromebrew --install` tells you why
  (`this is a Crostini container`). Run them from crosh's `shell`.
* **ChromeOS gives you no cron or systemd timers** (Chromebrew may). These
  are commands to run from the shell or from your own scripts, not a
  background service; `chromebrew --update` now and then by hand is the
  usual pattern.

## Troubleshooting

| You see | What it means | What to do |
| --- | --- | --- |
| `not ChromeOS (...)` | `/etc/lsb-release` has no `CHROMEOS_RELEASE_NAME`: a Linux machine, or the Crostini container | run it in crosh's `shell` on the device; `CBS_ASSUME_CHROMEOS=1` is for tests only |
| `refusing to continue: stdin is not a terminal and --yes was not given` | the command was run from a script or a pipe | add `--yes` if that is what you mean |
| `aborted; nothing was changed` | you answered anything but `y` | nothing happened |
| `mount -o remount,rw / failed (exit code 32)` | rootfs verification is on | `cbs-check` confirms it; run `rootfs` (with `-- --partitions N` on newer releases) and reboot, then `rw` |
| `make_dev_ssd.sh failed` and it asks for `--partitions` | newer ChromeOS wants the kernel partition | `rootfs -- --partitions 2` (or `4`); see [docs/rootfs.md](docs/rootfs.md#--partitions) |
| `Chromebrew must not be installed as root` | you are in a root shell | run `chromebrew --install` as the normal shell user |
| `the dev channel is not supported by the Chromebrew installer (stable and ltc are)` | the device is on beta, dev or canary | switch channels, or `--force` and expect the installer to object |
| `this is a Crostini container (...)` | the Linux terminal, not the ChromeOS shell | crosh (Ctrl+Alt+T), `shell` |
| `only 512.0 MiB free on /mnt/stateful_partition (MIN_FREE_MB=1024)` | little free space | free some, or `MIN_FREE_MB=256` / `--force` |
| `chromebrew is currently installed (...); use --update, or --remove first` | `crew` exists | `--update`, or `--remove` for a clean reinstall |
| `chromebrew is not installed` | no `crew` for `--update`, `--backup` or `--restore` | `chromebrew --install` first |
| `crew upgrade failed (timed out after 3600s)` | a long build or download | the log shows where it was; `CREW_TIMEOUT=7200` |
| `Permission denied` when running `~/.local/bin/rw` | the home directory is mounted `noexec` on ChromeOS | install into `/usr/local` (`./install.sh`), or `bash ~/.local/bin/rw` |
| `command not found` after `install.sh` | `/usr/local/bin` (or `~/.local/bin`) is not on `PATH` in this shell | open a new shell, or add the directory to `PATH`; the ChromeOS developer shell normally has `/usr/local/bin` on it |
| `no chromebrew-scripts.sha256 is published with the latest release; refusing an unverified update` | the repository (or the fork in `SELF_UPDATE_REPO`) has no release with a checksum | wait for a release, or install the tree layout / a git checkout, which follow a branch |
| `checkout origin (...) does not match the configured source (...)` | `SELF_UPDATE_REPO` and the checkout's `origin` differ | `--self-update --source URL` re-points `origin`, or fix the config |
| `refusing to update: ... has local changes` | the checkout has uncommitted changes | commit or stash them |
| `would switch from my-branch to master at ...` | the checkout is on a branch the remote does not have | that is what a real run would do; `--branch my-branch` or `SELF_UPDATE_BRANCH` if the remote has it |
| `cannot create log directory ...; this run is not logged` | `LOG_DIR` or `~/.local/state` is not writable | set `LOG_DIR`, or `--no-log` |
| `unknown key 'X' (FILE:N) ignored` / `invalid value for KEY (FILE:N) ignored` | a typo or a value of the wrong kind in a config file | see [`config.example`](config.example); `cbs-check` shows what is in effect |
| `Developer mode: unknown (crossystem devsw_boot)` in `cbs-check` | `crossystem` is missing or failed (ChromeOS Flex, a container) | nothing; the rest of the report is unaffected |

Every run's [log](#logs) has the full output and exit status of each
command, which is usually enough to see why a step did what it did; the
summary ends with its path and `latest.log` points at the newest. `-v`
(`--verbose`) shows the commands on the terminal as they run. Each command's
page in [`docs/`](docs/README.md) lists its failure reasons and what has not
been verified on a real device.

## Development

```
$ tests/lint.sh            # bash -n on every script, shellcheck -x on the sources, a shellchecked single-file build
$ tests/run.sh             # the bats suite, against bin/ and against a fresh single-file build (bats-core is fetched into tests/vendor if missing)
$ tests/run.sh --filter self-update        # a subset (arguments go to bats)
$ CBS_TEST_TARGET=bundle tests/run.sh      # one build only
$ tests/install-smoke.sh   # install.sh end to end into a temporary prefix: layouts, symlinks, completion, dry runs, --self-update --dry-run, uninstall
$ ./build.sh               # the single-file build, dist/chromebrew-scripts
$ make check               # lint + tests; make smoke runs the install smoke test
```

The tests never touch the real system: every path goes through `CBS_ROOT`
into a temporary sandbox, `CBS_ASSUME_CHROMEOS=1` is set, and `sudo`, `crew`,
`curl`, `mount`, `reboot`, `crossystem` and `make_dev_ssd.sh` are stubs on
`PATH` that log their calls. The 102 tests run twice, against the modular
`bin/` and against a single-file build, and cover the commands (confirmation,
dry run, every option, the failure paths), `chromebrew` (pre-flight checks,
install as a non-root user, remove, update, backup and restore),
`install.sh` (both layouts, switching, the 2.0.0 layout, foreign files,
`--update`, `--uninstall`), the configuration (precedence, hostile values,
the 2.0.0 names), the argument parser, colours and icons, the run log
(header, output, exit status, permissions, pruning, `--quiet`, `--no-log`),
self-update in all three modes against local repositories and fake releases
(including the refusals), the single-file build itself, the bash completion
against `--help`, and `cbs-check` against fixtures. They pass as root and as
an unprivileged user.

**Real ChromeOS cannot be tested in CI.** Nothing there runs
`make_dev_ssd.sh`, writes the powerwash marker, remounts a filesystem or
runs the Chromebrew installer for real; the per-command pages say what is
documented behaviour rather than tested behaviour. Test on a device you can
afford to powerwash.

CI (`.github/workflows/ci.yml`) runs the lint, the unit tests against both
builds with [bats-core](https://github.com/bats-core/bats-core) pinned to a
release commit, builds the single file and uploads it as an artifact, and
runs `tests/install-smoke.sh` inside `debian:stable-slim` and `alpine:3`
containers.

Releases: bump `VERSION`, commit, then tag and push the tag (`git tag v2.1.0
&& git push origin v2.1.0`). `.github/workflows/release.yml` runs the lint
and the tests, checks that the tag matches `VERSION`, builds the single
file and publishes it with its `.sha256` as a GitHub release, which is where
`--self-update` of a single file and `cbs-check` look.

Layout:

```
bin/chromebrew-scripts       the entry point: finds lib/, dispatches on its name or first argument
bin/{chromebrew,powerwash,rootfs,rw,cbs-check}   symlinks to it
lib/core/                    log, util (runners, confirm, download), config, args, chromeos (probes),
                             crew, runner (steps and summary), runlog, selfupdate
lib/cmd/<command>.sh         one module per command: cmd_<name>_usage/_options/_parse/_run
completions/                 bash completion
docs/                        one page per command
build.sh                     the single-file build; install.sh; config.example
tests/                       run.sh, lint.sh, install-smoke.sh, test_helper.bash, stubs/, unit/*.bats
```

Adding a command is one module in `lib/cmd/`, one symlink, one page in
`docs/` and one test file; [CONTRIBUTING.md](CONTRIBUTING.md) walks through
it and the rules every module follows.

## Changes from the original

Ed Reel's `chromebrew-scripts` were four short scripts (`chromebrew`,
`powerwash`, `rootfs`, `rw`); this version keeps the commands, their names
and what they do, and restructures them so they can be trusted on a device
you care about. Every command and flag from the original still works.

In 2.0.0 (the modular rewrite):

* `chromebrew -i` downloads from `raw.githubusercontent.com/chromebrew/chromebrew`
  (the `git.io/vddgY` short link is dead), into a temporary directory with
  `curl --fail` and a timeout, and refuses to run as root (the installer does too).
* `chromebrew -r` no longer runs `sudo dev_install --reinstall` (gone from
  modern ChromeOS); it follows the Chromebrew wiki's removal method, backs up
  `~/.bashrc`, and keeps this toolkit while clearing `/usr/local`.
* `chromebrew -u` wraps both crew commands in `timeout`.
* `powerwash` only reboots if the clobber marker was written; `rootfs` only
  reboots if `make_dev_ssd.sh` succeeded. Both have `--no-reboot`.
* `rw` exits non-zero when a remount fails (it used to print a message and
  exit 0).
* `--dry-run`, `--yes`, a `[y/N]` confirmation that accepts only `y`, a
  refusal to run on anything that is not ChromeOS, `install.sh`, tests, CI.

In 2.1.0 (this version):

* One entry point with the command names as symlinks, and a single-file
  build with `--self-update` that verifies a published checksum.
* A log of every run; `--verbose`, `--quiet`, `--color`, `--timeout`.
* A configuration file, with the 2.0.0 environment names still accepted.
* `cbs-check`: a read-only report of the device and the toolkit.
* `chromebrew --backup` and `--restore`; `rw --undo`; pre-flight checks and
  `--force` for `chromebrew --install`; `rootfs` notes when verification
  already looks removed.
* Tab completion, `install.sh --user` and `--tree`, a test suite that runs
  against both builds, a release workflow.

Thanks to Ed Reel ([@uberhacker](https://github.com/uberhacker)) for the
original scripts and the research behind them.

## References

Chromebrew:

* [chromebrew/chromebrew](https://github.com/chromebrew/chromebrew) (formerly
  `skycocker/chromebrew`): the README has the one-line installer, the
  supported architectures (x86_64, armv7l, aarch64 using the armv7l packages,
  i686 with limited support), and the notes that the installer does not
  support the beta, dev and canary channels and, from ChromeOS M117 on, does
  not run inside crosh.
* The [Chromebrew wiki](https://github.com/chromebrew/chromebrew/wiki) and its
  [FAQ](https://github.com/chromebrew/chromebrew/wiki/FAQ) (`yes | crew
  upgrade` for a non-interactive upgrade, which `chromebrew --update` uses).
* [How to remove chromebrew](https://github.com/chromebrew/chromebrew/wiki/How-to-remove-chromebrew):
  the method `chromebrew --remove` follows.
* [install.sh](https://raw.githubusercontent.com/chromebrew/chromebrew/master/install.sh):
  the installer `chromebrew --install` downloads and runs.

ChromeOS:

* [Developer mode](https://www.chromium.org/chromium-os/developer-library/guides/device/developer-mode/)
  (Chromium OS developer library): `sudo /usr/share/vboot/bin/make_dev_ssd.sh
  --remove_rootfs_verification`, the note that it may ask to be rerun with
  `--partitions`, and the warning that a writable root filesystem no longer
  passes verification even if nothing is changed. This is what `rootfs` and
  `rw` rest on.
* [/etc/lsb-release format](https://www.chromium.org/chromium-os/developer-library/reference/infrastructure/lsb-release/):
  `CHROMEOS_RELEASE_TRACK` is where the channel comes from, and
  `CHROMEOS_RELEASE_BOARD` is not to be relied on, which is why `cbs-check`
  labels the board informational.
* [Reset your Chromebook to factory settings](https://support.google.com/chromebook/answer/183084?hl=en)
  (Google Chromebook Help): what a powerwash is and how to do it from the
  settings.
* [Powerwash via the cmd line](https://neverware.zendesk.com/hc/en-us/articles/115000765287--Powerwash-via-the-cmd-line)
  (Neverware, historical): the CloudReady article that documented writing
  `clobber` to `/mnt/stateful_partition/.update_available`, which is what
  `powerwash` does. CloudReady is now
  [ChromeOS Flex](https://chromeenterprise.google/intl/en_gb/os/chromeosflex/)
  ([help centre](https://support.google.com/chromeosflex/answer/11542901?hl=en)),
  where `crossystem` and the Chromebook firmware do not exist as such;
  `cbs-check` reports those rows as `unknown` there.

The original:

* [uberhacker/chromebrew-scripts](https://github.com/uberhacker/chromebrew-scripts)
  by Ed Reel: the scripts this is a rewrite of.

## License

LGPL-3.0, as the original. See [LICENSE](LICENSE).
