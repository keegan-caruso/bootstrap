#!/usr/bin/env bash
set -euo pipefail

SCRIPT_MARKER="codex-zellij"

log() {
  printf '[zellij-setup] %s\n' "$*"
}

fail() {
  printf '[zellij-setup] %s\n' "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

get_copy_command() {
  if command_exists clip.exe; then
    printf '%s\n' "clip.exe"
  elif command_exists pbcopy; then
    printf '%s\n' "pbcopy"
  elif command_exists wl-copy; then
    printf '%s\n' "wl-copy"
  elif command_exists xclip; then
    printf '%s\n' "xclip -selection clipboard"
  elif command_exists xsel; then
    printf '%s\n' "xsel --clipboard --input"
  else
    printf '%s\n' ""
  fi
}

ensure_file() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  touch "$file"
}

upsert_block() {
  local file="$1"
  local name="$2"
  local content="$3"
  local start="# >>> ${SCRIPT_MARKER}:${name}"
  local end="# <<< ${SCRIPT_MARKER}:${name}"
  local tmp

  ensure_file "$file"
  tmp="$(mktemp)"

  awk -v start="$start" -v end="$end" -v block="$content" '
    BEGIN {
      in_block = 0
      replaced = 0
    }
    $0 == start {
      print start
      print block
      print end
      in_block = 1
      replaced = 1
      next
    }
    $0 == end {
      in_block = 0
      next
    }
    !in_block {
      print
    }
    END {
      if (!replaced) {
        if (NR > 0) {
          print ""
        }
        print start
        print block
        print end
      }
    }
  ' "$file" >"$tmp"

  mv "$tmp" "$file"
}

require_zellij() {
  if ! command_exists zellij; then
    fail "zellij is not installed or not on PATH."
  fi
}

