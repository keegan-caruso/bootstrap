#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TEST_ROOT="$(mktemp -d)"
export HOME="${TEST_ROOT}/selection-home"
mkdir -p "$HOME"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

# shellcheck source=bootstrap-nix.sh
# shellcheck disable=SC1091
source "${REPO_DIR}/bootstrap-nix.sh"
unset BOOTSTRAP_SHELL_PROFILE

fail_test() {
  printf 'Shell profile test failed: %s\n' "$*" >&2
  exit 1
}

test_profile_selection() {
  local profile_file="${HOME}/.config/codex-dev-shell/shell-profile"
  local error_log="${TEST_ROOT}/selection-error"
  local selection_log="${TEST_ROOT}/selection-output"

  configure_shell_profile <<<"" >"$selection_log"
  [[ "$(<"$profile_file")" == starship ]] \
    || fail_test "The first-run default must remain starship"
  grep -Fq "Both profiles enable zoxide navigation and directory tracking." "$selection_log" \
    || fail_test "Profile selection did not describe shared zoxide integration"

  rm "$profile_file"
  configure_shell_profile <<<'invalid
minimal' >/dev/null
  [[ "$(<"$profile_file")" == minimal ]] \
    || fail_test "Interactive selection did not accept minimal after invalid input"

  configure_shell_profile </dev/null >/dev/null
  [[ "$(<"$profile_file")" == minimal ]] \
    || fail_test "The saved selection was not reused without prompting"

  BOOTSTRAP_SHELL_PROFILE=starship configure_shell_profile </dev/null >/dev/null
  [[ "$(<"$profile_file")" == starship ]] \
    || fail_test "The environment override did not replace the saved selection"

  if (BOOTSTRAP_SHELL_PROFILE=invalid configure_shell_profile) >"$error_log" 2>&1; then
    fail_test "An invalid environment override was accepted"
  fi
  grep -Fq "Invalid shell profile" "$error_log" \
    || fail_test "Invalid selection did not produce an explicit error"
  [[ "$(<"$profile_file")" == starship ]] \
    || fail_test "An invalid override changed the saved selection"

  printf 'invalid\n' >"$profile_file"
  if (configure_shell_profile </dev/null) >"$error_log" 2>&1; then
    fail_test "An invalid saved selection was accepted"
  fi
  BOOTSTRAP_SHELL_PROFILE=minimal configure_shell_profile </dev/null >/dev/null
  [[ "$(<"$profile_file")" == minimal ]] \
    || fail_test "A valid override could not repair an invalid saved selection"

  rm "$profile_file"
  if (configure_shell_profile </dev/null) >"$error_log" 2>&1; then
    fail_test "Missing first-run input was silently accepted"
  fi
  [[ ! -e "$profile_file" ]] \
    || fail_test "Failed selection wrote a profile"
}

prepare_runtime_fixture() {
  local fixture="${TEST_ROOT}/runtime"
  mkdir -p "$fixture/bin" "$fixture/home/.config/codex-dev-shell" \
    "$fixture/home/repos" "$fixture/start"

  cat >"$fixture/bin/starship" <<'SH'
#!/bin/sh
printf 'starship %s\n' "$*" >>"$PROFILE_COMMAND_LOG"
cat <<'ZSH'
autoload -Uz add-zsh-hook
prompt_starship_precmd() { :; }
prompt_starship_preexec() { :; }
add-zsh-hook precmd prompt_starship_precmd
add-zsh-hook preexec prompt_starship_preexec
PROMPT='test-starship'
RPROMPT='test-right'
ZSH
SH

  cat >"$fixture/bin/zoxide" <<'SH'
#!/bin/sh
printf 'zoxide %s\n' "$*" >>"$PROFILE_COMMAND_LOG"
cat <<'ZSH'
autoload -Uz add-zsh-hook
__zoxide_hook() { print -r -- zoxide-add >>"$PROFILE_COMMAND_LOG"; }
__zoxide_z_complete() { :; }
__zoxide_z_complete_helper() { :; }
z() { :; }
zi() { :; }
add-zsh-hook chpwd __zoxide_hook
typeset -gA _comps
_comps[z]=__zoxide_z_complete
compdef() { unset "_comps[$2]"; }
zle -N __zoxide_z_complete_helper
ZSH
SH

  cat >"$fixture/bin/git" <<'SH'
#!/bin/sh
printf 'git %s\n' "$*" >>"$PROFILE_COMMAND_LOG"
exit 99
SH
  printf '#!/bin/sh\nexit 0\n' >"$fixture/bin/fnm"
  cp "$fixture/bin/fnm" "$fixture/bin/gh"
  chmod +x "$fixture/bin/"*

  cat \
    "$REPO_DIR/nix/templates/zsh/path.sh" \
    "$REPO_DIR/nix/templates/zsh/interactive.sh" \
    "$REPO_DIR/nix/templates/zsh/prompt.sh" \
    "$REPO_DIR/nix/templates/zsh/shell-tools.sh" \
    "$REPO_DIR/nix/templates/zsh/syntax-highlighting.sh" \
    >"$fixture/home/.config/codex-dev-shell/zshrc"
}

