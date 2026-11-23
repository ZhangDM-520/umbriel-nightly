#!/usr/bin/env bash
# Dragging a maximized or region-snapped floating window must animate its size
# back to the restored floating size while staying anchored to the pointer.
set -euo pipefail
source "$(dirname "$UMBRIEL_HARNESS_LIB")/title_bar.sh"

cat >>"$UMBRIEL_CONFIG" <<'CONFIG'
[animation]
duration_ms = 2000
curve = "linear"

[animation.windows_in]
enabled = false

[appearance]
border_width = 0
outer_border_width = 0
corner_radius = 0
drag_opacity = 1.0

[appearance.title_bar]
mode = "forced"

[appearance.shadow]
enabled = false

[colors.title_bar]
background = "#FF0000FF"
background_unfocused = "#FF0000FF"
text = "#FF0000FF"
text_unfocused = "#FF0000FF"
close = "#FF0000FF"
maximize = "#FF0000FF"

[[window_rule]]
match.title = "^floating-drag-restore$"
default_floating = true
default_floating_size_px = { width = 480, height = 300 }
default_position = { x = 173, y = 109, anchor = "top_left" }
CONFIG
"$UMBRIEL" msg config-reload >/dev/null

title_bar_bbox() {
  local image="$UMBRIEL_RUNTIME_DIR/$1.png"
  grim "$image"
  "$UMBRIEL_PIXEL_PROBE" "$image" bbox 'r > 0.9 && g < 0.1 && b < 0.1'
}

assert_drag_restore_animates() {
  local label=$1 start_width=$2
  "$UMBRIEL" clock-freeze >/dev/null
  pointer_hold 1280 720 move 100 20 press 272 move 100 120 -- release 272
  "$UMBRIEL" clock-advance 200 >/dev/null
  local x1 y1 w1 _h1 x2 y2 w2 _h2 _xd _yd done_w _hd
  read -r x1 y1 w1 _h1 < <(title_bar_bbox "${label}-200ms")
  "$UMBRIEL" clock-advance 400 >/dev/null
  read -r x2 y2 w2 _h2 < <(title_bar_bbox "${label}-600ms")
  if ! (( start_width > w1 && w1 > w2 && w2 > 480 )); then
    echo "$label did not animate monotonically: w1=$w1 w2=$w2 (expected $start_width > w1 > w2 > 480)"
    exit 1
  fi
  if (( x1 != x2 || y1 != y2 )); then
    echo "$label position drifted during drag: (${x1},${y1}) -> (${x2},${y2})"
    exit 1
  fi
  "$UMBRIEL" clock-advance 2000 >/dev/null
  pointer_release
  "$UMBRIEL" clock-resume >/dev/null
  "$UMBRIEL" settle >/dev/null
  read -r _xd _yd done_w _hd < <(title_bar_bbox "${label}-done")
  if (( done_w != 480 )); then
    echo "$label settled at width $done_w, expected 480"
    exit 1
  fi
}

"$UMBRIEL_FRACTIONAL_CLIENT" floating-drag-restore 480 300 >"$UMBRIEL_RUNTIME_DIR/client.log" 2>&1 &
title_bar_wait_box floating-drag-restore 480x300+173+109
"$UMBRIEL" settle >/dev/null

# 1. Maximized floating window dragged in a scrolling workspace (grab.stackingLayout == false).
"$UMBRIEL" msg window-toggle-maximize >/dev/null
"$UMBRIEL" settle >/dev/null
title_bar_wait_box floating-drag-restore 1264x676+8+36
assert_drag_restore_animates scrolling-max-drag 1264

# 2. Maximized floating window dragged in a stacking workspace.
"$UMBRIEL" msg workspace-set-layout stacking >/dev/null
"$UMBRIEL" msg window-toggle-maximize >/dev/null
"$UMBRIEL" settle >/dev/null
title_bar_wait_box floating-drag-restore 1264x676+8+36
assert_drag_restore_animates stacking-max-drag 1264

# 3. Region-snapped floating window dragged in a stacking workspace.
"$UMBRIEL" msg window-set-region left >/dev/null
"$UMBRIEL" settle >/dev/null
title_bar_wait_box floating-drag-restore 628x676+8+36
assert_drag_restore_animates stacking-region-drag 628

echo "maximized (scrolling/stacking) and region-snapped floating drags animate size restore"
