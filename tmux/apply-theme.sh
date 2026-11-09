#!/usr/bin/env bash
# Apply a color theme to ONE tmux session's UI (status bar, window tabs, pane
# borders, messages, copy-mode, clock) and pane canvas. Session-scoped so case
# and dev can wear different themes at the same time. A per-session hook keeps
# newly-created windows themed.
#
# Usage: apply-theme.sh <theme-name> [session]
#
# Note: this themes tmux's OWN rendering (works identically over SSH). It does
# not repaint the terminal emulator's 16-color palette, and programs that draw
# their own colors (vim, yazi) keep their own themes.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEMES_DIR="$DIR/themes"

THEME="${1:?usage: apply-theme.sh <theme-name> [session]}"
SESSION="${2:-$(tmux display-message -p '#{session_name}')}"

FILE="$THEMES_DIR/$THEME.sh"
if [ ! -f "$FILE" ]; then
  echo "apply-theme: unknown theme '$THEME' (looked in $THEMES_DIR)" >&2
  exit 1
fi
# Paint the pane canvas background to the theme? On by default; set to 0 if you
# prefer panes to keep the terminal emulator's own background.
: "${THEME_PAINT_CANVAS:=1}"

# shellcheck source=/dev/null
. "$FILE"

# Derive a status-bar background that always contrasts with the canvas by
# nudging the theme background toward its foreground (works for light and dark
# palettes alike). This lets theme files carry plain, source-accurate ANSI
# without fudging 'black' just to keep the status bar visible.
mix_hex() {  # mix_hex <hex_base> <hex_toward> <percent_toward>
  local a="${1#\#}" b="${2#\#}" p="$3"
  printf '#%02x%02x%02x' \
    "$(( (16#${a:0:2}*(100-p) + 16#${b:0:2}*p)/100 ))" \
    "$(( (16#${a:2:2}*(100-p) + 16#${b:2:2}*p)/100 ))" \
    "$(( (16#${a:4:2}*(100-p) + 16#${b:4:2}*p)/100 ))"
}
sbg="$(mix_hex "$background" "$foreground" 12)"

# --- helpers ---------------------------------------------------------------
so() { tmux set-option    -t "$SESSION" "$@"; }          # session-scoped option
# Apply a window option to every window currently in the session.
wo() {
  local opt="$1" val="$2" w
  for w in $(tmux list-windows -t "$SESSION" -F '#{window_id}'); do
    tmux set-window-option -t "$w" "$opt" "$val"
  done
}

# --- status bar ------------------------------------------------------------
so status-style      "bg=$sbg,fg=$foreground"
so message-style     "bg=$brightBlack,fg=$foreground"
so message-command-style "bg=$brightBlack,fg=$foreground"

# Rebuild Dave-Eddy-style left/right using palette hex, plus a theme tag.
so status-left "#[fg=$blue,bold][ #[fg=$green,nobold]#H #[fg=$magenta]:: #[fg=$brightMagenta]{#[fg=$green]#S#[fg=$brightMagenta]} #[fg=$blue,bold]] ["
so status-right "#[fg=$blue,bold]] [ #[fg=$brightBlack,nobold]$THEME_LABEL #[fg=$green]#(date '+%m/%d') #[fg=$yellow]#(date '+%H:%M') #[fg=$blue,bold]]"

# --- window tabs (window options) ------------------------------------------
wo window-status-current-format "#[fg=$background,bg=$blue,bold] #I#F#W #[default]"
wo window-status-format         "#[fg=$brightBlack] #I#F#W "
wo window-status-current-style  "bg=$blue,fg=$background"
wo window-status-style          "bg=$sbg,fg=$brightBlack"

# --- pane borders (window options) -----------------------------------------
# Active border pops in the cursor accent; inactive uses a mid-tone that still
# reads against light backgrounds. Also theme the border label bar so it's
# obviously styled: the active pane's label gets an accent highlight.
wo pane-border-style        "fg=$brightBlack,bg=$background"
wo pane-active-border-style "fg=$cursor,bg=$background,bold"
# Commas inside the true/false branches of #{?...} are escaped as '#,'.
wo pane-border-format \
  "#{?pane_active,#[fg=$background#,bg=$cursor#,bold],#[fg=$brightBlack#,bg=$black]} #P:#{?@role,#{@role},#{pane_current_command}} #[default]"

# --- copy-mode + clock (window options) ------------------------------------
wo mode-style        "bg=$yellow,fg=$background"
wo clock-mode-colour "$blue"

# --- pane canvas (window options) ------------------------------------------
if [ "$THEME_PAINT_CANVAS" = "1" ]; then
  wo window-active-style "bg=$background,fg=$foreground"
  wo window-style        "bg=$background,fg=$foreground"
fi

# --- pane ANSI palette (window options) ------------------------------------
# Remap the pane's 16 indexed colours (0-15) to the theme's own hues. Without
# this, programs that draw with indexed colours get the terminal EMULATOR's
# built-in palette, which never changes with the theme. The visible symptom is
# a light theme "blacking out" text: an app paints a block with ANSI black
# (e.g. '\033[40m') expecting a dark accent, gets the emulator's TRUE black, and
# the theme's near-black default foreground then sits on a black block -> the
# text is unreadable. Mapping index 0 to the light theme's own (light) "black"
# makes that block light, so the dark text reads again; dark themes are
# unaffected since their index 0 is already dark.
#
# pane-colours is session/pane-scoped like everything else here, so it works
# over SSH and keeps case/dev on independent themes. It arrived in tmux 3.2;
# older tmux lacks the option, so each set is best-effort (the rest of the theme
# still applies). The 0-15 order is the standard ANSI mapping.
palette=(
  "$black"       "$red"       "$green"       "$yellow"       # 0-3
  "$blue"        "$magenta"   "$cyan"         "$white"        # 4-7
  "$brightBlack" "$brightRed" "$brightGreen"  "$brightYellow" # 8-11
  "$brightBlue"  "$brightMagenta" "$brightCyan" "$brightWhite" # 12-15
)
for w in $(tmux list-windows -t "$SESSION" -F '#{window_id}'); do
  idx=0
  for hex in "${palette[@]}"; do
    tmux set-window-option -t "$w" "pane-colours[$idx]" "$hex" 2>/dev/null || true
    idx=$((idx + 1))
  done
done

# --- remember choice + keep new windows themed -----------------------------
so @theme "$THEME"
# Re-run on new/split windows so their window-scoped options match. Replaces the
# hook each call (no accumulation); does not create windows, so it can't recurse.
tmux set-hook -t "$SESSION" after-new-window   "run-shell '$DIR/apply-theme.sh $THEME $SESSION'"
tmux set-hook -t "$SESSION" after-split-window "run-shell '$DIR/apply-theme.sh $THEME $SESSION'"

tmux refresh-client -S 2>/dev/null || true
