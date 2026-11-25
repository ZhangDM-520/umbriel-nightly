# nightly integration manifest

`nightly` is rebuilt, not appended to. Reset to `upstream/main`, merge the members below in this order with `--no-ff`, then commit this file last. This file exists only on `nightly`; drop it before any upstream-facing use.

The 2026-11-25 replay integrates 22 members on `upstream/main` at `ce2d8eed`. Every pinned tip merges individually into upstream. The refreshed resize, minimize and scratchpad branches accommodate upstream's removal of `windows_resize.wait_for_redraw`. The new rule member is row 22.

| #  | Branch                                | PR                    | Owner        | State             | Note                                                                                          |
| -- | ------------------------------------- | --------------------- | ------------ | ----------------- | --------------------------------------------------------------------------------------------- |
| 1  | `feat/cli-completions`                | #806                  | `cli`        | merged            | C7 retired at the branch                                                                      |
| 2  | `scratchpad-close-animation`          | #742                  | `scratchpad` | merged            | uses per-pad backdrop fades                                                                   |
| 3  | `feat/scratchpad-blur-strength`       | —                     | `scratchpad` | **C15**           | shares `docs/user/animation.md` with 4 and 17                                                 |
| 4  | `floating-minimize-animation`         | #733                  | `minimize`   | **C1, C2**        | standing resolutions below                                                                    |
| 5  | `titlebar-adaptive-color`             | #735                  | `titlebar`   | merged            | shares `view_lifecycle.cpp` with 16                                                           |
| 6  | `render-scale`                        | #573                  | `render`     | merged            |                                                                                               |
| 7  | `downsample-box`                      | #575                  | `render`     | **C17**           | builds on 6                                                                                   |
| 8  | `background-blur-protocol`            | #715                  | `blur`       | merged            | C3 resolved by rebase on 2026-11-19                                                           |
| 9  | `fix/drag-deform-settle-crop`         | #570                  | `drag`       | merged            | C4 resolved by rebase on 2026-11-19                                                           |
| 10 | `fix/drag-blur-latency`               | #837                  | `drag`       | merged            | ancestor of 11                                                                                |
| 11 | `fix/drag-physics-scalability`        | #840                  | `drag`       | merged            | shares `effect_registry.cpp` with 14                                                          |
| 12 | `upstream-rejected`                   | closed #559/#560/#713 | —            | merged            | shares `view_animation.cpp` with 4                                                            |
| 13 | `fix/vram-footprint`                  | #844                  | `render`     | merged            | C5 resolved in place by #844                                                                  |
| 14 | `feat/resize-physics`                 | —                     | `drag`       | **C6, C8**        | rebased onto `ce2d8eed`; ships `drag/resize_physics`                                          |
| 15 | `fix/ram-footprint`                   | —                     | `render`     | merged            | restacked on 13                                                                               |
| 16 | `fix/resize-lag`                      | —                     | `drag`       | **C8, C14**       | rebased onto `ce2d8eed`; overlaps resize physics                                              |
| 17 | `feat/scratchpad-restore-fade`        | —                     | `scratchpad` | **C9, C15**       | one commit; the empty-pad feature was dropped                                                 |
| 18 | `fix/overview-scratchpad-fade`        | #898                  | `scratchpad` | **C10, C15**      | refreshed for per-window border effects                                                       |
| 19 | `feat/scratchpad-drop-adopt`          | —                     | `scratchpad` | **C11, C14, C15** | stacked on 17; four commits                                                                   |
| 20 | `fix/tiled-drag-detach-animation`     | —                     | `drag`       | merged            | animates remaining tiles on detach; C16 updates the fixture                                   |
| 21 | `fix/floating-drag-restore-animation` | —                     | `drag`       | merged            | animates floating restore and preserves scratchpad grab positioning; C16 keeps the snap check |
| 22 | `feat/match-is-maximized`             | —                     | `rules`      | merged            | matches the scheduled maximized state                                                         |

Every row is merged. A row's `State` names the resolutions it needs on replay, not an outstanding task: the `C` recipes below are applied during the replay, and a row marked `merged` needs nothing. No row is marked stale: every row merges clean into `upstream/main`, which is the test applied before the replay starts.

