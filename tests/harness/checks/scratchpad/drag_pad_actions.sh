#!/usr/bin/env bash
# harness: outputs=1
# A window the pointer is carrying is outside every pad until it is released. The scratchpad window actions refuse it
# with an error instead of moving it out from under the grab, and the release then decides: over a visible pad it stays
# a member, and a member whose pad was closed under the drag leaves the pad and lands on the workspace. Opening or
# closing the pad itself stays allowed, which is what keeps the two directions symmetric.
set -euo pipefail
source "$UMBRIEL_HARNESS_LIB"

readonly CLIENT="${UMBRIEL_UNMAP_CLIENT:-./build-debug/tests/unmap-client}"
readonly BTN_LEFT=272
readonly MEMBER=drag-actions-member
readonly TILE=drag-actions-tile
readonly SOLO=drag-actions-solo
readonly PAD_TILE_A=drag-actions-pad-tile-a
readonly PAD_TILE_B=drag-actions-pad-tile-b
readonly ONTO_TILE=drag-actions-onto-tile
readonly CLOSE_REASON="error: the window is being dragged"

cat >> "$UMBRIEL_CONFIG" <<'EOF'

[animation]
enabled = false

[animation.scratchpad]
dim = 0.5
blur = false

[colors]
backdrop = "#FFFFFFFF"

[appearance]
border_width = 0
outer_border_width = 0
corner_radius = 0

[[scratchpad]]
name = "pad"

[[scratchpad]]
name = "other"

[[scratchpad]]
name = "tiles"
layout.mode = "dwindle"

[[window_rule]]
match.title = "^drag-actions-pad-tile-"
default_scratchpad = "tiles"
EOF
"$UMBRIEL" msg config-reload > /dev/null

field() {
  window_by_title "$1" | jq -r --arg key "$2" 'if .[$key] == null then "" else (.[$key] | tostring) end'
}

box() { window_by_title "$1" | jq -r '"\(.x) \(.y)"'; }

centre() {
  window_by_title "$1" | jq -r '"\((.x + .w / 2) | floor) \((.y + .h / 2) | floor)"'
}

require() {
  local actual
  actual=$(field "$1" "$2")
  if [[ $actual != "$3" ]]; then
    echo "$1: expected $2=$3, got '$actual': $("$UMBRIEL" windows --json)"
    exit 1
  fi
}

# The window actions a drag has to refuse. `msg` prints the handler's message and exits nonzero on refusal.
refused() {
  local output
  if output=$("$UMBRIEL" msg $1 2>&1); then
    echo "$1 was accepted while its window was being dragged: $output"
    exit 1
  fi
  if [[ $output != "$CLOSE_REASON" ]]; then
    echo "$1 failed for the wrong reason: $output"
    exit 1
  fi
}

spawn_window() {
  FILL_COLOR=0xFF00FF00 "$CLIENT" "$1" 300 200 > "$UMBRIEL_RUNTIME_DIR/$1.log" 2>&1 &
  SPAWNED_PID=$!
  await_window "$1"
  "$UMBRIEL" settle
}

# Waits for a field a drop settles without a frame of its own, then settles the compositor once the frame it needs
# has been drawn.
await_field() {
  local actual=
  for _ in $(seq 100); do
    actual=$(field "$1" "$2")
    [[ $actual == "$3" ]] && break
    sleep 0.02
  done
  if [[ $actual != "$3" ]]; then
    echo "$1: expected $2=$3, got '$actual': $("$UMBRIEL" windows --json)"
    exit 1
  fi
}

# The pad takes the pointer while it is on screen, so the drag starts first and the pad opens or closes under it.
# The settle lets the compositor take the motion that turns the press into a drag, which is what makes the window
# carried.
start_drag() {
  pointer_hold 1280 720 mod logo move "$1" "$2" press "$BTN_LEFT" move "$3" "$4" -- release "$BTN_LEFT" mod none
  "$UMBRIEL" settle
}

