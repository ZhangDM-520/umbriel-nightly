#include "view/presented_crop.h"

#include "check.h"

UMBRIEL_TEST(fullscreenCentersASmallerBuffer) {
  // A client that has not yet committed the fullscreen size sits centered in the
  // tile rather than pinned to a corner.
  CHECK_EQ(umbriel::fullscreenCenterOffset(1920, 1280), 320);
  CHECK_EQ(umbriel::fullscreenCenterOffset(1080, 800), 140);
}

UMBRIEL_TEST(fullscreenCropsAnOversizedBufferEqually) {
  // Negative offset: the buffer is wider than the output, so it loses the same
  // amount from each side instead of being scaled.
  CHECK_EQ(umbriel::fullscreenCenterOffset(1920, 2560), -320);
}

UMBRIEL_TEST(fullscreenOffsetIsZeroWithoutGeometry) {
  // A client with no committed geometry must not be shoved half an output over.
  CHECK_EQ(umbriel::fullscreenCenterOffset(1920, 0), 0);
  CHECK_EQ(umbriel::fullscreenCenterOffset(1920, -1), 0);
}

UMBRIEL_TEST(cropSelectsTheWholeBufferWhenNothingIsHidden) {
  const wlr_fbox base{0, 0, 1200, 900};
  const wlr_box geometry{0, 0, 1200, 900};
  // Presented at the committed size, fully visible: the source is the whole buffer.
  const wlr_box content{0, 0, 1200, 900};
  const wlr_box clip{0, 0, 1200, 900};

  const wlr_fbox src =
      umbriel::croppedSourceBox(base, geometry, content, clip, 1200, 900, umbriel::ShrinkSampling::Fit);

  CHECK_EQ(static_cast<int>(src.x), 0);
  CHECK_EQ(static_cast<int>(src.y), 0);
  CHECK_EQ(static_cast<int>(src.width), 1200);
  CHECK_EQ(static_cast<int>(src.height), 900);
}

UMBRIEL_TEST(cropFitsTheWholeBufferWhenAnAnimationShrinks) {
  // An animation shrinking a window means to show the whole frame smaller, which is
  // the entire point of the animation.
  const wlr_fbox base{0, 0, 1200, 900};
  const wlr_box geometry{0, 0, 1200, 900};
  const wlr_box content{0, 0, 600, 450};
  const wlr_box clip{0, 0, 600, 450};

  const wlr_fbox src =
      umbriel::croppedSourceBox(base, geometry, content, clip, 1200, 900, umbriel::ShrinkSampling::Fit);

  CHECK_EQ(static_cast<int>(src.x), 0);
  CHECK_EQ(static_cast<int>(src.y), 0);
  CHECK_EQ(static_cast<int>(src.width), 1200);
  CHECK_EQ(static_cast<int>(src.height), 900);
}

UMBRIEL_TEST(cropSamplesOneToOneWhenAPointerDragShrinks) {
  // A drag that shrinks the window shows the top-left quarter at its own scale rather
  // than filtering the whole buffer down: each presented pixel is one buffer pixel.
  const wlr_fbox base{0, 0, 1200, 900};
  const wlr_box geometry{0, 0, 1200, 900};
  const wlr_box content{0, 0, 600, 450};
  const wlr_box clip{0, 0, 600, 450};

  const wlr_fbox src =
      umbriel::croppedSourceBox(base, geometry, content, clip, 1200, 900, umbriel::ShrinkSampling::OneToOne);

  CHECK_EQ(static_cast<int>(src.x), 0);
  CHECK_EQ(static_cast<int>(src.y), 0);
  CHECK_EQ(static_cast<int>(src.width), 600);
  CHECK_EQ(static_cast<int>(src.height), 450);
}

UMBRIEL_TEST(cropScalesTheSourceWhenGrowingPastTheBuffer) {
  // Growing has no other way to fill the box, so each presented pixel covers half a
  // buffer pixel.
  const wlr_fbox base{0, 0, 1200, 900};
  const wlr_box geometry{0, 0, 1200, 900};
  const wlr_box content{0, 0, 2400, 1800};
  const wlr_box clip{0, 0, 2400, 1800};

  const wlr_fbox src =
      umbriel::croppedSourceBox(base, geometry, content, clip, 1200, 900, umbriel::ShrinkSampling::Fit);

  CHECK_EQ(static_cast<int>(src.width), 1200);
  CHECK_EQ(static_cast<int>(src.height), 900);
}