## Conflicts

Ownership is decided against `upstream/main`, not against this branch. A collision is **branch-owned** when the branch also fails to merge into `upstream/main`: that branch is stale against the base it targets, and the fix belongs on it. A branch that merges into `upstream/main` cleanly is **fresh**, so the collision it makes here is between two accepted changes and is this branch's job to union. C1, C2, C6, C8, C9, C10, C11, C14, C15 and C17 are fresh-side unions and this branch resolves them; C3, C4 and C5 were stale branches and were fixed at their owners; C7 was fixed at #806.

A branch-owned conflict stops the rebuild: write the report, leave the branch at the last clean merge, push nothing. That happened once in this round's preparation: `feat/resize-physics` @ `58260d32` no longer merged into `01a7828f` because upstream `2a6f837e` removed the scratchpad presentation from `View::setMaximized`, and the branch was rebased to `38d4bf31` rather than resolved here. A `resolve:` commit here is the recorded fallback only when the owner agrees it is mechanical, and it is replaced by the rebase once the owner lands one.

### C1 — 3 × 4, `docs/user/animation.md` (standing resolution, owned by this branch)

Both rewrite the `## Event tables` table; row 4 retypes every row to insert `windows_minimize` and widens the column. #733 has not absorbed the blur row, so this recurs every rebuild.

Recipe: keep row 4's whole table verbatim, then change the scratchpad row's middle cell so it reads `dim`, `blur`, `blur_strength`. Re-pad with `node tools/remark/format.mjs docs/user/animation.md`.

### C2 — 4 × 12, `src/view/view_animation.cpp`, two hunks

**Hunk 1, `View::cancelFadeAnimation`.** Union, and the order is load-bearing: `abandonMinimizeTransition()` calls `m_fade.snap(1.0)`, so `wasAnimating` must be captured **before** the minimize block:

```cpp
void View::cancelFadeAnimation() {
  const bool wasAnimating = m_fade.animating();
  // An unmap or a fresh map abandons a minimize transition. ...
  if (minimizeConcealing()) {
    abandonMinimizeTransition();
  }
  m_minimizePhase = MinimizePhase::None;
  m_fade.snap(1.0);
  setFadeAlpha(1.0F);
  releaseOpeningPresentation();
  if (wasAnimating) {
    syncAnimationEffects();
  }
}
```

**Hunk 2, the animation tick — take OURS, never theirs.** `upstream-rejected`'s side is empty, which reads as a deletion and is not one: the block is #570's deferred release re-home, and row 12 predates it. Accepting the empty side stops a drag release from ever landing its re-home. Verify with `grep -c m_releaseRehomeArmed src/view/view_animation.cpp` returning 2. Observed: deleting the `flushReleaseRehome()` call turns `drag/physics_release_settle` and `drag/settle_pinned_dialog` red.

### C3, C4, C5 — resolved at their owners, not here

`background-blur-protocol` and `fix/drag-deform-settle-crop` were rebased onto the base on 2026-11-19, and `fix/vram-footprint` merged `fix/drag-physics-scalability` so it carries its own resolution. A rebuild merges them and applies nothing.

### C6 — 14 × this branch, resize physics union (standing resolution, owned by this branch)

Rebased onto `ce2d8eed`; the conflicts are unions with earlier members. The coalescing merge also retains `m_pointerResizeSettling` and its assignment in `finishFloatingResize` so resize physics waits for the outstanding configure.

- `view_lifecycle.cpp`: its `resetDragPhysics()` is a strict superset of the bare `m_dragPhysics = DragPhysics{}` (it also clears `m_dragResizeEdges` and unbinds the drag slot). Take its call, drop the bare assignment, and run #570's deferred re-home after it.
- `view.cpp`, `view_state.cpp`: it calls `cancelResizeGrab()` exactly where we call `flushReleaseRehome()` or `abandonMinimizeTransition()`. Union all of them; in `setFullscreen`, keep the minimize abandon block and the resize-grab block side by side.
- `view_animation.cpp`: take its tick structure (it handles grabs and resize edges) **and keep `progressed = true`** — `upstream-rejected` gates the effect sync on that flag and the branch predates the gate.
- `effect_registry.cpp`, `view.h`, `animation.md`: union. Keep the bounded-shader `else` branch and take its "dragged or resized" message; keep both method blocks; the table keeps C1 and C9's cells and gains `physics` on `windows_resize`.

