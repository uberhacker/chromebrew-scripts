# bash completion for chromebrew-scripts and its commands    -*- shell-script -*-
#
# Installed by install.sh into bash-completion's completions directory, or
# load it by hand:  source completions/chromebrew-scripts.bash
# A single-file build prints it:  source <(chromebrew-scripts --completion bash)
# zsh can use it too:  autoload -U bashcompinit && bashcompinit && source ...
#
# Completes `chromebrew-scripts COMMAND ...` and the command names themselves
# (chromebrew, powerwash, rootfs, rw, cbs-check). The option lists are kept
# in step with each command's --help by tests/unit/completion.bats.

# COMPREPLY=($(compgen ...)) is the standard idiom; words never contain spaces.
# shellcheck disable=SC2207

_cbs_commands="chromebrew powerwash rootfs rw check"
_cbs_common_opts="--dry-run --yes --verbose --quiet --no-color --color --timeout
  --config --log --no-log --self-update --source --branch --version --help"

# _cbs_cmd_opts COMMAND: the command's own options.
_cbs_cmd_opts() {
  case "$1" in
    chromebrew) printf '%s\n' "--install --remove --update --status --backup --restore --force" ;;
    powerwash) printf '%s\n' "--no-reboot" ;;
    rootfs) printf '%s\n' "--no-reboot --" ;;
    rw) printf '%s\n' "--undo --ro" ;;
    check|cbs-check) printf '%s\n' "--offline" ;;
  esac
}

_chromebrew_scripts() {
  local cur prev cmd="" i pfx="" name
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  # The command: the program's own name when it is a command symlink, else
  # the first word that names a command.
  name="${COMP_WORDS[0]##*/}"
  case "$name" in
    chromebrew|powerwash|rootfs|rw) cmd="$name" ;;
    cbs-check) cmd=check ;;
  esac
  if [ -z "$cmd" ]; then
    for ((i = 1; i < COMP_CWORD; i++)); do
      case " $_cbs_commands " in
        *" ${COMP_WORDS[i]} "*) cmd="${COMP_WORDS[i]}"; break ;;
      esac
    done
  fi

  # --opt=value: bash splits it into "--opt" "=" "value" (= is in
  # COMP_WORDBREAKS); without that, it arrives as one word.
  if [ "$cur" = "=" ]; then
    cur=""
  elif [ "$prev" = "=" ] && [ "$COMP_CWORD" -ge 2 ]; then
    prev="${COMP_WORDS[COMP_CWORD-2]}"
  elif [[ "$cur" == --*=* ]]; then
    prev="${cur%%=*}"
    pfx="$prev="
    cur="${cur#*=}"
  fi

  case "$prev" in
    --color|--colour)
      COMPREPLY=($(compgen -P "$pfx" -W "auto always never" -- "$cur"))
      return 0 ;;
    --completion)
      COMPREPLY=($(compgen -P "$pfx" -W "bash zsh" -- "$cur"))
      return 0 ;;
    --config|--log|--restore|--backup)
      compopt -o filenames 2>/dev/null || true
      COMPREPLY=($(compgen -f -- "$cur"))
      return 0 ;;
    --timeout|--source|--branch)
      return 0 ;;   # free-form values
  esac

  if [ -z "$cmd" ]; then
    COMPREPLY=($(compgen -W "$_cbs_commands $_cbs_common_opts --completion" -- "$cur"))
  else
    COMPREPLY=($(compgen -W "$(_cbs_cmd_opts "$cmd") $_cbs_common_opts" -- "$cur"))
  fi
}

complete -F _chromebrew_scripts chromebrew-scripts chromebrew powerwash rootfs rw cbs-check
