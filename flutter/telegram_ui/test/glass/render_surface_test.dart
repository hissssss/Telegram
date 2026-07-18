// Ring-1/Ring-2 tests for lib/src/glass/render_glass_surface.dart,
// glass_panel.dart, and glass_fade.dart (ARCHITECTURE.md sections 3.2 and
// 3.4), golden-free by design:
//
//  * backdrop filter math — the saturation color matrix
//    (RenderNodeEffects.java / ColorMatrix.setSaturation) and the
//    downscaled-blur sigma against blur_math;
//  * layer-tree shape — frosted panels push one grouped BackdropFilterLayer
//    under a rounded clip, flat/snapshot panels push none, a forced-liquid
//    request degrades to frosted on flutter_tester (the shader guard);
//  * paint order — a recording-canvas probe asserting shadow -> tint ->
//    strokes with paths matching GlassGeometry;
//  * panel padding / forceBottomZero geometry, whole-rect hit-testing, and
//    theme-revision repaint keying;
//  * edge-fade stop tables vs the generated glass_metrics constants and the
//    dstIn ShaderMaskLayer (BlurredBackgroundWithFadeDrawable.java).

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/foundation/blur_math.dart';
import 'package:telegram_ui/src/glass/backdrop_scope.dart';
import 'package:telegram_ui/src/glass/geometry.dart';
import 'package:telegram_ui/src/glass/glass_fade.dart';
import 'package:telegram_ui/src/glass/glass_panel.dart';
import 'package:telegram_ui/src/glass/liquid_glass_settings.dart';
import 'package:telegram_ui/src/glass/presets.dart';
import 'package:telegram_ui/src/glass/render_glass_surface.dart';
import 'package:telegram_ui/src/glass/runtime_probe.dart';
import 'package:telegram_ui/src/glass/strategy.dart';
import 'package:telegram_ui/src/glass/surface_colors.dart';
import 'package:telegram_ui/src/theme/telegram_resources.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/glass_metrics.g.dart';

/// A style with every decoration turned on, theme-independent.
const GlassSurfaceStyle _testStyle = GlassSurfaceStyle(
  backgroundColor: Color(0xD9FFFFFF),
  strokeColorTop: Color(0x28FFFFFF),
  strokeColorBottom: Color(0x14FFFFFF),
  shadowColor: Color(0x20000000),
);

/// Settings whose probe never resolves: liquid requests stay conservatively
/// frosted (the flutter_tester reality).
GlassSettings _manualSettings() =>
    GlassSettings(probe: () => Completer<GlassCapability>().future);

Widget _scene({
  required GlassSettings settings,
  GlassStrategy? strategy,
  required Widget child,
}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: GlassBackdropScope(
      settings: settings,
      probeOnMount: false,
      strategy: strategy,
      child: Center(child: SizedBox(width: 200, height: 72, child: child)),
    ),
  );
}

/// Records canvas invocations without executing them.
class _RecordedCall {
  _RecordedCall(this.method, this.arguments);

  final Symbol method;
  final List<Object?> arguments;
}

class _RecordingCanvas implements Canvas {
  final List<_RecordedCall> calls = <_RecordedCall>[];

  Iterable<_RecordedCall> get drawCalls =>
      calls.where((_RecordedCall c) => c.method == #drawPath || c.method == #drawRRect);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isMethod) {
      calls.add(_RecordedCall(invocation.memberName, invocation.positionalArguments));
    }
    if (invocation.memberName == #getSaveCount) {
      return 1;
    }
    return null;
  }
}

/// A painting context whose canvas is the recording canvas — enough for the
/// layer-free (flat tier) paint path.
class _ProbePaintingContext extends PaintingContext {
  _ProbePaintingContext(this._recordingCanvas) : super(ContainerLayer(), Rect.largest);

  final _RecordingCanvas _recordingCanvas;

  @override
  Canvas get canvas => _recordingCanvas;
}

/// Direct-lookup resources over a [TelegramThemeData], for computing expected
/// preset resolutions.
class _DataResources extends TelegramResources {
  const _DataResources(this.data);

  final TelegramThemeData data;

  @override
  Color getColor(int key) => data.color(key);
}