### C8 — 16 × 5, 14 and 19, six files (standing resolution, owned by this branch)

`fix/resize-lag` was rebased onto `ce2d8eed`. The overlapping resize-grab changes are unions; two are **duplicates**:

- `src/view/view.cpp`, `src/view/view_state.cpp` — take **ours**, the `cancelResizeGrab();` call. Their side inlines the same guard plus `cursor->resetMode()`, which is exactly what `View::cancelResizeGrab()` (row 14) expands to.
- `src/view/view_floating.cpp` — both functions were added at the same place: keep `View::cancelResizeGrab()` and `View::applyFloatingResize()`, each with its own body.
- `src/input/cursor.h` — union the `ResizeGrab` fields: the `physics` flag (row 14) and the pending box/position (row 16).
- `src/input/cursor.cpp` — the release flushes the pending box first, calls `finishFloatingResize()` to record whether the configure is outstanding, and then calls `endResizePhysics()` for a physics grab.
- `src/view/view_lifecycle.cpp`, `View::handleCommit` — union, both closing braces. Ours syncs the adaptive title bar; theirs fires `resizeTrace::commit(*this)`. The trace stays **after** the ssd sync and inside the same `if`-chain as `hadResizeRequest`.
- `tests/harness/clients/unmap_client.cpp` — union. Take their `const ssize_t bytesRead = read(...)` binding and `bytesRead > 0` test, but keep **our** `&& state.mapped` repaint guard and the whole `b`/`t` command set with `repaintBodyOnly` / `repaintBandOnly` / `topBandEnabled` / `topBandSplit`.

Falsification, honestly reported: removing `flushResizeTarget()` leaves `animation/resize_lag`, `drag/resize_physics` and `input/client_resize_grab` green. The trace and the `unmap_client` union are covered by `animation/resize_lag` and the harness clients that drive the band commands.

### C9 — 17 × 3, 4 and 12, three files (standing resolution, owned by this branch)

`feat/scratchpad-restore-fade` is rebased on `ce2d8eed` and predates the minimize timeline (row 4) and the blur-strength row (row 3). It no longer carries the empty-pad feature, so the passive-backdrop sentences and the `transient/modal_follow` adjustment of the previous round are gone; only the restore fade remains. All hunks are unions.

- `docs/user/animation.md` — keep **our** event table, which carries `windows_minimize`, `physics` on `windows_resize` and `blur_strength` on `scratchpad`, and take only their scratchpad transition cell: `Scratchpad show and hide, a window leaving for its workspace, and its backdrop`. Re-pad with the formatter, which widens the third column.
- `src/view/view.h` — union. Their `beginScratchpadRestoreFade` keeps its position right after `animateFadeTo`; our minimize cluster follows it verbatim.
- `src/view/view_animation.cpp`, `View::syncAnimationEffects` — declare `const AnimationEvent fade = fadeEvent();` and keep **our** minimize branch on it: `if (fade == AnimationEvent::Scratchpad || !minimizeFadeActive())` binds, else `clearAnimationEffect(&target->node, fade)`. The name must be `fade`: the following `wlr_scene_node_set_animation` block reads it.
- `src/view/view_animation.cpp`, the animation tick — keep `progressed = true` first, take `animationEffect(fadeEvent())` for `m_customFade`, and keep **both** conditions in `builtInSlide`: `fadeEvent() == AnimationEvent::WindowsIn && !minimizeFadeActive()`.

Falsification: binding unconditionally (dropping the minimize branch) turns `animation/floating_minimize` red — "the window vanished instead of animating out". The `fadeEvent()` half is pinned by `animation/scratchpad_restore_fade` on its same-workspace and followed-move legs.

### C10 — 18 × 8, `src/overview/overview.cpp` (standing resolution, owned by this branch)

