// Verbatim port of the blur radius <-> sigma math from
// `java/org/telegram/ui/Components/blur3/DownscaleScrollableNoiseSuppressor.java`
// (lines 255-277).
//
// Upstream references the Android hwui sources:
// - frameworks/base/libs/hwui/jni/RenderEffect.cpp
// - frameworks/base/libs/hwui/utils/Blur.cpp
// The constant approximates the scaling done in the software path's
// "high quality" mode, in SkBlurMask::Blur() (1 / sqrt(3)).
//
// Computation is done in Dart doubles rather than Java float32; the
// difference is < 1e-6 for all practical radii, far below the 0.1 uniform
// dirty-epsilon used by the glass shader driver.
library;

import 'dart:math' as math;

/// `BLUR_SIGMA_SCALE` — approximates SkBlurMask::Blur()'s 1/sqrt(3).
const double kBlurSigmaScale = 0.57735;

/// `MAX_RADIUS_FOR_FAST_BLUR` — upstream comment: `convertSigmaToRadius(2) - 0.031f`.
const double kMaxRadiusForFastBlur = 2.595;

/// Port of `convertRadiusToSigma(float radius)`:
/// `radius > 0 ? BLUR_SIGMA_SCALE * radius + 0.5f : 0.0f`.
double radiusToSigma(double radius) => radius > 0 ? kBlurSigmaScale * radius + 0.5 : 0.0;

/// Port of `convertSigmaToRadius(float sigma)`:
/// `sigma > .5f ? (sigma - 0.5f) / BLUR_SIGMA_SCALE : 0.0f`.
double sigmaToRadius(double sigma) => sigma > 0.5 ? (sigma - 0.5) / kBlurSigmaScale : 0.0;

/// Port of `downscaleRadius(float radius, float scale)`:
/// `Math.max(1, convertSigmaToRadius(convertRadiusToSigma(radius) / scale))`.
///
/// This is the blur radius to apply on a backdrop that was downscaled by
/// [scale] (4x for the glass chain, 8x for the frosted chain) so that the
/// upsampled result matches a blur of [radius] at full resolution.
double downscaleRadius(double radius, double scale) =>
    math.max(1, sigmaToRadius(radiusToSigma(radius) / scale));