# The drop point, computed from the pointer's travel and the grab offset the drag started with.
expect_at_drop() {
  local actual
  actual=$(box "$1")
  if [[ $actual != "$2" ]]; then
    echo "$1: expected the drop point $2, got $actual: $("$UMBRIEL" windows --json)"
    exit 1
  fi
}

# Outside a drag the same action must still work, so every refusal below is about the drag and not about the action.
spawn_window "$MEMBER"
"$UMBRIEL" msg window-focus "$(field "$MEMBER" id)" > /dev/null
"$UMBRIEL" msg window-move-to-scratchpad pad > /dev/null
"$UMBRIEL" msg scratchpad-toggle pad > /dev/null
"$UMBRIEL" settle
require "$MEMBER" scratchpad pad
"$UMBRIEL" msg window-restore-from-scratchpad pad > /dev/null
require "$MEMBER" scratchpad ""
require "$MEMBER" visible true

# Carry the member, then ask each window action to move it. None may touch it, and the release leaves it where it is.
# The control's restore dismissed the empty pad, so it is shown again before the member is carried.
"$UMBRIEL" msg window-focus "$(field "$MEMBER" id)" > /dev/null
"$UMBRIEL" msg window-move-to-scratchpad pad > /dev/null
"$UMBRIEL" msg scratchpad-toggle pad > /dev/null
"$UMBRIEL" settle
require "$MEMBER" scratchpad pad
require "$MEMBER" visible true

read -r cx cy <<< "$(centre "$MEMBER")"
start_drag "$cx" "$cy" $((cx + 80)) $((cy + 60))
before=$(box "$MEMBER")
# Membership actions, another pad's actions, workspace moves, and the layout/pin actions that would reframe or eject
# the carried member all refuse it.
for action in "window-restore-from-scratchpad pad" "window-toggle-scratchpad pad" "window-move-to-scratchpad pad" \
  "window-restore-from-scratchpad other" "window-toggle-scratchpad other" "window-move-to-scratchpad other" \
  "window-move-to-workspace 2" "window-toggle-pinned" "window-toggle-maximize" "window-cycle-primary-extent" \
  "window-set-region left" "window-clear-region" "layout-toggle-split"; do
  refused "$action"
  require "$MEMBER" scratchpad pad
  if [[ $(box "$MEMBER") != "$before" ]]; then
    echo "$action moved the dragged window: $before -> $(box "$MEMBER")"
    exit 1
  fi
done
# Pad-level actions stay available while a window is carried; only the window moves are refused.
"$UMBRIEL" msg scratchpad-focus-next pad > /dev/null
require "$MEMBER" scratchpad pad
pointer_release
"$UMBRIEL" settle
require "$MEMBER" scratchpad pad
expect_at_drop "$MEMBER" "$before"

# The same refusal for a window on the workspace: it must not be reparented into the pad under the grab, which would
# leave it hidden in a pad that is not showing. A visible pad takes the pointer itself, so hide it first.
"$UMBRIEL" msg scratchpad-toggle pad > /dev/null
"$UMBRIEL" settle
spawn_window "$TILE"
read -r tx ty <<< "$(centre "$TILE")"
tile_workspace=$(field "$TILE" workspace)
start_drag "$tx" "$ty" $((tx + 80)) $((ty + 60))
refused "window-move-to-scratchpad pad"
require "$TILE" scratchpad ""
pointer_release
"$UMBRIEL" settle
require "$TILE" scratchpad ""
require "$TILE" workspace "$tile_workspace"
require "$TILE" visible true

# Opening an empty pad mid-drag clears the keyboard focus, so the action must find the carried window through the grab
# rather than through focus. The release then lets the visible pad adopt it.
read -r tx ty <<< "$(centre "$TILE")"
tile_workspace=$(field "$TILE" workspace)
start_drag "$tx" "$ty" $((tx + 80)) $((ty + 60))
"$UMBRIEL" msg scratchpad-toggle other > /dev/null
refused "window-move-to-scratchpad pad"
pointer_release
"$UMBRIEL" settle
require "$TILE" scratchpad other
require "$TILE" visible true
"$UMBRIEL" msg window-restore-from-scratchpad other > /dev/null
"$UMBRIEL" settle
require "$TILE" scratchpad ""
require "$TILE" workspace "$tile_workspace"