Keep `background-blur-protocol`'s `clientRegion` computation (it is read by `card.blur.update(...)` below), then apply the pad rule instead of a flat `1.0F`:

```cpp
card.blur.setAlpha(card.transient ? cardOpacity : 1.0F);
```

Falsification, honestly reported: pinning `card.blur.setAlpha(1.0F)` leaves all 33 `overview/` checks green. The union is still required for correctness — a pad card's backdrop blur must leave with it, and a client blur region must map into the card — so the follow-up belongs on the branch: pin the pad card's blur alpha mid-fade.

### C11 — 19 × 14, `src/workspace/scratchpad.cpp`, `refreshOutputGeometry` and `syncPads` (standing resolution, owned by this branch)

Row 19 routes "the pointer owns this view" through `isCarried()`, which is `Cursor::isDraggingView()` behind a null check. Row 14 had taught the same two predicates to spare a **resize grab** as well. A dragged view must not be reparented, and a resizing view must not have its box remapped underneath the grab.

- `refreshOutputGeometry` — restore the `Cursor* cursor` local the incoming commit deleted (row 19 removed it because `isCarried()` needs no cursor), then:

```cpp
        if (entry.scratchpad != name
            || entry.view == nullptr
            || isCarried(entry.view)
            || (cursor != nullptr && cursor->isResizingView(entry.view))) {
```

- `syncPads`, when a pad definition is removed:

```cpp
      if (Cursor* cursor = m_server->cursor(); cursor != nullptr) {
        const bool removesGrabbedView = std::ranges::any_of(views, [&](const View* view) {
          return isCarried(view) || cursor->isResizingView(view);
        });
        if (removesGrabbedView) {
          cursor->resetMode();
        }
      }
```

Do **not** widen `isCarried()` to cover resizing: it is also the admission and restore guard, where a resize grab is cancelled rather than the operation refused.

Falsification, honestly reported: the drag half is pinned by `scratchpad/drag_pad_actions`; **both resize halves are still unobserved**. Dropping both clauses leaves all 29 of `scratchpad/` and `drag/resize_physics` green, and only `-Werror` notices the orphaned `cursor` local. A usable-area change or a pad-definition reload during a resize grab is not covered anywhere. The follow-up belongs on `feat/resize-physics`.

### C12 — 17/18/19 × `docs/user/scratchpad.md` (historical recipe, clean this round)

All three rewrite the same sentence in `## Visibility and focus`. One sentence must carry the preview-card fade, the backdrop, and the no-gesture case:

> Opening the workspace overview fades every visible scratchpad and its backdrop out inside the workspace preview it covered, over the opening animation, then hides it without removing its stored windows. A gesture that never opens the overview leaves the pad as it was.

### C13 — 2 × 18, `src/workspace/scratchpad.h` (historical recipe, clean this round)

Add/add in the same public and private blocks. Keep row 2's close-snapshot API (`createCloseSnapshotLayer`, `trackCloseSnapshot`, `forgetCloseSnapshot`, `TrackedCloseSnapshot`, `m_trackedCloseSnapshots`) and row 18's overview API (`beginOverviewDismissal`, `commitOverviewDismissal`, `restoreOverviewDismissal`, `hasVisiblePad`, `backdropFadeOn`, `visibleMembersOn`, `OverviewHidden`, `m_overviewHidden`). Both inherit upstream's single `visibleOn(Output*)`, so there is no duplicate accessor this round.

### C14 — 16 × 19, `src/input/cursor.cpp` and `src/input/cursor.h` (standing resolution, owned by this branch)

Row 19 introduces `Cursor::tiledResizeTargetValid()`, which subsumes the expanded tiled-resize guard row 16 carries inline (workspace, view, session, tiled, workspace match, and both fullscreen states). Take the helper:

```cpp
    if (grab != nullptr
        && (!tiledResizeTargetValid(*grab) || grab->session->ownerLayout() != &grab->workspace->layout())) {
      resetMode();
    }
```

and in `processResizeTile` drop the checks the helper already makes, leaving `grab->workspace->group() == nullptr` and its missing output. Keep row 16's `traceTiledResizeStep`/`clearPendingTiledTrace` declarations beside it.

