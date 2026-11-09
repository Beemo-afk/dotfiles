#!/usr/bin/env bash
# Dev-work session:
#   Window "dev" with three roles (all start at a bash shell — no prefill) —
#     - editor : bash (greeted by screenfetch); your primary pane, run vim here
#     - ssh    : attach your SSH session to the dev box here
#     - fwd    : small pane for port-forwarding commands
#
# Wide (ultrawide):              Narrow (laptop):
#   +---------+-------+            +-------------------+
#   |         |  ssh  |            |      editor       |
#   | editor  +-------+            +-------------------+
#   |         |  fwd  |            |       ssh         |
#   +---------+-------+            +-------------------+
#                                  (fwd pane parked in a hidden 'stash' window)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$DIR/lib.sh"

# Launch dir from the keybind as #{pane_current_path} ($1); falls back to $PWD
# when run straight from a shell. DEV_DIR still overrides where panes start.
LAUNCH_DIR="${1:-$PWD}"
SESSION="$(derive_session_name dev "$LAUNCH_DIR")"
WINDOW="dev"                        # stable window name (reflow finds non-stash)
START_DIR="${DEV_DIR:-$LAUNCH_DIR}"

if ! session_exists "$SESSION"; then
  # Pane 0 -> editor (bash, greeted by screenfetch); primary pane, run vim here.
  tmux new-session -d -s "$SESSION" -n "$WINDOW" -c "$START_DIR" $PRIMARY_PROG
  # Keep the window name stable (base config has automatic-rename on), since
  # reflow.sh locates the main window as the first non-stash window.
  tmux set-window-option -t "$SESSION:$WINDOW" automatic-rename off
  # Label panes with a pane-scoped user option (@role); see case.sh for why.
  tmux set-option -p -t "$SESSION:$WINDOW.0" @role editor
  greet_primary "$SESSION:$WINDOW.0"

  # Split right -> ssh (pane 1), plain shell.
  tmux split-window -h -t "$SESSION:$WINDOW.0" -c "$START_DIR"
  tmux set-option -p -t "$SESSION:$WINDOW.1" @role ssh

  # Split the right column -> fwd (pane 2), kept small for port-forwarding.
  tmux split-window -v -t "$SESSION:$WINDOW.1" -c "$START_DIR"
  tmux set-option -p -t "$SESSION:$WINDOW.2" @role fwd

  # editor gets the wide share; fwd pane made short; land on editor.
  tmux resize-pane -t "$SESSION:$WINDOW.0" -x '65%' 2>/dev/null || true
  tmux resize-pane -t "$SESSION:$WINDOW.2" -y '20%' 2>/dev/null || true
  tmux select-pane -t "$SESSION:$WINDOW.0"

  if is_narrow "$SESSION"; then "$DIR/reflow.sh" narrow "$SESSION" >/dev/null 2>&1 || true; fi

  # Freshly created: give it a random theme (no prompt). Re-attaches keep the
  # existing theme; prefix + T opens the menu to change it.
  attach_with_random_theme "$SESSION"
else
  attach_or_switch "$SESSION"
fi
