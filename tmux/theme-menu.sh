#!/usr/bin/env bash
# Show a tmux popup menu of available themes and apply the chosen one to the
# current (or given) session. Themes are auto-discovered from themes/*.sh, so
# dropping in a new palette file makes it appear here automatically.
#
# Usage: theme-menu.sh [session]
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEMES_DIR="$DIR/themes"
SESSION="${1:-$(tmux display-message -p '#{session_name}')}"

# Build display-menu arguments: for each theme, a label + key + command.
# Menu item = (label, shortcut-key, command-to-run-on-select).
args=()
i=0
for f in "$THEMES_DIR"/*.sh; do
  [ -e "$f" ] || continue
  name="$(basename "$f" .sh)"
  # Pull the human label without executing side effects (files are data-only,
  # but grep keeps this cheap and avoids sourcing in the menu builder).
  label="$(grep -m1 '^THEME_LABEL=' "$f" | cut -d'"' -f2)"
  [ -n "$label" ] || label="$name"
  key="$i"; [ "$i" -ge 10 ] && key=""     # first 10 get number shortcuts
  args+=("$label" "$key" "run-shell \"$DIR/apply-theme.sh $name $SESSION\"")
  i=$((i + 1))
done

if [ "${#args[@]}" -eq 0 ]; then
  tmux display-message "No themes found in $THEMES_DIR"
  exit 0
fi

tmux display-menu -T " Theme: $SESSION " -x C -y C "${args[@]}"
