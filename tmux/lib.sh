#!/usr/bin/env bash
# Shared helpers for tmux workflow launchers (case.sh, dev.sh).
#
# These scripts build/attach named tmux sessions using only native tmux
# commands, so they work identically on this laptop and on any remote box
# (e.g. a remote dev box) that has tmux installed. No extra deps.

# Width (in columns) below which we treat the client as "narrow" (laptop):
# stack at most two panes and skip the third. Tune to taste.
: "${TMUX_NARROW_COLS:=180}"

# Program to run in a "primary" pane. Just interactive bash — kept as a single
# argv so it survives tmux's word-splitting of the new-session/split-window
# command. The screenfetch greeting is sent separately via greet_primary().
PRIMARY_PROG="bash"

# Fire a screenfetch greeting into a freshly-created bash pane. Sent as keys
# (not baked into the pane command) so the argv stays a clean single word and
# ~/.bashrc still loads normally. No-op quietly if screenfetch is absent.
greet_primary() {
  local target="$1"
  tmux send-keys -t "$target" \
    'command -v screenfetch >/dev/null 2>&1 && screenfetch' C-m
}

# Return the width of the attached client, or 0 if nothing is attached yet.
# Used so a freshly-created (detached) session still lays out sensibly.
client_cols() {
  local s="$1"
  tmux display-message -p -t "$s" '#{client_width}' 2>/dev/null | grep -E '^[0-9]+$' || echo 0
}

# Is the given session (or the current client) narrow enough that we should
# use the laptop layout? A detached/unknown width (0) is treated as WIDE so
# the full layout is built; reflow at attach time handles the narrow case.
is_narrow() {
  local cols; cols="$(client_cols "$1")"
  [ "$cols" -gt 0 ] && [ "$cols" -lt "$TMUX_NARROW_COLS" ]
}

# True if a session with this exact name already exists.
session_exists() {
  tmux has-session -t "=$1" 2>/dev/null
}

# Derive a session name from a launch directory.
#   derive_session_name <prefix> <dir>
# Rule: use the directory's basename, sanitized; prepend "<prefix>-" unless the
# basename already starts with the prefix. Launched from $HOME or / (no
# meaningful project name), fall back to the bare prefix.
#   case + ~/work/case-123  -> case-123      (already prefixed)
#   case + ~/work/foo       -> case-foo
#   dev  + ~/work/llm       -> dev-llm
#   dev  + ~/work/dev-x     -> dev-x
derive_session_name() {
  local prefix="$1" dir="$2" base
  if [ -z "$dir" ] || [ "$dir" = "$HOME" ] || [ "$dir" = "/" ]; then
    echo "$prefix"; return
  fi
  base="$(basename "$dir")"
  # tmux session names can't contain '.' or ':'; collapse those and spaces to
  # '-', squeeze repeats, trim edges.
  base="$(printf '%s' "$base" | tr ' .:/' '----' | sed -E 's/-+/-/g; s/^-|-$//g')"
  [ -n "$base" ] || { echo "$prefix"; return; }
  case "$base" in
    "$prefix" | "$prefix"-*) echo "$base" ;;
    *) echo "$prefix-$base" ;;
  esac
}

# When launched from inside tmux, the session we launched FROM is usually the
# throwaway session tmux auto-creates for a bare `tmux` invocation, named with
# the next integer ("0", "1", ...). Once switch-client moves us onto the
# workflow session, that origin is just an empty orphan cluttering `tmux ls`,
# so kill it. Guards keep this safe:
#   * only pure-numeric names (tmux's default auto-naming) are touched, never a
#     named case-/dev- session or anything you deliberately named;
#   * skipped if another client is still attached to it (don't detach another
#     terminal out from under itself).
kill_origin_scratch() {
  local from="$1" target="$2"
  [ -n "$from" ] && [ "$from" != "$target" ] || return 0
  case "$from" in ''|*[!0-9]*) return 0 ;; esac
  [ -z "$(tmux list-clients -t "=$from" 2>/dev/null)" ] || return 0
  tmux kill-session -t "=$from" 2>/dev/null || true
}

# Attach if we're on a terminal, otherwise switch the current client.
# Lets the launchers work both from a plain shell and from inside tmux.
attach_or_switch() {
  local s="$1"
  if [ -n "$TMUX" ]; then
    local from; from="$(tmux display-message -p '#{session_name}')"
    tmux switch-client -t "$s"
    kill_origin_scratch "$from" "$s"
  else
    tmux attach-session -t "$s"
  fi
}

# Give a freshly-created session a RANDOM theme, then attach/switch to it.
# Applying a theme (unlike display-menu) needs no attached client, so we can
# theme the detached session up front and attach normally — no deferred hook
# needed. Pick a theme deliberately any time with prefix + T (the theme menu).
attach_with_random_theme() {
  local s="$1"
  "$DIR/theme-random.sh" "$s" >/dev/null 2>&1 || true
  attach_or_switch "$s"
}
