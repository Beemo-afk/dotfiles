#!/usr/bin/env bash
# Pick a random theme from themes/*.sh and apply it to the given (or current)
# session. Used by the launchers to theme a fresh session without prompting;
# also fine to run on its own to re-roll the palette. Change it deliberately
# any time with the theme menu (prefix + T).
#
# Usage: theme-random.sh [session]
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEMES_DIR="$DIR/themes"
SESSION="${1:-$(tmux display-message -p '#{session_name}')}"

# Collect theme names (basename without .sh).
themes=()
for f in "$THEMES_DIR"/*.sh; do
  [ -e "$f" ] || continue
  themes+=("$(basename "$f" .sh)")
done
[ "${#themes[@]}" -gt 0 ] || { tmux display-message "No themes in $THEMES_DIR"; exit 0; }

# $RANDOM is 0-32767; modulo the count is plenty uniform for a palette pick.
choice="${themes[$((RANDOM % ${#themes[@]}))]}"
exec "$DIR/apply-theme.sh" "$choice" "$SESSION"
