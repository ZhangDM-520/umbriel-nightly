#!/usr/bin/env bash
# Dragging a maximized or region-snapped floating window (including a maximized
# scratchpad) must animate its size restore while preserving the grab offset.
set -euo pipefail
source "$(dirname "$UMBRIEL_HARNESS_LIB")/title_bar.sh"

cat >>"$UMBRIEL_CONFIG" <<'CONFIG'
[animation]
duration_ms = 400
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

window_pos() {
  "$UMBRIEL" windows --json \
    | jq -r '.[] | select(.title == "floating-drag-restore") | "\(.x) \(.y)"'
}

assert_drag_restore_animates() {
  local label=$1 start_width=$2
  "$UMBRIEL" clock-freeze >/dev/null
  pointer_hold 1280 720 move 100 20 press 272 move 100 120 -- release 272
  "$UMBRIEL" clock-advance 80 >/dev/null
  local x1 y1 w1 _h1 x2 y2 w2 _h2 _xd _yd done_w _hd
  read -r x1 y1 w1 _h1 < <(title_bar_bbox "${label}-80ms")
  "$UMBRIEL" clock-advance 160 >/dev/null
  read -r x2 y2 w2 _h2 < <(title_bar_bbox "${label}-240ms")
  if ! (( start_width > w1 && w1 > w2 && w2 > 480 )); then
    echo "$label did not animate monotonically: w1=$w1 w2=$w2 (expected $start_width > w1 > w2 > 480)"
    exit 1
  fi
  if (( x1 != x2 || y1 != y2 )); then
    echo "$label position drifted during drag: (${x1},${y1}) -> (${x2},${y2})"
    exit 1
  fi
  "$UMBRIEL" clock-advance 500 >/dev/null
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

# 4. Maximized scratchpad dragged with move animations enabled preserves the restored grab offset.
"$UMBRIEL" msg window-move-to-scratchpad >/dev/null
"$UMBRIEL" msg scratchpad-toggle >/dev/null
"$UMBRIEL" settle >/dev/null
read -r sx sy < <(window_pos)
"$UMBRIEL" msg window-toggle-maximize >/dev/null
"$UMBRIEL" settle >/dev/null
title_bar_wait_box floating-drag-restore 1264x676+8+36

"$UMBRIEL" clock-freeze >/dev/null
pointer_hold 1280 720 move 100 200 mod logo press 272 move 140 230 -- release 272 mod none
"$UMBRIEL" clock-advance 80 >/dev/null
read -r _x1 _y1 sw1 _h1 < <(title_bar_bbox scratchpad-max-80ms)
"$UMBRIEL" clock-advance 160 >/dev/null
read -r _x2 _y2 sw2 _h2 < <(title_bar_bbox scratchpad-max-240ms)
if ! (( 1264 > sw1 && sw1 > sw2 && sw2 > 480 )); then
  echo "scratchpad max drag did not animate monotonically: w1=$sw1 w2=$sw2"
  exit 1
fi
"$UMBRIEL" clock-advance 500 >/dev/null
pointer_release
"$UMBRIEL" clock-resume >/dev/null
"$UMBRIEL" settle >/dev/null
read -r dx dy < <(window_pos)
if (( dx < sx + 39 || dx > sx + 41 || dy < sy + 29 || dy > sy + 31 )); then
  echo "scratchpad max drag dropped at (${dx},${dy}), expected near ($((sx + 40)),$((sy + 30))) from (${sx},${sy})"
  exit 1
fi

echo "maximized (scrolling/stacking/scratchpad) and region-snapped floating drags animate size restore"
