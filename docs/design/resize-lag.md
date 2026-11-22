# Resize lag

Dragging a window edge moves two things that can diverge if presentation waits for client redraws: the box the compositor has decided the window should occupy, and the box it draws. Keeping both compositor-owned during an interactive grab ensures the drawn edge tracks the pointer at compositor frame cadence rather than stalling behind slow or unresponsive clients.

## What each grab presents

When `View::sizeGrabActive` holds (and `View::tiledResizeWaitsForClient` is false), `View::presentedWidth` and `View::presentedHeight` return the compositor's target box, and `View::applyPresentation` fits the latest committed client buffer into that box through `View::applyPresentedCrop`: a box larger than the buffer scales it, and a smaller one follows `shrinkSampling`. A grab owns the box for as long as it lasts, so a shrinking pointer drag shows less of the window at 1:1 instead of filtering it down; every other shrink is an animation whose purpose is to show the whole frame smaller, so it scales. `m_presentedCropActive` ensures `View::resetPresentedSurface` restores 1:1 presentation when the grab ends and the client settles.

## A floating grab presents once per frame

A motion event only asks the client for the new size (`View::requestFloatingResize`), so client latency does not depend on the frame clock, and records the box in `FloatingResizeGrab::pending`. `Output::handleFrame` calls `Cursor::flushResizeTarget` before it builds the scene, which applies the newest box exactly once through `View::applyFloatingResize` (`m_presentation.setRegion`, `setPosition`, `presentBox`) and records the trace step. Applying a box is a layout pipeline — border ring, chrome layout, clip, corner radii, shadow and blur — so doing it per event costs a pointer-rate layout for work only the last event before a frame can change: on a 200 Hz pointer the presentation ran six times a frame and now runs once. `Cursor::resetMode` flushes before ending the grab, so a release that lands between frames still settles from the box the user dragged to.

Presentation is not deferred, only coalesced: the drawn edge still tracks the pointer at frame cadence, and a burst faster than the frame clock lands on its last box rather than its first.

A client commit under the grab cannot change the presented geometry, because the grab owns the box. The scene helper resets the source box and destination size on every commit, so `View::reapplyGrabbedCrop` re-derives only the crop for the box already presented instead of re-running the whole presentation. Without it a commit snaps the frame back to the client's buffer size. After release, `FloatingGeometry::pendingSize` holds the pointer-requested box until `View::retireFloatingSizeRequest` observes a usable client response, and `View::syncFloatingResizePosition` pins the opposite edges against `View::floatingSize`.

`View::sizeGrabTracksPointer` limits the workspace-wide `Cursor::isResizingWorkspace` hold to tiled windows (`m_tiled`) so an unrelated settling floating peer still retires its own size request while a tiled drag is held.

The `windows_resize` timeline does not enter pointer resizes. A pointer resize arranges with `windows_move` suppressed (`Cursor::isResizingWorkspace`) and `View::beginResizeAnimation` disabled (`sizeGrabTracksPointer`). The spring only governs reflows that are not driven by a pointer grab.

## Configures in flight

`View::requestFloatingSize` sends at most one configure while a pointer resize has one outstanding (`FloatingSizeConfigure::throttled`), and `View::commitFloatingSize` flushes the newest pending target once `FloatingSizeConfigure::releasesThrottle` observes a settled configure serial with either a usable size change, a newly attached buffer (`supplied`), or a native Wayland surface commit acknowledging that serial (`ackedCommit`). Allowing a bufferless Wayland commit to release the active-drag throttle prevents a deadlock when a cell-snapped terminal or size-constrained client acknowledges a configure without changing dimensions or attaching a new buffer, while keeping `FloatingSizeConfigure::settled` strict so ownership handoff still waits for a drawn frame.

## Tiled resizes

A tiled grab applies the pointer delta to the layout through `ResizeGrab::applyDelta` and schedules an arrange on the next output frame, so the drawn box stretches through `View::applyPresentedCrop` toward `Workspace::presentedTiledBox` and restores 1:1 sampling on release in `Cursor::resetMode`. Setting `[animation.windows_resize] wait_for_redraw = true` (`View::tiledResizeWaitsForClient`) opts tiled drags into unstretched held switches capped by `kRedrawWaitMs` instead.

## Measuring it

The `harness` option compiles the trace described in [Resize lag trace](README.md#resize-lag-trace): per applied step, the pointer, the drawn box, the compositor's target box, and the two lags. A floating step is recorded when the frame applies the box, so the record count is the number of presentations rather than of motion events. Tiled steps record through `Cursor::traceTiledResizeStep` at the end of `Workspace::arrange` so `drawn` reflects the newly presented box rather than the pre-arrange frame. The lag arithmetic lives in `umbriel_pure` (`src/view/resize_lag.cpp`) so a unit test covers the edge selection. A check opts in with `# harness: resize-trace=true`; without it no call site writes anything.

`tests/harness/clients/unmap_client.cpp` drives delayed, non-redrawing, and quantized configures with `RESIZE_DELAY_MS`, `RESIZE_ON_STDIN`, and `RESIZE_STEP` (acknowledging unchanged quantized configures without attaching a buffer, and logging outcomes under `LOG_RESIZES`).

`tests/harness/checks/animation/resize_lag.sh` verifies six paths in one run: instant, 40 ms delayed, and non-redrawing floating sweeps (all maintaining `<= 2 px` target and drawn lag plus pixel-probed held width), a burst of moves with no pause (laid out once, landing on its newest box, which is what pins the coalescing), a `RESIZE_STEP=50` sub-step ack unlocking the next configure before release plus a held frame staying at the box after the client commits a narrower buffer plus pointer-resizing a `floatingMaximized` snapped window clearing maximize and settling, and a workspace-2 pass checking a two-window non-redrawing `dwindle` drag (zero gap, post-arrange `drawn == target`, settled client commit traces, and a `300 px` stepped commit on a floating peer settling cleanly during the held tiled drag).
