#!/usr/bin/env bash
# Dragging a tiled window out of the layout animates the remaining tiled windows into the freed space via
# animation.windows_move (and windows_resize when their size changes), rather than snapping them immediately.
set -euo pipefail
source "$UMBRIEL_HARNESS_LIB"

readonly BTN_LEFT=272
readonly OUTPUT_W=1280
readonly OUTPUT_H=720
readonly IMAGE="$UMBRIEL_RUNTIME_DIR/tiled-drag-detach.png"

write_config() {
  local mode=$1 move_enabled=$2 resize_enabled=$3
  cat > "$UMBRIEL_CONFIG" <<EOF
[colors]
backdrop = "#000000FF"

[appearance]
border_width = 0
outer_border_width = 0
corner_radius = 0

[appearance.shadow]
enabled = false

[layout]
mode = "$mode"
gap = 0

[layout.scrolling]
default_extent_fraction = 0.5
center_underfull_strip = false

[animation]
enabled = true

[animation.windows_in]
enabled = false

[animation.windows_out]
enabled = false

[animation.windows_move]
enabled = $move_enabled
duration_ms = 400
curve = "linear"

[animation.windows_resize]
enabled = $resize_enabled
duration_ms = 400
curve = "linear"
EOF
  "$UMBRIEL" msg config-reload > /dev/null
}

spawn() {
  local title=$1 color=$2
  FILL_COLOR="$color" "$UMBRIEL_UNMAP_CLIENT" "$title" 640 720 > "$UMBRIEL_RUNTIME_DIR/$title.log" 2>&1 &
  for _ in $(seq 80); do
    if "$UMBRIEL" windows --json | jq -e --arg title "$title" 'any(.[]; .title == $title)' > /dev/null; then
      return 0
    fi
    sleep 0.025
  done
  echo "timed out waiting for $title"
  return 1
}

# Measure the red survivor on a top strip (y=48..55). Dragging the blue window downward moves its top edge well below
# y=55 so the red survivor stays unobstructed throughout the drag. Use a dominance predicate so a translucent drop
# hint overlay does not mask the red window.
readonly RED_EXPR='r > 0.5 && g < 0.4 && b < 0.4'

red_strip_width() {
  local region=$1
  grim "$IMAGE"
  local pixels
  pixels=$("$UMBRIEL_PIXEL_PROBE" "$IMAGE" count "$RED_EXPR" "$region")
  echo $(((pixels + 4) / 8))
}

write_config scrolling true true
"$UMBRIEL" clock-freeze

spawn drag-detach-left 0xFF0000FF
spawn drag-detach-right 0xFFFF0000
"$UMBRIEL" clock-advance 1000
"$UMBRIEL" settle

# Case 1: Scrolling layout — dragging the left tile out animates the right tile leftward via animation.windows_move.
before_left=$(red_strip_width 720x8+0+48)
if ((before_left > 16)); then
  echo "expected left region to have no red before drag in scrolling: before_left=$before_left"
  exit 1
fi

pointer_hold "$OUTPUT_W" "$OUTPUT_H" move 100 360 mod logo press "$BTN_LEFT" move 1200 600 -- release "$BTN_LEFT" mod none
"$UMBRIEL" clock-advance 320
w1=$(red_strip_width 720x8+0+48)
"$UMBRIEL" clock-advance 40
w2=$(red_strip_width 720x8+0+48)
"$UMBRIEL" clock-advance 500
"$UMBRIEL" settle
final_left=$(red_strip_width 720x8+0+48)
pointer_release
"$UMBRIEL" clock-advance 1000
"$UMBRIEL" settle

if ! ((before_left < w1 && w1 < w2 && w2 < final_left)); then
  echo "scrolling drag detach did not animate monotonically: before=$before_left w1=$w1 w2=$w2 final=$final_left"
  exit 1
fi

blue_center() {
  "$UMBRIEL" windows --json | jq -r '.[] | select(.title == "drag-detach-left") | "\((.x + .w / 2) | floor) \((.y + .h / 2) | floor)"'
}

# Case 2: Dwindle layout — dragging the blue tile out animates the red tile leftward to fill the freed space.
write_config dwindle true true
"$UMBRIEL" clock-advance 1000
"$UMBRIEL" settle

before_w=$(red_strip_width 720x8+0+48)
read -r bx by <<< "$(blue_center)"
pointer_hold "$OUTPUT_W" "$OUTPUT_H" move "$bx" "$by" mod logo press "$BTN_LEFT" move 1200 600 -- release "$BTN_LEFT" mod none
"$UMBRIEL" clock-advance 320
w1=$(red_strip_width 720x8+0+48)
"$UMBRIEL" clock-advance 40
w2=$(red_strip_width 720x8+0+48)
"$UMBRIEL" clock-advance 500
"$UMBRIEL" settle
final_w=$(red_strip_width 720x8+0+48)
pointer_release
"$UMBRIEL" clock-advance 1000
"$UMBRIEL" settle

if ! ((before_w < w1 && w1 < w2 && w2 < final_w)); then
  echo "dwindle drag detach did not animate monotonically: before=$before_w w1=$w1 w2=$w2 final=$final_w"
  exit 1
fi

# Case 3: Disabled windows_move/windows_resize snaps immediately.
write_config dwindle false false
"$UMBRIEL" clock-advance 1000
"$UMBRIEL" settle

read -r bx by <<< "$(blue_center)"
pointer_hold "$OUTPUT_W" "$OUTPUT_H" move "$bx" "$by" mod logo press "$BTN_LEFT" move 1200 600 -- release "$BTN_LEFT" mod none
"$UMBRIEL" clock-advance 50
w_snap=$(red_strip_width 720x8+0+48)
"$UMBRIEL" clock-advance 500
"$UMBRIEL" settle
w_snap_final=$(red_strip_width 720x8+0+48)
pointer_release
"$UMBRIEL" clock-advance 1000
"$UMBRIEL" settle

if ((w_snap != w_snap_final)); then
  echo "expected immediate snap with animations disabled: w_snap=$w_snap final=$w_snap_final"
  exit 1
fi

echo "tiled drag detach animated remaining windows in scrolling and dwindle, and snapped when disabled"
