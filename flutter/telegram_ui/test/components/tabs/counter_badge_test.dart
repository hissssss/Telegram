// Ring-1 tests for CounterBadge / CounterBadgePainter / CounterBadgeLayer /
// CounterBadgeDecoration (port of the counter pass of
// `ui/Components/glass/GlassTabView.java`, lines 98-103, 167-218, 223-227):
//
// - paint order via TestRecordingCanvas: saveLayer opens the offscreen
//   layer, the BlendMode.clear outer round rect (the punch-out ring,
//   Theme.PAINT_CLEAR at line 193) is drawn BEFORE the badge fill (line
//   209), the text after the fill, and the save/restore stack balances;
// - the decoration sandwiches the CHILD between the saveLayer and the
//   clear ring (dispatchDraw structure: saveLayer L170 -> children L173 ->
//   badge L175-213 -> restore L217), so the ring erases the icon;
// - size math (lines 181-182): height 16, width max(16, textWidth + 8),
//   inner radius 8, outer radius 9.333, gap 1.33, center (w/2 + 11, 10);
// - fill color endpoints (line 208): blendARGB(telegram_color,
//   fill_RedNormal, errorFactor) at factors 0 / 0.5 / 1;
// - appearance/error animation: 380ms EASE_OUT_QUINT (lines 68-69), scale
//   factor at t extremes (and the curve midpoint), text retained while
//   scaling out;
// - the premium variant (lines 167, 196-206): visibility pinned to 1, the
//   fill + text pass replaced by the PremiumGradient round rect (4-stop
//   premiumGradient1..4 linear shader, PremiumGradient.java:29, 258, with
//   the 96x16 matrix of lines 211-222) and the white 14dp star of
//   res/drawable/star.xml at the Java-truncated origin; the punch-out
//   ring and geometry stay identical to the non-premium pass.
//
// No glass shaders are involved: the badge is plain canvas work, so no
// GlassSettings tier forcing is needed here.

import 'dart:math' as math;
import 'dart:typed_data' show Float64List;

import 'package:flutter/foundation.dart'
    show FlutterMemoryAllocations, ObjectCreated, ObjectDisposed, ObjectEvent;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/components/tabs/counter_badge.dart';
import 'package:telegram_ui/src/components/tabs/glass_tab.dart'
    show blendArgb;
import 'package:telegram_ui/src/foundation/tg_curves.dart';
import 'package:telegram_ui/src/theme/telegram_resources.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// Day-theme defaults of the two fill keys (ThemeColors.java:98, 835).
const Color _blue = Color(0xFF229AF0);
const Color _red = Color(0xFFEB5E5E);

/// The tab-cell size used by the bar (56dp tall row, ~72dp cell).
const Size _cellSize = Size(72, 56);

CounterBadgePainter _painter({
  String text = '5',
  double visibility = 1.0,
  double errorFactor = 0.0,
  Offset? center,
}) {
  return CounterBadgePainter(
    text: text,
    color: _blue,
    errorColor: _red,
    visibility: visibility,
    errorFactor: errorFactor,
    center: center,
  );
}

/// Day-theme defaults of premiumGradient1..4 (ThemeColors defaults; see
/// default_colors.g.dart entries 718-721).
const List<Color> _premiumColors = <Color>[
  Color(0xFF55A5FF),
  Color(0xFFA767FF),
  Color(0xFFDB5C9D),
  Color(0xFFF38926),
];

CounterBadgePainter _premiumPainter({
  String text = '',
  double visibility = 1.0,
  List<Color> colors = _premiumColors,
  Offset? center,
}) {
  return CounterBadgePainter(
    text: text,
    color: _blue,
    errorColor: _red,
    visibility: visibility,
    premium: true,
    premiumGradientColors: colors,
    center: center,
  );
}

List<Symbol> _ops(TestRecordingCanvas canvas) => <Symbol>[
  for (final RecordedInvocation r in canvas.invocations)
    r.invocation.memberName,
];

/// The recorded drawRRect calls as (rrect, paint) pairs, in order.
List<(RRect, Paint)> _rrects(TestRecordingCanvas canvas) => <(RRect, Paint)>[
  for (final RecordedInvocation r in canvas.invocations)
    if (r.invocation.memberName == #drawRRect)
      (
        r.invocation.positionalArguments[0] as RRect,
        r.invocation.positionalArguments[1] as Paint,
      ),
];

/// Hosts the decoration in a tab-cell-sized box under an ambient theme.
Widget _host(TelegramThemeData theme, Widget child) {
  return TelegramTheme(
    data: theme,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: _cellSize.width,
          height: _cellSize.height,
          child: child,
        ),
      ),
    ),
  );
}