write_zellij_config() {
  local config_file="${HOME}/.config/zellij/config.kdl"
  local copy_command
  local copy_command_line

  mkdir -p "$(dirname "$config_file")"

  copy_command="$(get_copy_command)"
  if [[ -n "$copy_command" ]]; then
    copy_command_line="copy_command \"$copy_command\""
  else
    copy_command_line="// copy_command omitted: no supported clipboard helper found"
    log "No clipboard helper found for zellij; leaving copy_command unset."
  fi

  cat >"$config_file" <<EOF
//
// Managed by configure-zellij.sh
//

keybinds clear-defaults=true {
    locked {
        bind "Ctrl g" { SwitchToMode "normal"; }
    }
    pane {
        bind "left" { MoveFocus "left"; }
        bind "down" { MoveFocus "down"; }
        bind "up" { MoveFocus "up"; }
        bind "right" { MoveFocus "right"; }
        bind "c" { SwitchToMode "renamepane"; PaneNameInput 0; }
        bind "d" { NewPane "down"; SwitchToMode "normal"; }
        bind "e" { TogglePaneEmbedOrFloating; SwitchToMode "normal"; }
        bind "f" { ToggleFocusFullscreen; SwitchToMode "normal"; }
        bind "h" { MoveFocus "left"; }
        bind "i" { TogglePanePinned; SwitchToMode "normal"; }
        bind "j" { MoveFocus "down"; }
        bind "k" { MoveFocus "up"; }
        bind "l" { MoveFocus "right"; }
        bind "n" { NewPane; SwitchToMode "normal"; }
        bind "p" { SwitchFocus; }
        bind "Ctrl p" { SwitchToMode "normal"; }
        bind "r" { NewPane "right"; SwitchToMode "normal"; }
        bind "s" { NewPane "stacked"; SwitchToMode "normal"; }
        bind "w" { ToggleFloatingPanes; SwitchToMode "normal"; }
        bind "z" { TogglePaneFrames; SwitchToMode "normal"; }
    }
    tab {
        bind "left" { GoToPreviousTab; }
        bind "down" { GoToNextTab; }
        bind "up" { GoToPreviousTab; }
        bind "right" { GoToNextTab; }
        bind "1" { GoToTab 1; SwitchToMode "normal"; }
        bind "2" { GoToTab 2; SwitchToMode "normal"; }
        bind "3" { GoToTab 3; SwitchToMode "normal"; }
        bind "4" { GoToTab 4; SwitchToMode "normal"; }
        bind "5" { GoToTab 5; SwitchToMode "normal"; }
        bind "6" { GoToTab 6; SwitchToMode "normal"; }
        bind "7" { GoToTab 7; SwitchToMode "normal"; }
        bind "8" { GoToTab 8; SwitchToMode "normal"; }
        bind "9" { GoToTab 9; SwitchToMode "normal"; }
        bind "[" { BreakPaneLeft; SwitchToMode "normal"; }
        bind "]" { BreakPaneRight; SwitchToMode "normal"; }
        bind "b" { BreakPane; SwitchToMode "normal"; }
        bind "h" { GoToPreviousTab; }
        bind "j" { GoToNextTab; }
        bind "k" { GoToPreviousTab; }
        bind "l" { GoToNextTab; }
        bind "n" { NewTab; SwitchToMode "normal"; }
        bind "r" { SwitchToMode "renametab"; TabNameInput 0; }
        bind "s" { ToggleActiveSyncTab; SwitchToMode "normal"; }
        bind "Ctrl t" { SwitchToMode "normal"; }
        bind "x" { CloseTab; SwitchToMode "normal"; }
        bind "tab" { ToggleTab; }
    }
    resize {
        bind "left" { Resize "Increase left"; }
        bind "down" { Resize "Increase down"; }
        bind "up" { Resize "Increase up"; }
        bind "right" { Resize "Increase right"; }
        bind "+" { Resize "Increase"; }
        bind "-" { Resize "Decrease"; }
        bind "=" { Resize "Increase"; }
        bind "H" { Resize "Decrease left"; }
        bind "J" { Resize "Decrease down"; }
        bind "K" { Resize "Decrease up"; }
        bind "L" { Resize "Decrease right"; }
        bind "h" { Resize "Increase left"; }
        bind "j" { Resize "Increase down"; }
        bind "k" { Resize "Increase up"; }
        bind "l" { Resize "Increase right"; }
        bind "Ctrl n" { SwitchToMode "normal"; }
    }
    move {
        bind "left" { MovePane "left"; }
        bind "down" { MovePane "down"; }
        bind "up" { MovePane "up"; }
        bind "right" { MovePane "right"; }
        bind "h" { MovePane "left"; }
        bind "Ctrl h" { SwitchToMode "normal"; }
        bind "j" { MovePane "down"; }
        bind "k" { MovePane "up"; }
        bind "l" { MovePane "right"; }
        bind "n" { MovePane; }
        bind "p" { MovePaneBackwards; }
        bind "tab" { MovePane; }
    }
    scroll {
        bind "Alt left" { MoveFocusOrTab "left"; SwitchToMode "normal"; }
        bind "Alt down" { MoveFocus "down"; SwitchToMode "normal"; }
        bind "Alt up" { MoveFocus "up"; SwitchToMode "normal"; }
        bind "Alt right" { MoveFocusOrTab "right"; SwitchToMode "normal"; }
        bind "e" { EditScrollback; SwitchToMode "normal"; }
        bind "Alt h" { MoveFocusOrTab "left"; SwitchToMode "normal"; }
        bind "Alt j" { MoveFocus "down"; SwitchToMode "normal"; }
        bind "Alt k" { MoveFocus "up"; SwitchToMode "normal"; }
        bind "Alt l" { MoveFocusOrTab "right"; SwitchToMode "normal"; }
        bind "s" { SwitchToMode "entersearch"; SearchInput 0; }
    }
    search {
        bind "c" { SearchToggleOption "CaseSensitivity"; }
        bind "n" { Search "down"; }
        bind "o" { SearchToggleOption "WholeWord"; }
        bind "p" { Search "up"; }
        bind "w" { SearchToggleOption "Wrap"; }
    }
    session {
        bind "a" {
            LaunchOrFocusPlugin "zellij:about" {
                floating true
                move_to_focused_tab true
            }
            SwitchToMode "normal"
        }
        bind "c" {
            LaunchOrFocusPlugin "configuration" {
                floating true
                move_to_focused_tab true
            }
            SwitchToMode "normal"
        }
        bind "l" {
            LaunchOrFocusPlugin "zellij:layout-manager" {
                floating true
                move_to_focused_tab true
            }
            SwitchToMode "normal"
        }
        bind "Ctrl o" { SwitchToMode "normal"; }
        bind "p" {
            LaunchOrFocusPlugin "plugin-manager" {
                floating true
                move_to_focused_tab true
            }
            SwitchToMode "normal"
        }
        bind "s" {
            LaunchOrFocusPlugin "zellij:share" {
                floating true
                move_to_focused_tab true
            }
            SwitchToMode "normal"
        }
        bind "w" {
            LaunchOrFocusPlugin "session-manager" {
                floating true
                move_to_focused_tab true
            }
            SwitchToMode "normal"
        }
    }
    shared_except "locked" {
        bind "Alt +" { Resize "Increase"; }
        bind "Alt -" { Resize "Decrease"; }
        bind "Alt =" { Resize "Increase"; }
        bind "Alt [" { PreviousSwapLayout; }
        bind "Alt ]" { NextSwapLayout; }
        bind "Alt f" { ToggleFloatingPanes; }
        bind "Ctrl g" { SwitchToMode "locked"; }
        bind "Alt i" { MoveTab "left"; }
        bind "Alt n" { NewPane; }
        bind "Alt o" { MoveTab "right"; }
        bind "Alt p" { TogglePaneInGroup; }
        bind "Alt Shift p" { ToggleGroupMarking; }
        bind "Ctrl q" { Quit; }
    }
    shared_except "locked" "move" {
        bind "Ctrl h" { SwitchToMode "move"; }
    }
    shared_except "locked" "session" {
        bind "Ctrl o" { SwitchToMode "session"; }
    }
    shared_except "locked" "scroll" {
        bind "Alt left" { MoveFocusOrTab "left"; }
        bind "Alt down" { MoveFocus "down"; }
        bind "Alt up" { MoveFocus "up"; }
        bind "Alt right" { MoveFocusOrTab "right"; }
        bind "Alt h" { MoveFocusOrTab "left"; }
        bind "Alt j" { MoveFocus "down"; }
        bind "Alt k" { MoveFocus "up"; }
        bind "Alt l" { MoveFocusOrTab "right"; }
    }
    shared_except "locked" "scroll" "search" "tmux" {
        bind "Ctrl b" { SwitchToMode "tmux"; }
    }
    shared_except "locked" "scroll" "search" {
        bind "Ctrl s" { SwitchToMode "scroll"; }
    }
    shared_except "locked" "tab" {
        bind "Ctrl t" { SwitchToMode "tab"; }
    }
    shared_except "locked" "pane" {
        bind "Ctrl p" { SwitchToMode "pane"; }
    }
    shared_except "locked" "resize" {
        bind "Ctrl n" { SwitchToMode "resize"; }
    }
    shared_except "normal" "locked" "entersearch" {
        bind "enter" { SwitchToMode "normal"; }
    }
    shared_except "normal" "locked" "entersearch" "renametab" "renamepane" {
        bind "esc" { SwitchToMode "normal"; }
    }
    shared_among "pane" "tmux" {
        bind "x" { CloseFocus; SwitchToMode "normal"; }
    }
    shared_among "scroll" "search" {
        bind "PageDown" { PageScrollDown; }
        bind "PageUp" { PageScrollUp; }
        bind "left" { PageScrollUp; }
        bind "down" { ScrollDown; }
        bind "up" { ScrollUp; }
        bind "right" { PageScrollDown; }
        bind "Ctrl b" { PageScrollUp; }
        bind "Ctrl c" { ScrollToBottom; SwitchToMode "normal"; }
        bind "d" { HalfPageScrollDown; }
        bind "Ctrl f" { PageScrollDown; }
        bind "h" { PageScrollUp; }
        bind "j" { ScrollDown; }
        bind "k" { ScrollUp; }
        bind "l" { PageScrollDown; }
        bind "Ctrl s" { SwitchToMode "normal"; }
        bind "u" { HalfPageScrollUp; }
    }
    entersearch {
        bind "Ctrl c" { SwitchToMode "scroll"; }
        bind "esc" { SwitchToMode "scroll"; }
        bind "enter" { SwitchToMode "search"; }
    }
    renametab {
        bind "esc" { UndoRenameTab; SwitchToMode "tab"; }
    }
    shared_among "renametab" "renamepane" {
        bind "Ctrl c" { SwitchToMode "normal"; }
    }
    renamepane {
        bind "esc" { UndoRenamePane; SwitchToMode "pane"; }
    }
    shared_among "session" "tmux" {
        bind "d" { Detach; }
    }
    tmux {
        bind "left" { MoveFocus "left"; SwitchToMode "normal"; }
        bind "down" { MoveFocus "down"; SwitchToMode "normal"; }
        bind "up" { MoveFocus "up"; SwitchToMode "normal"; }
        bind "right" { MoveFocus "right"; SwitchToMode "normal"; }
        bind "space" { NextSwapLayout; }
        bind "\"" { NewPane "down"; SwitchToMode "normal"; }
        bind "%" { NewPane "right"; SwitchToMode "normal"; }
        bind "," { SwitchToMode "renametab"; }
        bind "[" { SwitchToMode "scroll"; }
        bind "Ctrl b" { Write 2; SwitchToMode "normal"; }
        bind "c" { NewTab; SwitchToMode "normal"; }
        bind "h" { MoveFocus "left"; SwitchToMode "normal"; }
        bind "j" { MoveFocus "down"; SwitchToMode "normal"; }
        bind "k" { MoveFocus "up"; SwitchToMode "normal"; }
        bind "l" { MoveFocus "right"; SwitchToMode "normal"; }
        bind "n" { GoToNextTab; SwitchToMode "normal"; }
        bind "o" { FocusNextPane; }
        bind "p" { GoToPreviousTab; SwitchToMode "normal"; }
        bind "z" { ToggleFocusFullscreen; SwitchToMode "normal"; }
    }
}

plugins {
    about location="zellij:about"
    compact-bar location="zellij:compact-bar"
    configuration location="zellij:configuration"
    filepicker location="zellij:strider" {
        cwd "/"
    }
    plugin-manager location="zellij:plugin-manager"
    session-manager location="zellij:session-manager"
    status-bar location="zellij:status-bar"
    strider location="zellij:strider"
    tab-bar location="zellij:tab-bar"
    welcome-screen location="zellij:session-manager" {
        welcome_screen true
    }
}

load_plugins {
    zellij:link
}

web_client {
    font "monospace"
}

default_mode "normal"
default_shell "/bin/zsh"
default_layout "coding"
theme "github-light-shell"
${copy_command_line}
copy_clipboard "system"
copy_on_select false
scroll_buffer_size 50000
session_serialization true
serialize_pane_viewport false
show_startup_tips false
show_release_notes false
auto_layout true
mouse_mode true
pane_frames true
styled_underlines true
focus_follows_mouse false
mouse_click_through false
mirror_session false
on_force_close "detach"
web_server false
web_sharing "off"

themes {
    github-light-shell {
        text_unselected {
            base 87 96 106
            background 255 255 255
            emphasis_0 36 41 47
            emphasis_1 9 105 218
            emphasis_2 26 127 55
            emphasis_3 154 103 0
        }
        text_selected {
            base 31 35 40
            background 221 244 255
            emphasis_0 9 105 218
            emphasis_1 130 80 223
            emphasis_2 26 127 55
            emphasis_3 207 34 46
        }
        ribbon_unselected {
            base 36 41 47
            background 208 215 222
            emphasis_0 87 96 106
            emphasis_1 9 105 218
            emphasis_2 26 127 55
            emphasis_3 154 103 0
        }
        ribbon_selected {
            base 9 105 218
            background 221 244 255
            emphasis_0 36 41 47
            emphasis_1 9 105 218
            emphasis_2 26 127 55
            emphasis_3 207 34 46
        }
        table_title {
            base 36 41 47
            background 208 215 222
            emphasis_0 9 105 218
            emphasis_1 130 80 223
            emphasis_2 26 127 55
            emphasis_3 207 34 46
        }
        table_cell_unselected {
            base 36 41 47
            background 255 255 255
            emphasis_0 87 96 106
            emphasis_1 9 105 218
            emphasis_2 26 127 55
            emphasis_3 154 103 0
        }
        table_cell_selected {
            base 31 35 40
            background 221 244 255
            emphasis_0 9 105 218
            emphasis_1 130 80 223
            emphasis_2 26 127 55
            emphasis_3 207 34 46
        }
        list_unselected {
            base 36 41 47
            background 255 255 255
            emphasis_0 87 96 106
            emphasis_1 9 105 218
            emphasis_2 26 127 55
            emphasis_3 154 103 0
        }
        list_selected {
            base 31 35 40
            background 221 244 255
            emphasis_0 9 105 218
            emphasis_1 130 80 223
            emphasis_2 26 127 55
            emphasis_3 207 34 46
        }
        frame_unselected {
            base 214 222 229
            background 255 255 255
            emphasis_0 87 96 106
            emphasis_1 214 222 229
            emphasis_2 214 222 229
            emphasis_3 214 222 229
        }
        frame_selected {
            base 84 174 255
            background 255 255 255
            emphasis_0 9 105 218
            emphasis_1 130 80 223
            emphasis_2 26 127 55
            emphasis_3 207 34 46
        }
        frame_highlight {
            base 165 140 255
            background 255 255 255
            emphasis_0 130 80 223
            emphasis_1 9 105 218
            emphasis_2 26 127 55
            emphasis_3 207 34 46
        }
        exit_code_success {
            base 26 127 55
            background 255 255 255
            emphasis_0 26 127 55
            emphasis_1 26 127 55
            emphasis_2 26 127 55
            emphasis_3 26 127 55
        }
        exit_code_error {
            base 207 34 46
            background 255 255 255
            emphasis_0 207 34 46
            emphasis_1 207 34 46
            emphasis_2 207 34 46
            emphasis_3 207 34 46
        }
        multiplayer_user_colors {
            player_1 9 105 218
            player_2 26 127 55
            player_3 130 80 223
            player_4 207 34 46
            player_5 154 103 0
            player_6 31 35 40
            player_7 87 96 106
            player_8 221 244 255
            player_9 208 215 222
            player_10 36 41 47
        }
    }
}
EOF
}

write_layout() {
  local layout_file="${HOME}/.config/zellij/layouts/coding.kdl"

  mkdir -p "$(dirname "$layout_file")"

  cat >"$layout_file" <<'EOF'
layout {
    pane size=1 borderless=true {
        plugin location="tab-bar"
    }
    pane split_direction="vertical" {
        pane name="editor"
        pane split_direction="horizontal" size="30%" {
            pane name="terminal"
            pane name="git-status" command="git" {
                args "status"
            }
        }
    }
    pane size=1 borderless=true {
        plugin location="status-bar"
    }
}
EOF
}

write_zsh_helper() {
  local zshrc="${HOME}/.zshrc"
  local helper_block

  helper_block=$'zj() {\n  zellij attach -c "${1:-main}"\n}'
  upsert_block "$zshrc" "helper" "$helper_block"
}

validate_config() {
  zellij setup --check >/dev/null
}

main() {
  require_zellij
  write_zellij_config
  write_layout
  write_zsh_helper
  validate_config

  log "Configured zellij theme, layout, and shell helper"
  log "Open a new shell or run: source ~/.zshrc"
}

main "$@"
