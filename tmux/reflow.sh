#!/usr/bin/env bash
# Reshape a live workflow session between two layouts, at runtime, without
# tearing anything down. This is the bit a load-once tool (tmuxp) can't do:
# it moves running panes when you dock to the ultrawide or undock to the laptop.
#
#   wide   : main-vertical — one big pane left, others stacked right (3 panes)
#   narrow : two panes stacked top/bottom; the extra pane(s) parked in a
#            hidden "stash" window so nothing is lost
#   toggle : flip between the two based on current pane count
#   auto   : pick wide/narrow from the attached client's width
#
# Usage: reflow.sh {wide|narrow|toggle|auto} [session]
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$DIR/lib.sh"

MODE="${1:-toggle}"
SESSION="${2:-$(tmux display-message -p '#{session_name}')}"
STASH="stash"                 # window that parks panes hidden in narrow mode
MAIN_WIDTH="${TMUX_MAIN_WIDTH:-62%}"

# The "main" window is the first one that isn't the stash.
main_win() {
  tmux list-windows -t "$SESSION" -F '#{window_name}' \
    | grep -vx "$STASH" | head -n1
}

stash_exists() { tmux list-windows -t "$SESSION" -F '#{window_name}' | grep -qx "$STASH"; }

go_wide() {
  local win; win="$(main_win)"
  local target; target="$(tmux list-panes -t "$SESSION:$win" -F '#{pane_id}' | head -n1)"
  # Pull any parked panes back into the main window.
  if stash_exists; then
    for p in $(tmux list-panes -t "$SESSION:$STASH" -F '#{pane_id}'); do
      tmux join-pane -d -s "$p" -t "$target"
    done
    # stash window self-destructs once its last pane leaves
  fi
  tmux set-window-option -t "$SESSION:$win" main-pane-width "$MAIN_WIDTH" >/dev/null
  tmux select-layout -t "$SESSION:$win" main-vertical
}

go_narrow() {
  local win; win="$(main_win)"
  # Park every pane beyond the first two into the stash window.
  local i=0
  for p in $(tmux list-panes -t "$SESSION:$win" -F '#{pane_id}'); do
    i=$((i + 1))
    [ "$i" -le 2 ] && continue
    if stash_exists; then
      tmux join-pane -d -s "$p" -t "$SESSION:$STASH"
    else
      tmux break-pane -d -s "$p" -n "$STASH"
    fi
  done
  tmux select-layout -t "$SESSION:$win" even-vertical
}

case "$MODE" in
  wide)   go_wide ;;
  narrow) go_narrow ;;
  auto)   if is_narrow "$SESSION"; then go_narrow; else go_wide; fi ;;
  toggle)
    win="$(main_win)"
    n="$(tmux list-panes -t "$SESSION:$win" -F x | wc -l | tr -d ' ')"
    if [ "$n" -ge 3 ]; then go_narrow; else go_wide; fi ;;
  *) echo "usage: reflow.sh {wide|narrow|toggle|auto} [session]" >&2; exit 2 ;;
esac