CounterBadgePainter _painterOf(WidgetTester tester) => tester
    .renderObject<RenderCounterBadge>(find.byType(CounterBadgeLayer))
    .painter!;

/// Fixed-palette resources for exact fill expectations.
class _FixedResources extends TelegramResources {
  const _FixedResources(this.colors);

  final Map<int, Color> colors;

  @override
  Color getColor(int key) => colors[key] ?? const Color(0xFF000000);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('paint order (punch-out)', () {
    test('standalone: saveLayer -> clear ring -> fill -> text -> restore',
        () {
      final CounterBadgePainter p = _painter();
      final TestRecordingCanvas canvas = TestRecordingCanvas();
      p.paint(canvas, _cellSize);

      final List<Symbol> names = _ops(canvas);

      // The offscreen layer opens first (GlassTabView.java:169-171), with a
      // plain (non-clear) paint — Java passes null — over the expanded
      // bounds.
      expect(names.first, #saveLayer);
      final Invocation saveLayer = canvas.invocations.first.invocation;
      expect(saveLayer.positionalArguments[0], p.layerBounds(_cellSize));
      expect(
        (saveLayer.positionalArguments[1] as Paint).blendMode,
        isNot(BlendMode.clear),
      );

      // The clear-blend outer rect (L193) precedes the badge fill (L209),
      // which precedes the text (L210-211).
      int clearIndex = -1;
      int fillIndex = -1;
      for (int i = 0; i < canvas.invocations.length; i++) {
        final Invocation inv = canvas.invocations[i].invocation;
        if (inv.memberName == #drawRRect) {
          final Paint paint = inv.positionalArguments[1] as Paint;
          if (paint.blendMode == BlendMode.clear) {
            clearIndex = i;
          } else {
            fillIndex = i;
          }
        }
      }
      final int paragraphIndex = names.indexOf(#drawParagraph);
      expect(clearIndex, greaterThan(0));
      expect(fillIndex, greaterThan(clearIndex));
      expect(paragraphIndex, greaterThan(fillIndex));

      // The layer closes last and the save stack balances (L213, 216-218).
      expect(names.last, #restore);
      expect(canvas.getSaveCount(), 0);

      // The fill paint carries the blended color at default src-over.
      // (Compare ARGB ints: Paint stores color components as float32, so
      // Color == against the double-precision original fails spuriously.)
      final (RRect, Paint) fill = _rrects(canvas)[1];
      expect(fill.$2.color.toARGB32(), p.fillColor.toARGB32());
      expect(fill.$2.blendMode, BlendMode.srcOver);
    });

    test('visibility 0 paints nothing (no layer, no clear)', () {
      final TestRecordingCanvas canvas = TestRecordingCanvas();
      _painter(visibility: 0.0).paint(canvas, _cellSize);
      expect(canvas.invocations, isEmpty);
    });

    test('appearance scale pivots on the badge center (L192)', () {
      final TestRecordingCanvas canvas = TestRecordingCanvas();
      _painter(visibility: 0.5).paint(canvas, _cellSize);

      final List<Invocation> transforms = <Invocation>[
        for (final RecordedInvocation r in canvas.invocations)
          if (r.invocation.memberName == #translate ||
              r.invocation.memberName == #scale)
            r.invocation,
      ];
      // canvas.scale(hasCounter, hasCounter, cx, cy):
      // translate(cx, cy) -> scale(s, s) -> translate(-cx, -cy).
      expect(transforms, hasLength(3));
      expect(transforms[0].memberName, #translate);
      expect(transforms[0].positionalArguments, <double>[47.0, 10.0]);
      expect(transforms[1].memberName, #scale);
      expect(transforms[1].positionalArguments, <double>[0.5, 0.5]);
      expect(transforms[2].memberName, #translate);
      expect(transforms[2].positionalArguments, <double>[-47.0, -10.0]);
    });

    testWidgets('decoration paints the CHILD inside the layer, before the '
        'clear ring', (tester) async {
      await tester.pumpWidget(
        _host(
          TelegramThemeData.day(),
          const CounterBadgeDecoration(
            count: '3',
            child: ColoredBox(color: Color(0xFF00FF00)),
          ),
        ),
      );

      final RenderCounterBadge ro = tester.renderObject<RenderCounterBadge>(
        find.byType(CounterBadgeLayer),
      );
      final TestRecordingCanvas canvas = TestRecordingCanvas();
      ro.paint(TestRecordingPaintingContext(canvas), Offset.zero);

      final List<Symbol> names = _ops(canvas);
      final int layerIndex = names.indexOf(#saveLayer);
      final int childIndex = names.indexOf(#drawRect); // the ColoredBox
      int clearIndex = -1;
      for (int i = 0; i < canvas.invocations.length; i++) {
        final Invocation inv = canvas.invocations[i].invocation;
        if (inv.memberName == #drawRRect &&
            (inv.positionalArguments[1] as Paint).blendMode ==
                BlendMode.clear) {
          clearIndex = i;
        }
      }
      // dispatchDraw structure: saveLayer (L170) -> children (L173) ->
      // clear ring (L193) -> restore (L217).
      expect(layerIndex, 0);
      expect(childIndex, greaterThan(layerIndex));
      expect(clearIndex, greaterThan(childIndex));
      expect(names.last, #restore);
      expect(canvas.getSaveCount(), 0);

      // Paint offset shifts the layer bounds along with everything else.
      final TestRecordingCanvas offsetCanvas = TestRecordingCanvas();
      const Offset offset = Offset(10, 20);
      ro.paint(TestRecordingPaintingContext(offsetCanvas), offset);
      expect(
        offsetCanvas.invocations.first.invocation.positionalArguments[0],
        ro.painter!.layerBounds(_cellSize).shift(offset),
      );
    });

    testWidgets('hidden decoration paints the child unwrapped', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          TelegramThemeData.day(),
          const CounterBadgeDecoration(
            count: null,
            child: ColoredBox(color: Color(0xFF00FF00)),
          ),
        ),
      );
      final RenderCounterBadge ro = tester.renderObject<RenderCounterBadge>(
        find.byType(CounterBadgeLayer),
      );
      final TestRecordingCanvas canvas = TestRecordingCanvas();
      ro.paint(TestRecordingPaintingContext(canvas), Offset.zero);
      // `if (hasCounter > 0)` gates the whole pass (GlassTabView.java:168):
      // just the child, no layer.
      expect(_ops(canvas), <Symbol>[#drawRect]);
    });

    testWidgets('composited child degrades to badge-over-child (no shared '
        'layer)', (tester) async {
      await tester.pumpWidget(
        _host(
          TelegramThemeData.day(),
          const CounterBadgeDecoration(
            count: '3',
            child: RepaintBoundary(
              child: ColoredBox(color: Color(0xFF00FF00)),
            ),
          ),
        ),
      );
      final RenderCounterBadge ro = tester.renderObject<RenderCounterBadge>(
        find.byType(CounterBadgeLayer),
      );
      final TestRecordingCanvas canvas = TestRecordingCanvas();
      ro.paint(TestRecordingPaintingContext(canvas), Offset.zero);
      final List<Symbol> names = _ops(canvas);
      // The child paints FIRST, outside the badge's own bounded layer.
      expect(names.indexOf(#drawRect), lessThan(names.indexOf(#saveLayer)));
      expect(canvas.getSaveCount(), 0);
    });
  });

  group('size math', () {
    test('widthFor: max(16, textWidth + 8) — spec values (L181-182)', () {
      expect(CounterBadge.widthFor(0), 16.0); // empty text floor
      expect(CounterBadge.widthFor(5.6), 16.0); // real-Roboto single digit
      expect(CounterBadge.widthFor(8.0), 16.0); // exact floor boundary
      expect(CounterBadge.widthFor(10.0), 18.0);
      expect(CounterBadge.widthFor(20.0), 28.0);
      expect(CounterBadge.widthFor(30.0), 38.0);
    });

    test('painted geometry for 1/2/3-digit counts', () {
      final CounterBadgePainter one = _painter(text: '1');
      final CounterBadgePainter two = _painter(text: '88');
      final CounterBadgePainter three = _painter(text: '888');

      // Width grows with the measured text and follows the exact formula.
      expect(one.textWidth, lessThan(two.textWidth));
      expect(two.textWidth, lessThan(three.textWidth));
      for (final CounterBadgePainter p in <CounterBadgePainter>[
        one,
        two,
        three,
      ]) {
        expect(p.badgeWidth, math.max(16.0, p.textWidth + 8.0));

        final TestRecordingCanvas canvas = TestRecordingCanvas();
        p.paint(canvas, _cellSize);
        final List<(RRect, Paint)> rrects = _rrects(canvas);
        expect(rrects, hasLength(2));

        final RRect outer = rrects[0].$1; // the clear ring (L185-193)
        final RRect inner = rrects[1].$1; // the fill (L194, 209)
        expect(inner.width, p.badgeWidth);
        expect(inner.height, CounterBadge.height); // 16
        expect(inner.tlRadiusX, CounterBadge.innerRadius); // 8
        expect(outer.tlRadiusX, CounterBadge.outerRadius); // 9.333
        // Outer = inner inflated by the 1.33 gap on every side (L178,
        // 185-190, 194).
        expect(outer.left, moreOrLessEquals(inner.left - 1.33));
        expect(outer.top, moreOrLessEquals(inner.top - 1.33));
        expect(outer.right, moreOrLessEquals(inner.right + 1.33));
        expect(outer.bottom, moreOrLessEquals(inner.bottom + 1.33));
        // Centered at (w/2 + 11, 10) (L179-180).
        expect(inner.center, const Offset(72 / 2 + 11, 10));
      }

      // Empty text clamps to the 16x16 circle-ish minimum.
      expect(_painter(text: '').badgeWidth, 16.0);
    });

    test('center override replaces the (w/2 + 11, 10) placement', () {
      final CounterBadgePainter p = _painter(center: const Offset(5, 7));
      expect(p.centerFor(_cellSize), const Offset(5, 7));
      expect(
        p.fillRect(_cellSize).center,
        offsetMoreOrLessEquals(const Offset(5, 7)),
      );
      // And the default remains the Java formula.
      expect(
        _painter().centerFor(const Size(100, 56)),
        const Offset(61, 10),
      );
    });

    test('layer bounds cover the badge even on a box smaller than it', () {
      const Size icon = Size(24, 24);
      final CounterBadgePainter p = _painter(text: '888');
      expect(p.layerBounds(icon), isNot(Offset.zero & icon));
      // The union covers both the box and the full punch rect (Rect.contains
      // excludes right/bottom edges, so compare edges directly).
      final Rect layer = p.layerBounds(icon);
      final Rect punch = p.punchRect(icon);
      expect(layer.right, greaterThanOrEqualTo(punch.right));
      expect(layer.top, lessThanOrEqualTo(punch.top));
      expect(layer.bottom, greaterThanOrEqualTo(punch.bottom));
      expect(layer.left, lessThanOrEqualTo(math.min(0, punch.left)));
    });

    test('counter text style is 10dp RobotoMedium white (L99-103)', () {
      expect(CounterBadge.textStyle.fontSize, 10.0);
      expect(
        CounterBadge.textStyle.fontFamily,
        'packages/telegram_ui/RobotoMedium',
      );
      expect(CounterBadge.textStyle.fontWeight, FontWeight.w500);
      expect(CounterBadge.textStyle.color, const Color(0xFFFFFFFF));
    });
  });

  group('fill color lerp (L208)', () {
    test('endpoints and midpoint of blendARGB(telegram_color, '
        'fill_RedNormal)', () {
      expect(_painter(errorFactor: 0.0).fillColor, _blue);
      expect(_painter(errorFactor: 1.0).fillColor, _red);
      expect(
        _painter(errorFactor: 0.5).fillColor,
        blendArgb(_blue, _red, 0.5),
      );
    });

    testWidgets('decoration resolves telegram_color / fill_RedNormal '
        'through the theme', (tester) async {
      final TelegramThemeData theme = TelegramThemeData.day();
      await tester.pumpWidget(
        _host(
          theme,
          const CounterBadgeDecoration(count: '7', child: SizedBox()),
        ),
      );
      final CounterBadgePainter p = _painterOf(tester);
      expect(p.color, theme.color(TelegramColorKey.telegram_color));
      expect(p.errorColor, theme.color(TelegramColorKey.fill_RedNormal));
      expect(p.text, '7');
      expect(p.errorFactor, 0.0);
      // The initial bind snaps — no appearance animation on first build.
      expect(p.visibility, 1.0);
    });

    testWidgets('explicit resources override wins over the theme', (
      tester,
    ) async {
      const TelegramResources resources = _FixedResources(<int, Color>{
        TelegramColorKey.telegram_color: Color(0xFF112233),
        TelegramColorKey.fill_RedNormal: Color(0xFF445566),
      });
      await tester.pumpWidget(
        _host(
          TelegramThemeData.day(),
          const CounterBadgeDecoration(
            count: '7',
            resources: resources,
            child: SizedBox(),
          ),
        ),
      );
      final CounterBadgePainter p = _painterOf(tester);
      expect(p.color, const Color(0xFF112233));
      expect(p.errorColor, const Color(0xFF445566));
    });
  });

  group('animation (380ms EASE_OUT_QUINT, L68-69)', () {
    testWidgets('appearance factor at t extremes and the curve midpoint', (
      tester,
    ) async {
      final TelegramThemeData theme = TelegramThemeData.day();
      Widget host(String? count) => _host(
        theme,
        CounterBadgeDecoration(count: count, child: const SizedBox()),
      );

      await tester.pumpWidget(host(null));
      expect(_painterOf(tester).visibility, 0.0);

      // Show: 0 at t=0, curve(0.5) at 190ms, exactly 1 at 380ms.
      await tester.pumpWidget(host('5'));
      await tester.pump(); // first ticker tick: elapsed 0 -> t = 0
      expect(_painterOf(tester).visibility, 0.0);

      await tester.pump(const Duration(milliseconds: 190)); // t = 0.5
      expect(
        _painterOf(tester).visibility,
        moreOrLessEquals(TgCurves.easeOutQuint.transform(0.5), epsilon: 1e-9),
      );

      await tester.pump(const Duration(milliseconds: 190)); // t = 1
      expect(_painterOf(tester).visibility, 1.0);
      await tester.pumpAndSettle();

      // Hide: the text keeps painting while the badge scales out
      // (AnimatedTextDrawable keeps its text through the hide).
      await tester.pumpWidget(host(null));
      await tester.pump(); // t = 0
      expect(_painterOf(tester).visibility, 1.0);
      await tester.pump(const Duration(milliseconds: 190)); // t = 0.5
      CounterBadgePainter p = _painterOf(tester);
      expect(p.text, '5');
      expect(
        p.visibility,
        moreOrLessEquals(
          1.0 - TgCurves.easeOutQuint.transform(0.5),
          epsilon: 1e-9,
        ),
      );
      await tester.pump(const Duration(milliseconds: 190)); // t = 1
      p = _painterOf(tester);
      expect(p.visibility, 0.0);
      await tester.pumpAndSettle();
    });

    testWidgets('error factor animates the fill between the endpoints', (
      tester,
    ) async {
      const TelegramResources resources = _FixedResources(<int, Color>{
        TelegramColorKey.telegram_color: _blue,
        TelegramColorKey.fill_RedNormal: _red,
      });
      Widget host({required bool error}) => _host(
        TelegramThemeData.day(),
        CounterBadgeDecoration(
          count: '9',
          error: error,
          resources: resources,
          child: const SizedBox(),
        ),
      );

      await tester.pumpWidget(host(error: false));
      expect(_painterOf(tester).fillColor, _blue);

      await tester.pumpWidget(host(error: true));
      await tester.pump(); // t = 0
      expect(_painterOf(tester).errorFactor, 0.0);
      expect(_painterOf(tester).fillColor, _blue);

      await tester.pump(const Duration(milliseconds: 190)); // t = 0.5
      final double midFactor = TgCurves.easeOutQuint.transform(0.5);
      expect(
        _painterOf(tester).errorFactor,
        moreOrLessEquals(midFactor, epsilon: 1e-9),
      );
      expect(
        _painterOf(tester).fillColor,
        blendArgb(_blue, _red, _painterOf(tester).errorFactor),
      );

      await tester.pump(const Duration(milliseconds: 190)); // t = 1
      expect(_painterOf(tester).errorFactor, 1.0);
      expect(_painterOf(tester).fillColor, _red);
      await tester.pumpAndSettle();
    });

    testWidgets('count change while visible swaps text without re-animating',
        (tester) async {
      final TelegramThemeData theme = TelegramThemeData.day();
      await tester.pumpWidget(
        _host(
          theme,
          const CounterBadgeDecoration(count: '5', child: SizedBox()),
        ),
      );
      expect(_painterOf(tester).visibility, 1.0);
      await tester.pumpWidget(
        _host(
          theme,
          const CounterBadgeDecoration(count: '55', child: SizedBox()),
        ),
      );
      final CounterBadgePainter p = _painterOf(tester);
      expect(p.text, '55');
      expect(p.visibility, 1.0); // no appearance re-run
      await tester.pumpAndSettle();
    });

    testWidgets(
        'animation ticks reuse one laid-out TextPainter, disposed on '
        'text change and teardown', (tester) async {
      final TelegramThemeData theme = TelegramThemeData.day();
      Widget host(String count, {bool error = false}) => _host(
        theme,
        CounterBadgeDecoration(
          count: count,
          error: error,
          child: const SizedBox(),
        ),
      );
      await tester.pumpWidget(host('5'));
      await tester.pumpAndSettle();

      int created = 0;
      int disposed = 0;
      void onEvent(ObjectEvent event) {
        if (event.object is TextPainter) {
          if (event is ObjectCreated) {
            created++;
          } else if (event is ObjectDisposed) {
            disposed++;
          }
        }
      }

      FlutterMemoryAllocations.instance.addListener(onEvent);
      addTearDown(
          () => FlutterMemoryAllocations.instance.removeListener(onEvent));

      // A full 380ms error animation rebuilds the CustomPainter every tick;
      // the laid-out TextPainter (constant text) must be reused — the old
      // code allocated one per painted frame and disposed none.
      await tester.pumpWidget(host('5', error: true));
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pumpAndSettle();
      expect(created, 0);
      expect(disposed, 0);

      // A text change swaps the cached painter, disposing the old one.
      await tester.pumpWidget(host('7', error: true));
      await tester.pumpAndSettle();
      expect(created, 1);
      expect(disposed, 1);

      // State teardown disposes the cache.
      await tester.pumpWidget(const SizedBox());
      expect(created, 1);
      expect(disposed, 2);
    });
  });

  group('premium variant (L167, 196-206)', () {
    test('constants match the Java draw (L201-205)', () {
      expect(CounterBadge.premiumGradientWidth, 96.0);
      expect(CounterBadge.premiumGradientHeight, 16.0);
      expect(CounterBadge.premiumStarSize, 14.0);
      expect(CounterBadge.premiumStarColor, const Color(0xFFFFFFFF));
      expect(CounterBadge.premiumStarViewport, 513.0);
    });

    test('gradient spec: keys, stops, axis (PremiumGradient.java:29, 35, '
        '169, 258)', () {
      expect(CounterBadge.premiumGradientKeys, const <int>[
        TelegramColorKey.premiumGradient1,
        TelegramColorKey.premiumGradient2,
        TelegramColorKey.premiumGradient3,
        TelegramColorKey.premiumGradient4,
      ]);
      // The c5 == 0 branch of chekColors: {0, 0.5f, 0.78f, 1f}.
      expect(
        CounterBadge.premiumGradientStops,
        const <double>[0.0, 0.5, 0.78, 1.0],
      );
      // (size * x1, size * y1) -> (size * x2, size * y2) with size 100,
      // (x1, y1, x2, y2) = (0, 1, 1.5, 0).
      expect(CounterBadge.premiumGradientFrom, const Offset(0.0, 100.0));
      expect(CounterBadge.premiumGradientTo, const Offset(150.0, 0.0));
    });

    test('gradient matrix: non-exactly branch for the 96x16 extent '
        '(PremiumGradient.java:211-222)', () {
      // sx = 96/100, sy = (16+16)/100, pivot (75, 50), then
      // translate(0, -32): x' = 0.96x + 3, y' = 0.32y + 2.
      final Float64List m = CounterBadge.premiumGradientMatrix().storage;
      expect(m[0], moreOrLessEquals(0.96));
      expect(m[5], moreOrLessEquals(0.32));
      expect(m[12], moreOrLessEquals(3.0)); // 75 * (1 - 0.96)
      expect(m[13], moreOrLessEquals(2.0)); // 50 * (1 - 0.32) - 32
      // No rotation/shear/z terms.
      expect(m[1], 0.0);
      expect(m[4], 0.0);
      expect(m[10], 1.0);
      expect(m[15], 1.0);

      // xOffset/yOffset post-translate (the last Java postTranslate args).
      final Float64List shifted = CounterBadge.premiumGradientMatrix(
        offset: const Offset(5.0, 7.0),
      ).storage;
      expect(shifted[12], moreOrLessEquals(8.0));
      expect(shifted[13], moreOrLessEquals(9.0));

      // And the shader builds from the 4 colors + 4 stops without throwing.
      expect(
        CounterBadge.premiumGradientShader(_premiumColors),
        isNotNull,
      );
    });

    test('star path maps the 513-viewport star into the given bounds '
        '(star.xml, GlassTabView.java:205)', () {
      const Rect bounds = Rect.fromLTWH(0, 0, 14, 14);
      final Path star = CounterBadge.premiumStarPath(bounds);
      final Rect box = star.getBounds();
      // Inside the 14x14 bounds...
      expect(box.left, greaterThanOrEqualTo(bounds.left));
      expect(box.top, greaterThanOrEqualTo(bounds.top));
      expect(box.right, lessThanOrEqualTo(bounds.right));
      expect(box.bottom, lessThanOrEqualTo(bounds.bottom));
      // ...and filling most of them (the star spans ~380/513 of the
      // viewport per axis), roughly centered.
      expect(box.width, greaterThan(9.0));
      expect(box.height, greaterThan(9.0));
      expect(box.center.dx, moreOrLessEquals(7.0, epsilon: 1.0));
      expect(box.center.dy, moreOrLessEquals(7.0, epsilon: 1.0));
      expect(star.contains(bounds.center), isTrue);

      // Translation follows the bounds origin exactly (Path stores float32
      // verbs — compare at float precision).
      const Offset shift = Offset(40, 3);
      final Rect shiftedBox =
          CounterBadge.premiumStarPath(bounds.shift(shift)).getBounds();
      expect(shiftedBox.left, moreOrLessEquals(box.left + shift.dx, epsilon: 1e-3));
      expect(shiftedBox.top, moreOrLessEquals(box.top + shift.dy, epsilon: 1e-3));
      expect(shiftedBox.width, moreOrLessEquals(box.width, epsilon: 1e-3));
      expect(shiftedBox.height, moreOrLessEquals(box.height, epsilon: 1e-3));
    });

    test('paint order: clear ring -> gradient rect -> star, no text '
        '(L193, 201-206)', () {
      final CounterBadgePainter p = _premiumPainter();
      final TestRecordingCanvas canvas = TestRecordingCanvas();
      p.paint(canvas, _cellSize);

      final List<Symbol> names = _ops(canvas);
      expect(names.first, #saveLayer);
      expect(names, isNot(contains(#drawParagraph))); // no counter text
      expect(names, contains(#drawPath)); // the star

      final List<(RRect, Paint)> rrects = _rrects(canvas);
      expect(rrects, hasLength(2));
      // The punch-out ring first (clear), then the gradient fill: a
      // shader paint, not a solid color.
      expect(rrects[0].$2.blendMode, BlendMode.clear);
      expect(rrects[1].$2.blendMode, BlendMode.srcOver);
      expect(rrects[1].$2.shader, isNotNull);

      // The star draw follows the gradient rect (L202 then L206).
      int fillIndex = -1;
      int starIndex = -1;
      for (int i = 0; i < canvas.invocations.length; i++) {
        final Invocation inv = canvas.invocations[i].invocation;
        if (inv.memberName == #drawRRect &&
            (inv.positionalArguments[1] as Paint).blendMode !=
                BlendMode.clear) {
          fillIndex = i;
        } else if (inv.memberName == #drawPath) {
          starIndex = i;
          // White untinted fill (star.xml fillColor).
          expect(
            (inv.positionalArguments[1] as Paint).color.toARGB32(),
            0xFFFFFFFF,
          );
        }
      }
      expect(starIndex, greaterThan(fillIndex));
      expect(names.last, #restore);
      expect(canvas.getSaveCount(), 0);
    });

    test('premium geometry matches the non-premium rects; star sits in the '
        '14x14 box at the truncated origin (L203-205)', () {
      final CounterBadgePainter plain = _painter(text: '1');
      final CounterBadgePainter premium = _premiumPainter(text: '1');

      final TestRecordingCanvas plainCanvas = TestRecordingCanvas();
      final TestRecordingCanvas premiumCanvas = TestRecordingCanvas();
      plain.paint(plainCanvas, _cellSize);
      premium.paint(premiumCanvas, _cellSize);

      // The ring/fill rects and radii are computed before the branch
      // (L178-194): identical between the variants.
      final List<(RRect, Paint)> plainRects = _rrects(plainCanvas);
      final List<(RRect, Paint)> premiumRects = _rrects(premiumCanvas);
      expect(premiumRects[0].$1, plainRects[0].$1);
      expect(premiumRects[1].$1, plainRects[1].$1);

      // Star bounds: cx = 72/2 + 11 = 47, cy = 10 -> origin (40, 3).
      final Path starPath = premiumCanvas.invocations
          .map((RecordedInvocation r) => r.invocation)
          .firstWhere((Invocation inv) => inv.memberName == #drawPath)
          .positionalArguments[0] as Path;
      const Rect starBox = Rect.fromLTWH(40, 3, 14, 14);
      final Rect painted = starPath.getBounds();
      expect(painted.left, greaterThanOrEqualTo(starBox.left));
      expect(painted.top, greaterThanOrEqualTo(starBox.top));
      expect(painted.right, lessThanOrEqualTo(starBox.right));
      expect(painted.bottom, lessThanOrEqualTo(starBox.bottom));

      // Fractional center: Java `(int)(cx - 7)` truncates — center
      // (20.7, 10.6) puts the star box at (13, 3), not (13.7, 3.6).
      final TestRecordingCanvas fractional = TestRecordingCanvas();
      _premiumPainter(center: const Offset(20.7, 10.6))
          .paint(fractional, _cellSize);
      final Path fractionalPath = fractional.invocations
          .map((RecordedInvocation r) => r.invocation)
          .firstWhere((Invocation inv) => inv.memberName == #drawPath)
          .positionalArguments[0] as Path;
      final Rect fractionalBox = fractionalPath.getBounds();
      expect(
        fractionalBox.left,
        moreOrLessEquals(painted.left - 27.0, epsilon: 1e-3),
      );
      expect(fractionalBox.top, moreOrLessEquals(painted.top, epsilon: 1e-3));
    });

    test('visibility is pinned to 1 (usePremiumCounter ? 1f : ..., L167)',
        () {
      final CounterBadgePainter p = _premiumPainter(visibility: 0.0);
      expect(p.effectiveVisibility, 1.0);
      // Paints at full scale even at raw visibility 0: the transform
      // collapses to nothing (scale 1 about the center is dropped only in
      // Java's matrix internals — here the recorded scale must be 1).
      final TestRecordingCanvas canvas = TestRecordingCanvas();
      p.paint(canvas, _cellSize);
      expect(_ops(canvas), contains(#drawPath));
      final Invocation scale = canvas.invocations
          .map((RecordedInvocation r) => r.invocation)
          .firstWhere((Invocation inv) => inv.memberName == #scale);
      expect(scale.positionalArguments, <double>[1.0, 1.0]);

      // Non-premium keeps honoring the raw factor.
      expect(_painter(visibility: 0.3).effectiveVisibility, 0.3);
      expect(_painter(visibility: 0.0).effectiveVisibility, 0.0);
    });

    testWidgets('decoration resolves premiumGradient1..4 through the theme '
        'and paints the badge even with a null count', (tester) async {
      final TelegramThemeData theme = TelegramThemeData.day();
      await tester.pumpWidget(
        _host(
          theme,
          const CounterBadgeDecoration(
            count: null,
            premium: true,
            child: ColoredBox(color: Color(0xFF00FF00)),
          ),
        ),
      );
      expect(tester.takeException(), isNull);

      final CounterBadgePainter p = _painterOf(tester);
      expect(p.premium, isTrue);
      expect(p.premiumGradientColors, <Color>[
        for (final int key in CounterBadge.premiumGradientKeys)
          theme.color(key),
      ]);
      // Pinned visible despite the empty count.
      expect(p.visibility, 0.0);
      expect(p.effectiveVisibility, 1.0);

      // The render object paints the shared layer + star.
      final RenderCounterBadge ro = tester.renderObject<RenderCounterBadge>(
        find.byType(CounterBadgeLayer),
      );
      final TestRecordingCanvas canvas = TestRecordingCanvas();
      ro.paint(TestRecordingPaintingContext(canvas), Offset.zero);
      final List<Symbol> names = _ops(canvas);
      expect(names.first, #saveLayer);
      expect(names, contains(#drawPath));
      expect(names, isNot(contains(#drawParagraph)));
    });

    testWidgets('non-premium decoration passes no gradient colors '
        '(unchanged path)', (tester) async {
      await tester.pumpWidget(
        _host(
          TelegramThemeData.day(),
          const CounterBadgeDecoration(count: '5', child: SizedBox()),
        ),
      );
      final CounterBadgePainter p = _painterOf(tester);
      expect(p.premium, isFalse);
      expect(p.premiumGradientColors, isNull);

      // And the non-premium paint pass still has no star and no shader.
      final TestRecordingCanvas canvas = TestRecordingCanvas();
      p.paint(canvas, _cellSize);
      expect(_ops(canvas), isNot(contains(#drawPath)));
      expect(_rrects(canvas)[1].$2.shader, isNull);
    });

    test('premium without the 4 resolved colors asserts', () {
      expect(
        () => CounterBadgePainter(
          text: '1',
          color: _blue,
          errorColor: _red,
          premium: true,
        ),
        throwsAssertionError,
      );
      expect(
        () => CounterBadgePainter(
          text: '1',
          color: _blue,
          errorColor: _red,
          premium: true,
          premiumGradientColors: const <Color>[Color(0xFF000000)],
        ),
        throwsAssertionError,
      );
    });
  });

  group('shouldRepaint', () {
    test('repaints on any input change, not on identical values', () {
      final CounterBadgePainter base = _painter();
      expect(base.shouldRepaint(_painter()), isFalse);
      expect(base.shouldRepaint(_painter(text: '6')), isTrue);
      expect(base.shouldRepaint(_painter(visibility: 0.5)), isTrue);
      expect(base.shouldRepaint(_painter(errorFactor: 0.5)), isTrue);
      expect(
        base.shouldRepaint(_painter(center: const Offset(1, 1))),
        isTrue,
      );
    });

    test('premium flag and gradient colors participate', () {
      expect(_painter().shouldRepaint(_premiumPainter(text: '5')), isTrue);
      final CounterBadgePainter premium = _premiumPainter();
      // Same colors by value (a fresh list) — no repaint.
      expect(
        premium.shouldRepaint(
          _premiumPainter(colors: List<Color>.of(_premiumColors)),
        ),
        isFalse,
      );
      // A changed gradient color repaints.
      final List<Color> changed = List<Color>.of(_premiumColors);
      changed[2] = const Color(0xFF123456);
      expect(premium.shouldRepaint(_premiumPainter(colors: changed)), isTrue);
    });
  });
}