void main() {
  group('backdrop filter math', () {
    test('saturationColorMatrix(3) matches ColorMatrix.setSaturation(3f)', () {
      // AOSP: invSat = 1 - 3 = -2; R = 0.213*invSat, G = 0.715*invSat,
      // B = 0.072*invSat; diagonal gets + sat.
      final List<double> m = saturationColorMatrix(kGlassBackdropSaturation);
      const List<double> expected = <double>[
        2.574, -1.43, -0.144, 0, 0, //
        -0.426, 1.57, -0.144, 0, 0, //
        -0.426, -1.43, 2.856, 0, 0, //
        0, 0, 0, 1, 0,
      ];
      expect(m, hasLength(20));
      for (int i = 0; i < expected.length; i++) {
        expect(m[i], closeTo(expected[i], 1e-9), reason: 'entry $i');
      }
    });

    test('saturationColorMatrix(1) is the identity', () {
      final List<double> m = saturationColorMatrix(1.0);
      const List<double> identity = <double>[
        1, 0, 0, 0, 0, //
        0, 1, 0, 0, 0, //
        0, 0, 1, 0, 0, //
        0, 0, 0, 1, 0,
      ];
      for (int i = 0; i < identity.length; i++) {
        expect(m[i], closeTo(identity[i], 1e-12), reason: 'entry $i');
      }
    });

    test('downscaledBlurSigma follows the blur_math round trip', () {
      // Above the downscale floor the round trip is exactly sigma / scale:
      // radiusToSigma(sigmaToRadius(s)) == s for s > 0.5.
      expect(
        downscaledBlurSigma(18.0, 4.0),
        moreOrLessEquals(radiusToSigma(18.0) / 4.0, epsilon: 1e-9),
      );
      expect(
        downscaledBlurSigma(kFrostedBackdropBlurRadiusDp * 3, 8.0),
        moreOrLessEquals(radiusToSigma(kFrostedBackdropBlurRadiusDp * 3) / 8.0, epsilon: 1e-9),
      );
      // Below it, the Java max(1, ...) radius floor kicks in.
      expect(downscaledBlurSigma(1.0, 8.0), moreOrLessEquals(radiusToSigma(1.0), epsilon: 1e-9));
    });

    test('glass and frosted filter chains construct off-Impeller', () {
      // ColorFilter, blur, and matrix filters are backend-independent; only
      // ImageFilter.shader is Impeller-only (and is never constructed here).
      expect(glassBackdropFilter(devicePixelRatio: 3.0), isA<ui.ImageFilter>());
      expect(frostedBackdropFilter(devicePixelRatio: 3.0), isA<ui.ImageFilter>());
      expect(
        frostedBackdropFilter(devicePixelRatio: 2.625, emulateDownscale: false),
        isA<ui.ImageFilter>(),
      );
    });
  });

  group('fade gradient math (BlurredBackgroundWithFadeDrawable)', () {
    test('default table: 5 stops over 255', () {
      final List<Color> colors = fadeGradientColors(const Color(0xFF000000), opacity: false);
      expect(colors, hasLength(kFadeStopAlphasDefault.length));
      for (int i = 0; i < colors.length; i++) {
        expect(
          colors[i].toARGB32() >>> 24,
          kFadeStopAlphasDefault[i] * 0xFF ~/ kFadeStopAlphaDivisorDefault,
          reason: 'stop $i',
        );
      }
      // Hand-computed Java values for a fully opaque source.
      expect(
        colors.map((Color c) => c.toARGB32() >>> 24).toList(),
        <int>[0x00, 0x60, 0xB0, 0xE8, 0xFF],
      );
    });

    test('opacity table: 4 stops over 285, max ~0.813 of source alpha', () {
      final List<Color> colors = fadeGradientColors(const Color(0xFF000000), opacity: true);
      expect(colors, hasLength(kFadeStopAlphasOpacity.length));
      for (int i = 0; i < colors.length; i++) {
        expect(
          colors[i].toARGB32() >>> 24,
          kFadeStopAlphasOpacity[i] * 0xFF ~/ kFadeStopAlphaDivisorOpacity,
          reason: 'stop $i',
        );
      }
      // 0x60*255/285 = 85, 0xB0*255/285 = 157, 0xE8*255/285 = 207 (Java int
      // division).
      expect(
        colors.map((Color c) => c.toARGB32() >>> 24).toList(),
        <int>[0, 85, 157, 207],
      );
    });

    test('source alpha scales every stop in Java int math', () {
      final List<Color> colors = fadeGradientColors(const Color(0x80112233), opacity: false);
      for (int i = 0; i < colors.length; i++) {
        expect(colors[i].toARGB32() >>> 24, kFadeStopAlphasDefault[i] * 0x80 ~/ 255);
        expect(colors[i].toARGB32() & 0x00FFFFFF, 0x112233, reason: 'RGB is untouched');
      }
    });

    test('stops are evenly spaced (Android positions = null)', () {
      expect(fadeGradientStops(5), <double>[0.0, 0.25, 0.5, 0.75, 1.0]);
      expect(fadeGradientStops(4), <double>[0.0, 1 / 3, 2 / 3, 1.0]);
    });

    test('gradient axis: down from the top edge, up anchored to the bottom', () {
      final (Offset downFrom, Offset downTo) = fadeGradientAxis(
        fadeHeight: 40,
        direction: GlassFadeDirection.down,
        height: 100,
      );
      expect(downFrom, Offset.zero);
      expect(downTo, const Offset(0, 40));

      // Java negative fadeHeight: offset = height + fadeHeight, transparent
      // at the bottom edge.
      final (Offset upFrom, Offset upTo) = fadeGradientAxis(
        fadeHeight: 40,
        direction: GlassFadeDirection.up,
        height: 100,
      );
      expect(upFrom, const Offset(0, 100));
      expect(upTo, const Offset(0, 60));
    });

    test('mainTabs constructor pins dp(60) and the opacity table', () {
      const GlassEdgeFade fade = GlassEdgeFade.mainTabs();
      expect(fade.fadeHeight, kFadeMainTabsHeightDp);
      expect(fade.fadeHeight, 60.0);
      expect(fade.opacity, isTrue);
      expect(fade.direction, GlassFadeDirection.down);

      const GlassEdgeFade fallback = GlassEdgeFade();
      expect(fallback.fadeHeight, kFadeDefaultHeightDp);
      expect(fallback.fadeHeight, 40.0);
      expect(fallback.opacity, isFalse);
    });
  });

  group('GlassEdgeFade widget', () {
    testWidgets('masks its child with a dstIn ShaderMaskLayer', (WidgetTester tester) async {
      await tester.pumpWidget(
        const Center(
          child: SizedBox(
            width: 300,
            height: 100,
            child: GlassEdgeFade.mainTabs(child: ColoredBox(color: Color(0xFF112233))),
          ),
        ),
      );
      final ShaderMaskLayer layer = tester.layers.whereType<ShaderMaskLayer>().single;
      expect(layer.blendMode, BlendMode.dstIn);
      // Default 800x600 test surface, centered 300x100 box.
      expect(layer.maskRect, const Rect.fromLTWH(250, 250, 300, 100));
      expect(layer.shader, isNotNull);
    });

    testWidgets('paints no mask layer without a child', (WidgetTester tester) async {
      await tester.pumpWidget(const Center(child: SizedBox(width: 10, height: 10, child: GlassEdgeFade())));
      expect(tester.layers.whereType<ShaderMaskLayer>(), isEmpty);
    });
  });

  group('tier switch and layer shape', () {
    testWidgets('frosted: one grouped BackdropFilterLayer under a rounded clip',
        (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings();
      BackdropKey? scopeKey;
      await tester.pumpWidget(
        _scene(
          settings: settings,
          child: Builder(
            builder: (BuildContext context) {
              scopeKey = BackdropGroup.of(context)?.backdropKey;
              return const GlassPanel(
                style: _testStyle,
                borderRadius: GlassRadii.all(28),
              );
            },
          ),
        ),
      );

      final RenderGlassSurface surface =
          tester.renderObject(find.byType(GlassPanel)) as RenderGlassSurface;
      expect(surface.tier, GlassTier.frosted); // Unprobed settings downgrade liquid.
      expect(surface.effectiveTier, GlassTier.frosted);
      expect(surface.strategy, GlassStrategy.backdropShader);

      final BackdropFilterLayer backdrop =
          tester.layers.whereType<BackdropFilterLayer>().single;
      expect(backdrop.filter, isNotNull);
      expect(backdrop.blendMode, BlendMode.srcOver);
      expect(scopeKey, isNotNull);
      expect(backdrop.backdropKey, same(scopeKey));

      // The frosted fill is clipped by the panel's rounded rect.
      final Offset topLeft = tester.getTopLeft(find.byType(GlassPanel));
      final GlassGeometry geometry = surface.geometryFor(topLeft & surface.size);
      final ClipRRectLayer clip = tester.layers.whereType<ClipRRectLayer>().single;
      expect(clip.clipRRect, geometry.outerRRect);
    });

    testWidgets('two panels under one scope share ONE backdrop key',
        (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: GlassBackdropScope(
            settings: settings,
            probeOnMount: false,
            child: Stack(
              children: const <Widget>[
                Positioned(
                  left: 0,
                  top: 0,
                  width: 100,
                  height: 40,
                  child: GlassPanel(style: _testStyle, borderRadius: GlassRadii.all(20)),
                ),
                Positioned(
                  left: 0,
                  top: 100,
                  width: 100,
                  height: 40,
                  child: GlassPanel(style: _testStyle, borderRadius: GlassRadii.all(20)),
                ),
              ],
            ),
          ),
        ),
      );
      final List<BackdropFilterLayer> layers =
          tester.layers.whereType<BackdropFilterLayer>().toList();
      expect(layers, hasLength(2));
      final Set<BackdropKey?> keys =
          layers.map((BackdropFilterLayer l) => l.backdropKey).toSet();
      expect(keys, hasLength(1));
      expect(keys.single, isNotNull);
    });

    testWidgets('flat tier: zero backdrop layers', (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings()..forcedTier = GlassTier.flat;
      await tester.pumpWidget(
        _scene(
          settings: settings,
          child: const GlassPanel(style: _testStyle, borderRadius: GlassRadii.all(28)),
        ),
      );
      expect(tester.layers.whereType<BackdropFilterLayer>(), isEmpty);
      final RenderGlassSurface surface =
          tester.renderObject(find.byType(GlassPanel)) as RenderGlassSurface;
      expect(surface.strategy, GlassStrategy.tintOnly);
    });

    testWidgets('snapshot strategy: zero backdrop layers', (WidgetTester tester) async {
      final GlassSettings settings = _manualSettings();
      await tester.pumpWidget(
        _scene(
          settings: settings,
          strategy: GlassStrategy.snapshotCache,
          child: const GlassPanel(style: _testStyle, borderRadius: GlassRadii.all(28)),
        ),
      );
      expect(tester.layers.whereType<BackdropFilterLayer>(), isEmpty);
    });

    testWidgets('a forced-liquid request degrades to frosted on flutter_tester',
        (WidgetTester tester) async {
      // The shader guard: ui.ImageFilter.shader would throw here, so the
      // paint tier must fall back to frosted without crashing.
      expect(ui.ImageFilter.isShaderFilterSupported, isFalse);
      final GlassSettings settings = _manualSettings()..forcedTier = GlassTier.liquid;
      await tester.pumpWidget(
        _scene(
          settings: settings,
          child: const GlassPanel(style: _testStyle, borderRadius: GlassRadii.all(28)),
        ),
      );
      final RenderGlassSurface surface =
          tester.renderObject(find.byType(GlassPanel)) as RenderGlassSurface;
      expect(surface.tier, GlassTier.liquid);
      expect(surface.effectiveTier, GlassTier.frosted);
      // The frosted fallback still renders a backdrop layer.
      expect(tester.layers.whereType<BackdropFilterLayer>(), hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('FrostedPanel pins the frosted tier', (WidgetTester tester) async {
      final GlassSettings settings = GlassSettings(probe: () async => const GlassCapability.supported());
      await settings.ensureProbed();
      await tester.pumpWidget(
        _scene(
          settings: settings,
          child: const FrostedPanel(style: _testStyle, borderRadius: GlassRadii.all(23)),
        ),
      );
      final RenderGlassSurface surface =
          tester.renderObject(find.byType(FrostedPanel)) as RenderGlassSurface;
      // The scope would resolve liquid (capability supported), but the panel
      // forces frosted.
      expect(GlassScopeData.resolve(settings: settings).tier, GlassTier.liquid);
      expect(surface.tier, GlassTier.frosted);
    });
  });

  group('paint order (recording canvas probe)', () {
    testWidgets('flat tier paints shadow, then tint, then stroke rings',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const Center(
          child: SizedBox(
            width: 200,
            height: 56,
            child: GlassPanel(
              tier: GlassTier.flat,
              style: _testStyle,
              borderRadius: GlassRadii.all(16),
            ),
          ),
        ),
      );
      final RenderGlassSurface surface =
          tester.renderObject(find.byType(GlassPanel)) as RenderGlassSurface;

      final _RecordingCanvas canvas = _RecordingCanvas();
      surface.paint(_ProbePaintingContext(canvas), Offset.zero);

      final GlassGeometry geometry = surface.geometryFor(Offset.zero & surface.size);
      final List<_RecordedCall> draws = canvas.drawCalls.toList();
      expect(draws, hasLength(4));

      // 1. Shadow: a blurred path at the shadow offset, before everything.
      expect(draws[0].method, #drawPath);
      final Path shadowPath = draws[0].arguments[0]! as Path;
      final Paint shadowPaint = draws[0].arguments[1]! as Paint;
      expect(shadowPaint.color.toARGB32(), _testStyle.shadowColor.toARGB32());
      expect(shadowPaint.maskFilter, isNotNull);
      expect(
        shadowPath.getBounds(),
        rectMoreOrLessEquals(geometry.shadowPath.getBounds(), epsilon: 1e-6),
      );

      // 2. Tint fill.
      expect(draws[1].method, #drawRRect);
      expect(draws[1].arguments[0], geometry.outerRRect);
      expect((draws[1].arguments[1]! as Paint).color.toARGB32(), _testStyle.backgroundColor.toARGB32());

      // 3-4. Stroke rings last, matching the geometry paths.
      expect(draws[2].method, #drawPath);
      expect((draws[2].arguments[1]! as Paint).color.toARGB32(), _testStyle.strokeColorTop.toARGB32());
      expect(
        (draws[2].arguments[0]! as Path).getBounds(),
        rectMoreOrLessEquals(geometry.strokeRingTop.getBounds(), epsilon: 1e-6),
      );
      expect(draws[3].method, #drawPath);
      expect((draws[3].arguments[1]! as Paint).color.toARGB32(), _testStyle.strokeColorBottom.toARGB32());
      expect(
        (draws[3].arguments[0]! as Path).getBounds(),
        rectMoreOrLessEquals(geometry.strokeRingBottom.getBounds(), epsilon: 1e-6),
      );
    });

    testWidgets('transparent shadow/strokes/tint paint nothing', (WidgetTester tester) async {
      await tester.pumpWidget(
        const Center(
          child: SizedBox(
            width: 200,
            height: 56,
            child: GlassPanel(
              tier: GlassTier.flat,
              style: GlassSurfaceStyle(), // Everything transparent.
              borderRadius: GlassRadii.all(16),
            ),
          ),
        ),
      );
      final RenderGlassSurface surface =
          tester.renderObject(find.byType(GlassPanel)) as RenderGlassSurface;
      final _RecordingCanvas canvas = _RecordingCanvas();
      surface.paint(_ProbePaintingContext(canvas), Offset.zero);
      expect(canvas.drawCalls, isEmpty);
    });
  });

  group('panel geometry, padding, hit testing, repaint keys', () {
    testWidgets('padding insets the glass; forceBottomZero splits clip and shader radii',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const Center(
          child: SizedBox(
            width: 200,
            height: 72,
            child: GlassPanel(
              tier: GlassTier.flat,
              style: _testStyle,
              borderRadius: GlassRadii.all(28),
              forceBottomZero: true,
              padding: 8,
            ),
          ),
        ),
      );
      final RenderGlassSurface surface =
          tester.renderObject(find.byType(GlassPanel)) as RenderGlassSurface;
      final GlassGeometry geometry = surface.geometryFor(Offset.zero & surface.size);
      expect(geometry.boundsWithPadding, const Rect.fromLTRB(8, 8, 192, 64));
      // Clip radii squared at the bottom, shader radii keep the un-forced
      // values (BlurredBackgroundDrawable.java:119-131).
      expect(geometry.clipRadii, const GlassRadii.all(28).withBottomZero);
      expect(geometry.shaderRadii, const GlassRadii.all(28));
      expect(geometry.shaderRadiusQuad, const <double>[28, 28, 28, 28]);
      // Square bottom clip corners produce no bottom hairline.
      expect(geometry.strokeRingBottom.getBounds().isEmpty, isTrue);
      expect(geometry.strokeRingTop.getBounds().isEmpty, isFalse);
    });

    testWidgets('the surface consumes hits over its whole rect', (WidgetTester tester) async {
      await tester.pumpWidget(
        const Center(
          child: SizedBox(
            width: 200,
            height: 72,
            child: GlassPanel(
              tier: GlassTier.flat,
              style: _testStyle,
              borderRadius: GlassRadii.all(28),
              padding: 8,
            ),
          ),
        ),
      );
      final RenderGlassSurface surface =
          tester.renderObject(find.byType(GlassPanel)) as RenderGlassSurface;
      // Corner outside the rounded pill and inside the padding margin: still
      // consumed, like the rectangular Android view.
      final BoxHitTestResult corner = BoxHitTestResult();
      expect(surface.hitTest(corner, position: const Offset(1, 1)), isTrue);
      expect(corner.path.any((HitTestEntry<Object?> e) => identical(e.target, surface)), isTrue);

      final BoxHitTestResult outside = BoxHitTestResult();
      expect(surface.hitTest(outside, position: const Offset(-1, 10)), isFalse);
    });

    testWidgets('theme revision and settings changes mark the surface for repaint',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const Center(
          child: SizedBox(
            width: 200,
            height: 72,
            child: GlassPanel(
              tier: GlassTier.flat,
              style: _testStyle,
              borderRadius: GlassRadii.all(28),
            ),
          ),
        ),
      );
      final RenderGlassSurface surface =
          tester.renderObject(find.byType(GlassPanel)) as RenderGlassSurface;
      expect(surface.debugNeedsPaint, isFalse);

      surface.themeRevision = 42;
      expect(surface.debugNeedsPaint, isTrue);
      await tester.pump();
      expect(surface.debugNeedsPaint, isFalse);

      surface.themeRevision = 42; // Unchanged revision: no repaint.
      expect(surface.debugNeedsPaint, isFalse);

      surface.settings = const LiquidGlassSettings(thickness: 32, refractIntensity: 0.4);
      expect(surface.debugNeedsPaint, isTrue);
      await tester.pump();

      surface.style = _testStyle.copyWith(backgroundColor: const Color(0xC2000000));
      expect(surface.debugNeedsPaint, isTrue);
      await tester.pump();
    });
  });

  group('theme integration', () {
    testWidgets('presets resolve against the ambient theme; tint and revision are wired',
        (WidgetTester tester) async {
      final TelegramThemeData data = TelegramThemeData.day();
      final GlassSettings settings = _manualSettings();
      await tester.pumpWidget(
        TelegramTheme(
          data: data,
          child: _scene(
            settings: settings,
            child: const GlassPanel(
              preset: GlassPresets.mainTabs,
              borderRadius: GlassRadii.all(28),
              padding: 7.666,
            ),
          ),
        ),
      );
      final RenderGlassSurface surface =
          tester.renderObject(find.byType(GlassPanel)) as RenderGlassSurface;

      // Unprobed settings resolve the scope to frosted; the preset must have
      // been resolved at that tier (tint alpha 0.76).
      final GlassSurfaceStyle expected =
          GlassPresets.mainTabs(_DataResources(data), tier: GlassTier.frosted);
      expect(surface.tier, GlassTier.frosted);
      expect(surface.style, expected);
      expect(surface.style.tintAlpha, kGlassTintAlphaFrosted);
      // The transparent default tint is wired to the resolved background.
      expect(surface.settings.tintColor, expected.backgroundColor);
      expect(surface.themeRevision, data.revision);
      expect(surface.padding, 7.666);
    });
  });
}