# Closing the pad under a drag is allowed, and the member the pointer carries leaves with it instead of vanishing.
"$UMBRIEL" msg scratchpad-toggle pad > /dev/null
"$UMBRIEL" settle
require "$MEMBER" visible true
read -r cx cy <<< "$(centre "$MEMBER")"
start_drag "$cx" "$cy" $((cx + 80)) $((cy + 60))
"$UMBRIEL" msg scratchpad-toggle pad > /dev/null
# The hidden pad has no focused member left to name, so the carried window is still the target the actions must refuse.
refused "window-restore-from-scratchpad pad"
refused "window-toggle-scratchpad pad"
before=$(box "$MEMBER")
require "$MEMBER" scratchpad pad
require "$MEMBER" visible true
pointer_release
"$UMBRIEL" settle
require "$MEMBER" scratchpad ""
require "$MEMBER" visible true
if [[ $(field "$MEMBER" workspace) == "" ]]; then
  echo "the member left its pad without a workspace: $("$UMBRIEL" windows --json)"
  exit 1
fi
expect_at_drop "$MEMBER" "$before"

# The mirror direction: opening the pad under a drag adopts the window on release, so closing could not simply refuse.
read -r tx ty <<< "$(centre "$TILE")"
start_drag "$tx" "$ty" $((tx + 80)) $((ty + 60))
"$UMBRIEL" msg scratchpad-toggle pad > /dev/null
pointer_release
"$UMBRIEL" settle
require "$TILE" scratchpad pad
require "$TILE" visible true

# A pad showing one window at a time shows the window dropped onto it, instead of leaving its new member hidden.
"$UMBRIEL" msg window-focus "$(field "$MEMBER" id)" > /dev/null
"$UMBRIEL" msg window-move-to-scratchpad pad > /dev/null
"$UMBRIEL" settle
require "$MEMBER" scratchpad pad
"$UMBRIEL" msg scratchpad-toggle pad > /dev/null
"$UMBRIEL" settle
spawn_window "$SOLO"
read -r sx sy <<< "$(centre "$SOLO")"
start_drag "$sx" "$sy" $((sx + 80)) $((sy + 60))
"$UMBRIEL" msg scratchpad-toggle pad > /dev/null
"$UMBRIEL" msg scratchpad-window-show-next pad > /dev/null
"$UMBRIEL" settle
# One window at a time must actually be in effect before the drop, or the last assertion proves nothing.
shown=$("$UMBRIEL" windows --json | jq '[.[] | select(.scratchpad == "pad" and .visible)] | length')
if (( shown != 1 )); then
  echo "the solo pad showed $shown members before the drop: $("$UMBRIEL" windows --json)"
  exit 1
fi
pointer_release
"$UMBRIEL" settle
require "$SOLO" scratchpad pad
require "$SOLO" visible true
shown=$("$UMBRIEL" windows --json | jq '[.[] | select(.scratchpad == "pad" and .visible)] | length')
if (( shown != 1 )); then
  echo "the solo pad showed $shown members after the drop: $("$UMBRIEL" windows --json)"
  exit 1
fi

# A step the pad took under the drag is re-applied at release: the member it stopped showing must not stay drawn.
require "$SOLO" visible true
read -r sx sy <<< "$(centre "$SOLO")"
start_drag "$sx" "$sy" $((sx + 80)) $((sy + 60))
"$UMBRIEL" msg scratchpad-window-show-next pad > /dev/null
"$UMBRIEL" settle
pointer_release
"$UMBRIEL" settle
shown=$("$UMBRIEL" windows --json | jq '[.[] | select(.scratchpad == "pad" and .visible)] | length')
if (( shown != 1 )); then
  echo "the solo pad showed $shown members after a step under the drag: $("$UMBRIEL" windows --json)"
  exit 1
fi
require "$SOLO" visible false

