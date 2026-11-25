#!/usr/bin/env bash
# A hidden scratchpad view remains rendered while its opacity falls, then leaves the scene when the fade completes;
# restoring or following it out to a workspace fades it back in, while a silent move or disabled animation snaps.
set -euo pipefail
source "$UMBRIEL_HARNESS_LIB"

readonly CLIENT="${UMBRIEL_POPUP_CLIENT:-./build-debug/tests/popup-client}"
readonly POINTER="${UMBRIEL_POINTER_CLIENT:-./build-debug/tests/pointer-client}"
readonly CLIENT_LOG="$UMBRIEL_RUNTIME_DIR/scratchpad-hide-fade-client.log"
readonly BEFORE="$UMBRIEL_RUNTIME_DIR/scratchpad-hide-before.png"
readonly DURING="$UMBRIEL_RUNTIME_DIR/scratchpad-hide-during.png"
readonly AFTER="$UMBRIEL_RUNTIME_DIR/scratchpad-hide-after.png"

sample_blue() {
  "$UMBRIEL_PIXEL_PROBE" "$1" mean 20x20+630+350 | awk '{ print $3 }'
}

sample() {
  grim "$UMBRIEL_RUNTIME_DIR/$1.png"
  sample_blue "$UMBRIEL_RUNTIME_DIR/$1.png"
}

window_field() {
  "$UMBRIEL" windows --json | jq -r --arg key "$1" '.[0] | .[$key] // ""'
}

pointer() {
  "$POINTER" 1280 720 "$@"
}

cat >> "$UMBRIEL_CONFIG" <<'EOF'

[animation]
duration_ms = 2000

[animation.windows_in]
enabled = false

[animation.workspaces]
enabled = false

[animation.scratchpad]
enabled = true # SCRATCHPAD_ANIMATION
duration_ms = 2000
curve = "linear"
dim = 0.0
blur = false

[colors]
backdrop = "#000000FF"

[appearance]
border_width = 0
outer_border_width = 0
corner_radius = 0

[[workspace]]
name = "ONE"

[[workspace]]
name = "TWO"
EOF
"$UMBRIEL" msg config-reload > /dev/null

pointer move 0 0
"$CLIENT" > "$CLIENT_LOG" 2>&1 &
await_lines "$CLIENT_LOG" ready 1

# Animation time only moves by clock-advance: 2000 ms finishes any scratchpad fade, and the mid-fade sample lands at
# 300 ms of the hide.
"$UMBRIEL" clock-freeze
"$UMBRIEL" msg window-move-to-scratchpad > /dev/null
"$UMBRIEL" clock-advance 2000
"$UMBRIEL" msg scratchpad-toggle > /dev/null
"$UMBRIEL" clock-advance 2000
grim "$BEFORE"
before_blue=$(sample_blue "$BEFORE")
if (( before_blue < 80 )); then
  echo "scratchpad window was not visible before hide: blue=$before_blue"
  exit 1
fi

# Positive control: the client is pointer-aware and the sampled point is inside the visible scratchpad window.
pointer move 630 350
for _ in $(seq 20); do
  grep -q '^pointer-enter$' "$CLIENT_LOG" && break
  sleep 0.05
done
if ! grep -q '^pointer-enter$' "$CLIENT_LOG"; then
  echo "visible scratchpad did not receive the positive-control pointer enter"
  exit 1
fi
enters_before_hide=$(grep -c '^pointer-enter$' "$CLIENT_LOG")
pointer move 0 0

"$UMBRIEL" msg scratchpad-toggle > /dev/null
"$UMBRIEL" clock-advance 300
pointer move 630 350
sleep 0.1
enters_during_fade=$(grep -c '^pointer-enter$' "$CLIENT_LOG")
if (( enters_during_fade != enters_before_hide )); then
  echo "inactive scratchpad received pointer focus during its fade"
  exit 1
fi
grim "$DURING"
during_blue=$(sample_blue "$DURING")
if (( during_blue < 40 )); then
  echo "scratchpad window disappeared before its fade completed: before=$before_blue during=$during_blue"
  exit 1