### C15 — refreshed per-pad backdrop state

Keep the close-animation row's `backdropOwner`, `backdropFade` and `retargetFade` APIs. In `updateDimAndBlur`, use that backdrop’s alpha for the fade and apply the configured blur strength separately. Preserve the restore transition parameters and drop-adopt's carried-window flags on `restoreView`. Keep the overview accessor and delegate it to `backdropFade`. Preserve `visibleNameOn` and `isCarried` beside the per-pad fade helpers.

### C16 — drag-animation harness fixtures

The tiled detach check uses `underfull_strip = "start"`, the current spelling from `upstream-rejected`. The older title-bar drop-zone check asserts the snapped restore box before the client commits, so its fixture disables `windows_resize`. The floating drag restore check exercises intermediate frames with resize animation enabled.

### C17 — render-scale guidance and box filtering

Retain the render-scale branch's expanded fullscreen and Xwayland guidance in `docs/user/outputs.md`, together with the downsample-box branch's filtering description and layer-rule guidance.

The resize-lag member's `docs/design/resize-lag.md` still mentioned the removed `wait_for_redraw` setting and helper. Remove those obsolete references in nightly until the member absorbs the correction.

## Gate

The gate is local, and it is the only gate: `just build debug`, the unit binaries, the harness over every area a row touches, `just format-docs-check`, and `clang-tidy` with the lint recipe's own flags. Record the command and its output in the round's log, and report the reds that reproduce on `upstream/main` separately from the ones the round introduced.

**This fork runs no CI, by decision.** GitHub Actions is disabled on `ZhangDM-520/umbriel-nightly` — `gh workflow run` and the raw dispatch endpoint both answer HTTP 422 "Actions has been disabled for this repository", the workflows still report `active`, and `allowed_actions` is `local_only`. The owner's ruling on 2026-11-21: the fork's CI is not worth repairing, because this branch is never proposed from the fork — it exists to be rebuilt locally, and the work reaches CI through each member's own pull request upstream. So a claim about this branch is a claim about a local run, and nothing here is CI-vouched. Do not report a check as pending, and do not treat a missing run as a failure.

Two host traps make the local gate narrower than its recipe: `tests/eis-socket-test` and `tests/global-shortcuts-store-test` fail to link under the GCC 17 snapshot (`std::__shared_ptr<...::_Dir>` undefined), and `just lint` builds those first. Use `meson test --no-rebuild --exclude 'umbriel:eis-socket' --exclude 'umbriel:global-shortcuts-store'` and run `clang-tidy -p build-debug` directly. Build the test binaries with `ninja -k 0` so the two link failures do not hide the rest; a stale test binary reports a phantom doc-sync failure.

## Rules

- Fork-only. Never pushed upstream, never proposed.
- Member branches are the source of truth. A fix goes on the member branch; this branch carries merges and, only by recorded fallback, `resolve:` commits.
- A conflict pauses the rebuild. Write the report, leave the branch at the last clean merge, push nothing.
- Never `git add -A`. Never rewrite a member branch from here. One writer per checkout: `nightly` lives in its own worktree.
- Rebuild on `upstream/main`, never rebase onto `upstream-rejected`.
- A force-pushed member costs nothing: that is what the rebuild lifecycle is for.
- `Owner` names the thread that maintains the branch, not a person. The standing ownership contract — surface, gate, conflict shape, decision log — is `docs/branch-ownership.md`, committed beside this file by the same bookkeeping commit, because a rebuild starts from `upstream/main` and neither file exists there.
- A member that lands upstream is deleted from this table outright; do not keep its row as history. #745 and #820 went that way.
- A row stacked on another must follow it: row 19 is cut on row 17, so merging it after row 17 keeps its merge base inside this branch and the scratchpad and resize guards retain their documented unions.
- A collision is judged against `upstream/main`, not against this branch. Merge the member into `upstream/main` with `git merge-tree --write-tree`; a clean result makes the branch fresh and the collision here ours to union, and a colliding result makes it stale and sends the fix to its owner. A branch based on an older commit is still fresh if that merge is clean.
