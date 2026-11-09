#!/usr/bin/env bash
# Case-work session:
#   Window "case" with three roles —
#     - primary : bash shell, or runs $CASE_PRIMARY_CMD if set (e.g. a CLI
#                 agent or REPL you live in for this piece of work).
#     - files   : yazi file explorer. Enter on a file opens it in $EDITOR (vim),
#                 which is how you review logs / open text for correspondence.
#     - ops     : small shell (greeted by screenfetch) for side commands —
#                 git, auth refreshes, one-off scripts.
#
# Wide (ultrawide):              Narrow (laptop):
#   +---------+-------+            +-------------------+
#   |         |  ops  |            |     primary       |
#   | primary +-------+            +-------------------+
#   |         | files |            |       ops         |
#   +---------+-------+            +-------------------+
#                                  (files parked in a hidden 'stash' window)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$DIR/lib.sh"

# Launch dir comes from the keybind as #{pane_current_path} ($1); when run
# straight from a shell, $1 is empty so fall back to the real $PWD. CASE_DIR
# still overrides where the panes start.
LAUNCH_DIR="${1:-$PWD}"
SESSION="$(derive_session_name case "$LAUNCH_DIR")"
WINDOW="case"                       # stable window name (reflow finds non-stash)
START_DIR="${CASE_DIR:-$LAUNCH_DIR}"
# The ops pane can start somewhere else (e.g. a parent dir of all your work
# dirs) via CASE_OPS_DIR; otherwise it starts with the other panes. Falls back
# to START_DIR if that dir isn't present on this box.
OPS_DIR="${CASE_OPS_DIR:-$START_DIR}"
[ -d "$OPS_DIR" ] || OPS_DIR="$START_DIR"
# Prefer a real file explorer if present; fall back to a shell.
if command -v yazi >/dev/null 2>&1; then FILES_CMD="yazi"
else FILES_CMD="${SHELL:-/bin/zsh}"; fi
# Optional command run in the primary pane (export CASE_PRIMARY_CMD, e.g. in
# ~/.bashrc.local). Unset/empty keeps a greeted shell; it also falls back to the
# shell on a box where the command's binary isn't installed.
PRIMARY_CMD="${CASE_PRIMARY_CMD:-}"

if ! session_exists "$SESSION"; then
  # Pane 0 -> primary (bash, greeted by screenfetch)
  tmux new-session -d -s "$SESSION" -n "$WINDOW" -c "$START_DIR" $PRIMARY_PROG
  # Keep the window name stable (base config has automatic-rename on), since
  # reflow.sh locates the main window as the first non-stash window.
  tmux set-window-option -t "$SESSION:$WINDOW" automatic-rename off
  # Label panes with a pane-scoped user option (@role) rather than -T: shells
  # and TUIs (bash prompt, yazi) rewrite pane_title via escapes, but @role
  # sticks and travels with the pane through reflow's join/break.
  tmux set-option -p -t "$SESSION:$WINDOW.0" @role primary
  # Prefill the primary command. If PRIMARY_CMD is empty or its binary is
  # missing, fall back to the screenfetch-greeted bash shell so the launcher
  # still works anywhere.
  primary_bin="${PRIMARY_CMD%% *}"
  if [ -n "$PRIMARY_CMD" ] && command -v "$primary_bin" >/dev/null 2>&1; then
    tmux send-keys -t "$SESSION:$WINDOW.0" "$PRIMARY_CMD" C-m
  else
    greet_primary "$SESSION:$WINDOW.0"
  fi

  # Split right -> ops (pane 1): a small greeted bash shell for the out-of-agent
  # commands (git, auth refreshes, one-off scripts). It
  # sits top-right, at eye level next to the agent. Runs bash explicitly (via
  # $PRIMARY_PROG, not the login shell) so ~/.bashrc loads and it matches the
  # primary pane, and starts in $OPS_DIR. greet_primary then fires the
  # screenfetch greeting.
  tmux split-window -h -t "$SESSION:$WINDOW.0" -c "$OPS_DIR" $PRIMARY_PROG
  tmux set-option -p -t "$SESSION:$WINDOW.1" @role ops
  greet_primary "$SESSION:$WINDOW.1"

  # Split the ops column -> files (pane 2): yazi over the work dir, below ops.
  # reflow's narrow mode parks pane #3+ in the stash, so on a laptop this pane
  # hides (primary + ops stay) and returns when you dock wide.
  tmux split-window -v -t "$SESSION:$WINDOW.1" -c "$START_DIR"
  tmux set-option -p -t "$SESSION:$WINDOW.2" @role files
  tmux send-keys   -t "$SESSION:$WINDOW.2" "$FILES_CMD" C-m

  # primary gets the wide share; ops kept short up top; land cursor on primary.
  tmux resize-pane -t "$SESSION:$WINDOW.0" -x '62%' 2>/dev/null || true
  tmux resize-pane -t "$SESSION:$WINDOW.1" -y '30%' 2>/dev/null || true
  tmux select-pane -t "$SESSION:$WINDOW.0"

  # On a laptop-width client, stack the two panes top/bottom.
  if is_narrow "$SESSION"; then "$DIR/reflow.sh" narrow "$SESSION" >/dev/null 2>&1 || true; fi

  # Freshly created: give it a random theme (no prompt). Re-attaching to an
  # existing session keeps whatever theme it already has; prefix + T opens the
  # menu to change it.
  attach_with_random_theme "$SESSION"
else
  attach_or_switch "$SESSION"
fi