UMBRIEL_TEST(cropSelectsOnlyTheVisibleHalf) {
  // Presented at half size with only the left half on this output: a fitted shrink
  // still selects the whole buffer scaled, so half of the visible box is half of it.
  const wlr_fbox base{0, 0, 1200, 900};
  const wlr_box geometry{0, 0, 1200, 900};
  const wlr_box content{0, 0, 600, 450};
  const wlr_box clip{0, 0, 300, 450};

  const wlr_fbox src =
      umbriel::croppedSourceBox(base, geometry, content, clip, 1200, 900, umbriel::ShrinkSampling::Fit);

  CHECK_EQ(static_cast<int>(src.x), 0);
  CHECK_EQ(static_cast<int>(src.width), 600);
}

UMBRIEL_TEST(cropSamplesTheVisibleHalfOneToOneForADrag) {
  // The same half box under a grab: one buffer pixel per presented pixel, so the
  // visible half is half the buffer width.
  const wlr_fbox base{0, 0, 1200, 900};
  const wlr_box geometry{0, 0, 1200, 900};
  const wlr_box content{0, 0, 600, 450};
  const wlr_box clip{0, 0, 300, 450};

  const wlr_fbox src =
      umbriel::croppedSourceBox(base, geometry, content, clip, 1200, 900, umbriel::ShrinkSampling::OneToOne);

  CHECK_EQ(static_cast<int>(src.x), 0);
  CHECK_EQ(static_cast<int>(src.width), 300);
}

UMBRIEL_TEST(cropHonoursTheSurfaceViewport) {
  // A client with a viewport: the buffer is twice the surface size, so every
  // surface coordinate maps to two buffer pixels on top of the presented scale.
  const wlr_fbox base{0, 0, 2400, 1800};
  const wlr_box geometry{0, 0, 1200, 900};
  const wlr_box content{0, 0, 1200, 900};
  const wlr_box clip{0, 0, 600, 900};

  const wlr_fbox src =
      umbriel::croppedSourceBox(base, geometry, content, clip, 1200, 900, umbriel::ShrinkSampling::Fit);

  CHECK_EQ(static_cast<int>(src.width), 1200);
  CHECK_EQ(static_cast<int>(src.height), 1800);
}

UMBRIEL_TEST(cropNeverReachesOutsideTheBuffer) {
  // A clip extending past the surface must clamp, not sample garbage.
  const wlr_fbox base{0, 0, 1200, 900};
  const wlr_box geometry{0, 0, 1200, 900};
  const wlr_box content{0, 0, 1200, 900};
  const wlr_box clip{600, 0, 1200, 900};

  const wlr_fbox src =
      umbriel::croppedSourceBox(base, geometry, content, clip, 1200, 900, umbriel::ShrinkSampling::Fit);

  CHECK(src.x >= base.x);
  CHECK(src.x + src.width <= base.x + base.width);
  CHECK(src.y + src.height <= base.y + base.height);
}

UMBRIEL_TEST(cropIsEmptyForDegenerateInput) {
  const wlr_fbox base{0, 0, 1200, 900};
  const wlr_box geometry{0, 0, 1200, 900};
  const wlr_box clip{0, 0, 100, 100};

  // A zero-width presented box would divide by zero.
  CHECK(
      umbriel::croppedSourceBox(base, geometry, {0, 0, 0, 900}, clip, 1200, 900, umbriel::ShrinkSampling::Fit).width
      <= 0
  );
  // A surface that has committed nothing yet.
  CHECK(
      umbriel::croppedSourceBox(base, geometry, {0, 0, 600, 450}, clip, 0, 0, umbriel::ShrinkSampling::Fit).width <= 0
  );
  // A client with no geometry.
  CHECK(
      umbriel::croppedSourceBox(base, {0, 0, 0, 0}, {0, 0, 600, 450}, clip, 1200, 900, umbriel::ShrinkSampling::Fit)
          .width
      <= 0
  );
}

UMBRIEL_TEST(shrinkSamplingFollowsWhoOwnsTheBox) {
  // An opening or closing animation shrinks the whole frame, so it must keep showing all of it. Only a grab, which owns
  // the box until the pointer lets go, turns a shrink into a viewport. Getting this wrong crops every window-open
  // animation to its top-left quadrant.
  CHECK(umbriel::shrinkSampling(true) == umbriel::ShrinkSampling::OneToOne);
  CHECK(umbriel::shrinkSampling(false) == umbriel::ShrinkSampling::Fit);
}

int main() { return RUN_TESTS(); }