# A member of a pad closed under the drag is outside its pad, so another visible pad adopts it on release.
"$UMBRIEL" msg scratchpad-toggle pad > /dev/null
"$UMBRIEL" msg scratchpad-toggle pad > /dev/null
"$UMBRIEL" settle
require "$MEMBER" visible true
"$UMBRIEL" msg window-focus "$(field "$MEMBER" id)" > /dev/null
"$UMBRIEL" settle
read -r mx my <<< "$(centre "$MEMBER")"
start_drag "$mx" "$my" $((mx + 80)) $((my + 60))
"$UMBRIEL" msg scratchpad-toggle pad > /dev/null
"$UMBRIEL" msg scratchpad-toggle other > /dev/null
"$UMBRIEL" settle
pointer_release
"$UMBRIEL" settle
require "$MEMBER" scratchpad other
require "$MEMBER" visible true
"$UMBRIEL" msg window-restore-from-scratchpad other > /dev/null
"$UMBRIEL" settle
require "$MEMBER" scratchpad ""

# A tiled member keeps its pad's layout, so the release that carries it out must place it on the workspace instead
# of the closed pad's layout it was aiming at.
spawn_window "$PAD_TILE_A"
spawn_window "$PAD_TILE_B"
"$UMBRIEL" msg scratchpad-toggle tiles > /dev/null
"$UMBRIEL" settle
require "$PAD_TILE_A" scratchpad tiles
require "$PAD_TILE_B" scratchpad tiles
read -r ax ay <<< "$(centre "$PAD_TILE_A")"
start_drag "$ax" "$ay" $((ax + 80)) $((ay + 60))
"$UMBRIEL" msg scratchpad-toggle tiles > /dev/null
"$UMBRIEL" settle
pointer_release
await_field "$PAD_TILE_A" scratchpad ""
await_field "$PAD_TILE_A" column 0
await_field "$PAD_TILE_A" visible true
if [[ -z $(field "$PAD_TILE_A" workspace) ]]; then
  echo "the tiled member left its pad without a workspace: $("$UMBRIEL" windows --json)"
  exit 1
fi
require "$PAD_TILE_B" scratchpad tiles
require "$PAD_TILE_B" visible false

# A pad with a layout owns the placement: the window dropped on it joins by layout order, not at the drop point.
spawn_window "$ONTO_TILE"
read -r ox oy <<< "$(centre "$ONTO_TILE")"
start_drag "$ox" "$oy" $((ox + 120)) $((oy + 160))
"$UMBRIEL" msg scratchpad-toggle tiles > /dev/null
"$UMBRIEL" settle
pointer_release
"$UMBRIEL" settle
require "$ONTO_TILE" scratchpad tiles
require "$ONTO_TILE" floating false
require "$ONTO_TILE" y "$(field "$PAD_TILE_B" y)"

# A release over a panel draws no drop target, so the workspace the window left its pad for must still place it.
readonly PANEL_CLIENT="${UMBRIEL_LAYER_CLIENT:-./build-debug/tests/layer-client}"
"$PANEL_CLIENT" HEADLESS-1 40 > "$UMBRIEL_RUNTIME_DIR/panel.log" 2>&1 &
PANEL_PID=$!
await_lines "$UMBRIEL_RUNTIME_DIR/panel.log" ready 1
"$UMBRIEL" settle
read -r bx by <<< "$(centre "$PAD_TILE_B")"
start_drag "$bx" "$by" $((bx + 120)) 20
"$UMBRIEL" msg scratchpad-toggle tiles > /dev/null
"$UMBRIEL" settle
pointer_release
await_field "$PAD_TILE_B" scratchpad ""
await_field "$PAD_TILE_B" visible true
if [[ -z $(field "$PAD_TILE_B" workspace) ]]; then
  echo "the tiled member released over a panel left without a workspace: $("$UMBRIEL" windows --json)"
  exit 1
fi
kill "$PANEL_PID" 2>/dev/null || true

echo "a dragged window refused the scratchpad window actions, stayed put until release, and the pad's own close and"
echo "open decided its membership symmetrically; a dropped window became the one its solo pad shows"