fi

"$UMBRIEL" clock-advance 2000
grim "$AFTER"
after_blue=$(sample_blue "$AFTER")
if (( after_blue > 10 )); then
  echo "scratchpad window remained after its fade completed: during=$during_blue after=$after_blue"
  exit 1
fi

show_pad() {
  "$UMBRIEL" msg scratchpad-toggle > /dev/null
  "$UMBRIEL" clock-advance 2000
  local shown
  shown=$(sample "$1")
  if (( $(awk -v blue="$shown" 'BEGIN { print blue < 80 }') )); then
    echo "scratchpad window was not visible before restore ($1): blue=$shown"
    exit 1
  fi
}

enter_pad() {
  "$UMBRIEL" msg window-move-to-scratchpad > /dev/null
  "$UMBRIEL" clock-advance 2000
  show_pad "$1"
}

assert_restore_fade() {
  local tag="$1"
  local at_once mid after
  at_once=$(sample "$tag-at-once")
  if (( $(awk -v blue="$at_once" 'BEGIN { print blue >= 10 }') )); then
    echo "$tag: restored window was drawn at full opacity instead of starting its fade: blue=$at_once"
    exit 1
  fi
  "$UMBRIEL" clock-advance 600
  mid=$(sample "$tag-mid")
  if (( $(awk -v blue="$mid" 'BEGIN { print blue <= 20 || blue >= 100 }') )); then
    echo "$tag: restore did not fade through a partial opacity: at_once=$at_once mid=$mid"
    exit 1
  fi
  "$UMBRIEL" clock-advance 2000
  after=$(sample "$tag-after")
  if (( $(awk -v blue="$after" 'BEGIN { print blue < 80 }') )); then
    echo "$tag: restored window never reached full opacity: mid=$mid after=$after"
    exit 1
  fi
  if [[ $(window_field scratchpad) != "" || $(window_field workspace) == "" ]]; then
    echo "$tag: restored window kept its scratchpad membership: $("$UMBRIEL" windows --json)"
    exit 1
  fi
  echo "$at_once -> $mid -> $after"
}

# Restoring to the current workspace fades the window in over animation.scratchpad.
show_pad restore-before
"$UMBRIEL" msg window-restore-from-scratchpad > /dev/null
restore_trace=$(assert_restore_fade restore)

# Following a scratchpad window to an inactive workspace fades it in after activating the destination.
enter_pad follow-before
"$UMBRIEL" msg window-move-to-workspace TWO > /dev/null
follow_trace=$(assert_restore_fade follow)

# A silent move to an inactive workspace snaps to full opacity instead of holding a pending fade.
enter_pad silent-before
"$UMBRIEL" msg window-move-to-workspace-silent ONE > /dev/null
"$UMBRIEL" msg workspace-switch ONE > /dev/null
silent_blue=$(sample silent-arrived)
if (( $(awk -v blue="$silent_blue" 'BEGIN { print blue < 80 }') )); then
  echo "silent move to inactive workspace did not snap to full opacity: blue=$silent_blue"
  exit 1
fi

# Control: disabling animation.scratchpad lands the restored window in one frame.
sed -i 's/^enabled = true # SCRATCHPAD_ANIMATION$/enabled = false # SCRATCHPAD_ANIMATION/' "$UMBRIEL_CONFIG"
"$UMBRIEL" msg config-reload > /dev/null
enter_pad disabled-before
"$UMBRIEL" msg window-restore-from-scratchpad > /dev/null
at_once_disabled=$(sample at-once-disabled)
if (( $(awk -v blue="$at_once_disabled" 'BEGIN { print blue < 80 }') )); then
  echo "restore still faded with the scratchpad animation disabled: blue=$at_once_disabled"
  exit 1
fi

echo "scratchpad hide/restore fade: hide $before_blue -> $during_blue -> $after_blue; restore $restore_trace; follow $follow_trace; silent $silent_blue; disabled $at_once_disabled"