test_runtime_profiles() {
  local fixture="${TEST_ROOT}/runtime"
  local zsh_command
  zsh_command="$(command -v zsh)"

  # shellcheck disable=SC2016
  HOME="$fixture/home" \
  XDG_STATE_HOME="$fixture/state" \
  XDG_CACHE_HOME="$fixture/cache" \
  PATH="$fixture/bin:/usr/bin:/bin" \
  PROFILE_COMMAND_LOG="$fixture/commands" \
  ZSH_NONINTERACTIVE_SAFE=1 \
    "$zsh_command" -dfi -c '
      check() { "$@" || { print -u2 -- "${funcfiletrace[1]}: runtime assertion failed: $*"; exit 1; }; }
      check_zoxide() {
        local -a hooks
        check test "${+functions[z]}" = 1
        check test "${+functions[zi]}" = 1
        check test "${+functions[__zoxide_hook]}" = 1
        check test "${+widgets[__zoxide_z_complete_helper]}" = 1
        check test "${+_comps[z]}" = 1
        hooks=("${(@M)chpwd_functions:#__zoxide_hook}")
        check test "${#hooks}" = 1
      }
      config="$HOME/.config/codex-dev-shell/zshrc"
      profile_file="$HOME/.config/codex-dev-shell/shell-profile"
      cd -- "$1/start"
      print -r -- minimal >"$profile_file"
      : >"$PROFILE_COMMAND_LOG"
      source "$config" || exit 1
      check test "$PROMPT" = "%~ %# "
      check test -z "$RPROMPT"
      check test "$PROMPT2" = "%_> "
      check test "$PWD" = "$HOME/repos"
      check_zoxide
      check grep -Fxq "zoxide init zsh" "$PROFILE_COMMAND_LOG"
      check grep -Fxq zoxide-add "$PROFILE_COMMAND_LOG"
      check test "$(grep -Ec "^(starship|git) " "$PROFILE_COMMAND_LOG")" = 0
      check test "$FZF_CTRL_T_COMMAND" = "$FZF_DEFAULT_COMMAND"
      check test "${+functions[_fnm_lazy_load]}" = 1
      : >"$PROFILE_COMMAND_LOG"
      cd -- "$1/start"
      cd -- "$HOME/repos"
      check test "$(grep -Fxc zoxide-add "$PROFILE_COMMAND_LOG")" = 2
      check test "$(grep -Ec "^(starship|git) " "$PROFILE_COMMAND_LOG")" = 0

      rmdir "$HOME/repos"
      cd -- "$1/start"
      source "$config" || exit 1
      check test "$PWD" = "$1/start"
      check_zoxide
      mkdir "$HOME/repos"

      rm "$profile_file"
      : >"$PROFILE_COMMAND_LOG"
      source "$config" || exit 1
      check test "$PROMPT" = test-starship
      check_zoxide
      check test "$PWD" = "$1/start"
      check grep -Fxq "starship init zsh" "$PROFILE_COMMAND_LOG"
      check grep -Fxq "zoxide init zsh" "$PROFILE_COMMAND_LOG"
      cd -- "$HOME/repos"
      check grep -Fxq zoxide-add "$PROFILE_COMMAND_LOG"

      print -r -- minimal >"$profile_file"
      : >"$PROFILE_COMMAND_LOG"
      autoload -Uz vcs_info
      add-zsh-hook precmd vcs_info
      source "$config" || exit 1
      check test "$PROMPT" = "%~ %# "
      check test "$PWD" = "$HOME/repos"
      check_zoxide
      check grep -Fxq "zoxide init zsh" "$PROFILE_COMMAND_LOG"
      check test "$(grep -Ec "^(starship|git) " "$PROFILE_COMMAND_LOG")" = 0
      [[ " ${precmd_functions[*]} ${preexec_functions[*]} ${chpwd_functions[*]} " != *starship* &&
         " ${precmd_functions[*]} ${chpwd_functions[*]} " != *vcs_info* ]] || exit 1

      print -r -- starship >"$profile_file"
      source "$config" || exit 1
      check test "$PROMPT" = test-starship
      check_zoxide
      source "$config" || exit 1
      check_zoxide
      : >"$PROFILE_COMMAND_LOG"
      cd -- "$1/start"
      cd -- "$HOME/repos"
      check test "$(grep -Fxc zoxide-add "$PROFILE_COMMAND_LOG")" = 2

      print -r -- invalid >"$profile_file"
      : >"$PROFILE_COMMAND_LOG"
      if source "$config" 2>"$1/runtime-error"; then
        print -u2 -- "Invalid runtime profile was accepted"
        exit 1
      fi
      check grep -Fq "invalid shell profile" "$1/runtime-error"
      check test ! -s "$PROFILE_COMMAND_LOG"
    ' profile-runtime "$fixture"
}

test_profile_selection
prepare_runtime_fixture
test_runtime_profiles
printf 'Shell profile checks passed\n'
