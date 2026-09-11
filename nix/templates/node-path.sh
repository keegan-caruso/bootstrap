# shellcheck shell=sh

export FNM_DIR="${FNM_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/fnm}"
# Keep an explicitly selected runtime ahead of the stable default fallback.
case ":$PATH:" in
  *":$FNM_DIR/aliases/default/bin:"*) ;;
  *) export PATH="$PATH:$FNM_DIR/aliases/default/bin" ;;
esac
