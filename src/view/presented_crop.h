#pragma once

extern "C" {
#include <umbrielfx/types/fx/clipped_region.h>
#include <wlr/util/box.h>
}

#include <algorithm>

namespace umbriel {
  // Offset centering a client buffer of `contentSize` in a fullscreen tile of `tileSize`. Negative when the buffer is
  // the larger of the two, which crops it equally on both sides; a fullscreen buffer is never scaled, because scaling a
  // client that is mid mode-change shows it at the wrong aspect ratio.
  constexpr int fullscreenCenterOffset(int tileSize, int contentSize) {
    return contentSize > 0 ? (tileSize - contentSize) / 2 : 0;
  }

  // How a presented box smaller than the committed buffer samples it. A pointer drag shows a viewport (one buffer pixel
  // per presented pixel, so text stays legible and nothing is filtered); an animation that shrinks a window means to
  // show the whole frame smaller, which is the entire point of the animation.
  enum class ShrinkSampling : uint8_t { OneToOne, Fit };

  // Who owns a presented box decides how a shrink samples it. A pointer grab owns the box for as long as it lasts, so a
  // smaller box means the user is dragging the window smaller; every other shrink is an animation, and shrinking the
  // whole frame is the point of it.
  constexpr ShrinkSampling shrinkSampling(bool pointerGrabOwnsBox) {
    return pointerGrabOwnsBox ? ShrinkSampling::OneToOne : ShrinkSampling::Fit;
  }

  // Map the visible part of an animated presentation back onto the committed buffer. `content` is the box the view is
  // drawn at and `clip` its visible part (surface coordinates); `base` is the surface's buffer source box (client
  // viewport and scale). A scene clip cannot do this: it crops 1:1 and caps at the committed surface size. Returns an
  // empty box when nothing is left, meaning the buffer should be left alone.
  constexpr wlr_fbox croppedSourceBox(
      const wlr_fbox& base, const wlr_box& geometry, const wlr_box& content, const wlr_box& clip, int surfaceWidth,
      int surfaceHeight, ShrinkSampling shrink
  ) {
    if (content.width <= 0
        || content.height <= 0
        || geometry.width <= 0
        || geometry.height <= 0
        || surfaceWidth <= 0
        || surfaceHeight <= 0) {
      return {};
    }
    // Surface px per presented px. Growing always scales, since nothing else fills a box larger than the buffer.
    // Shrinking scales or samples 1:1 depending on who owns the box.
    const double ratioW = static_cast<double>(geometry.width) / content.width;
    const double ratioH = static_cast<double>(geometry.height) / content.height;
    const double fx = shrink == ShrinkSampling::OneToOne ? std::min(1.0, ratioW) : ratioW;
    const double fy = shrink == ShrinkSampling::OneToOne ? std::min(1.0, ratioH) : ratioH;
    // Surface-local region backing the visible presented box.
    const double sx = geometry.x + (clip.x - geometry.x) * fx;
    const double sy = geometry.y + (clip.y - geometry.y) * fy;
    const double sw = clip.width * fx;
    const double sh = clip.height * fy;
    // Surface -> buffer coordinates (viewport/scale aware).
    const double bx = base.width / surfaceWidth;
    const double by = base.height / surfaceHeight;

    wlr_fbox src{base.x + sx * bx, base.y + sy * by, sw * bx, sh * by};
    if (src.x < base.x) {
      src.width -= base.x - src.x;
      src.x = base.x;
    }
    if (src.y < base.y) {
      src.height -= base.y - src.y;
      src.y = base.y;
    }
    const double maxWidth = base.x + base.width - src.x;
    const double maxHeight = base.y + base.height - src.y;
    src.width = src.width < maxWidth ? src.width : maxWidth;
    src.height = src.height < maxHeight ? src.height : maxHeight;
    if (src.width <= 0 || src.height <= 0) {
      return {};
    }
    return src;
  }
} // namespace umbriel
