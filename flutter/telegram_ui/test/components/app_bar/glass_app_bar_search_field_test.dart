// Ring-1/Ring-2 tests for
// lib/src/components/app_bar/glass_app_bar_search_field.dart — the
// ActionBarMenuItem search layout port (checkCreateSearchField,
// ActionBarMenuItem.java:1294-1647), golden-free:
//
//  * constants against the Java values (cited per constant);
//  * palette: text/cursor `actionBarDefaultSearch`, hint
//    `actionBarDefaultSearchPlaceholder` (ActionBarMenuItem.java:1489-1493),
//    clear "X" in the bar items color -> `actionBarDefaultIcon`
//    (ActionBarMenuItem.java:1609-1614);
//  * layout: 36dp band centered, 6dp left margin, 48dp clear slot
//    (ActionBarMenuItem.java:1575, 1645);
//  * clear button: hidden at alpha 0/scale 0/rotation 45deg, 180ms
//    decelerate show/hide (checkClearButton,
//    ActionBarMenuItem.java:1617-1618, 1660-1750);
//  * clear tap empties the field and refocuses it
//    (ActionBarMenuItem.java:1621-1639);
//  * IME search submit keeps focus (ActionBarMenuItem.java:1509-1516).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/components/app_bar/glass_app_bar_search_field.dart';
import 'package:telegram_ui/src/glass/backdrop_scope.dart';
import 'package:telegram_ui/src/glass/runtime_probe.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

final TelegramThemeData _dayTheme = TelegramThemeData.day();

GlassSettings _manualSettings() =>
    GlassSettings(probe: () => Completer<GlassCapability>().future);

/// Hosts the field in the geometry the GlassAppBar socket gives it:
/// a 334x56 box (400dp bar minus the 66dp search-content left).
Widget _host({
  required Widget child,
  Size fieldSize = const Size(334, 56),
}) {
  return TelegramTheme(
    data: _dayTheme,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: GlassBackdropScope(
          settings: _manualSettings(),
          probeOnMount: false,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(size: fieldSize, child: child),
          ),
        ),
      ),
    ),
  );
}

GlassAppBarSearchFieldState _state(WidgetTester tester) =>
    tester.state<GlassAppBarSearchFieldState>(
        find.byType(GlassAppBarSearchField));

double _clearOpacity(WidgetTester tester) => tester
    .widget<Opacity>(find.descendant(
      of: find.byKey(GlassAppBarSearchField.clearButtonKey),
      matching: find.byType(Opacity),
    ))
    .opacity;

/// Rotation (radians) of the outermost Transform under the clear slot —
/// the Transform.rotate of the clear "X".
double _clearRotation(WidgetTester tester) {
  final Matrix4 m = tester
      .widget<Transform>(find
          .descendant(
            of: find.byKey(GlassAppBarSearchField.clearButtonKey),
            matching: find.byType(Transform),
          )
          .first)
      .transform;
  return math.atan2(m.storage[1], m.storage[0]);
}

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      // Field text/frame (ActionBarMenuItem.java:1491, 1575).
      expect(kGlassAppBarSearchTextSize, 18.0);
      expect(kGlassAppBarSearchFieldHeight, 36.0);
      expect(kGlassAppBarSearchFieldLeftMargin, 6.0);
      // Clear slot (ActionBarMenuItem.java:1575, 1645).
      expect(kGlassAppBarSearchClearSlotWidth, 48.0);
      // Clear show/hide (ActionBarMenuItem.java:1670, 1714, 1618).
      expect(kGlassAppBarSearchClearDuration,
          const Duration(milliseconds: 180));
      expect(kGlassAppBarSearchClearHiddenAngle, 45.0);
      // Cursor (ActionBarMenuItem.java:1489).
      expect(kGlassAppBarSearchCursorWidth, 1.5);
      // CloseProgressDrawable2 (CloseProgressDrawable2.java:36-47).
      expect(kGlassAppBarSearchClearStrokeWidth, 2.0);
      expect(kGlassAppBarSearchClearHalfSide, 8.0);
    });

    test('clear curve is DecelerateInterpolator: 1 - (1-t)^2', () {
      // ActionBarMenuItem.java:1671, 1715; Flutter's Curves.decelerate is
      // the same formula.
      expect(kGlassAppBarSearchClearCurve, Curves.decelerate);
      expect(kGlassAppBarSearchClearCurve.transform(0.5), closeTo(0.75, 1e-9));
      expect(kGlassAppBarSearchClearCurve.transform(0.25),
          closeTo(1 - 0.75 * 0.75, 1e-9));
    });
  });

  group('field styling (ActionBarMenuItem.java:1489-1498, 1557)', () {
    testWidgets('18dp text/cursor in actionBarDefaultSearch, IME search',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: const GlassAppBarSearchField(hintText: 'Search'),
      ));
      final EditableText field = tester
          .widget<EditableText>(find.byKey(GlassAppBarSearchField.fieldKey));
      final Color searchColor =
          _dayTheme.color(TelegramColorKey.actionBarDefaultSearch);
      expect(field.style.fontSize, kGlassAppBarSearchTextSize);
      expect(field.style.color, searchColor);
      expect(field.cursorColor, searchColor);
      expect(field.cursorWidth, 1.5);
      expect(field.maxLines, 1);
      // TYPE_TEXT_FLAG_NO_SUGGESTIONS (ActionBarMenuItem.java:1494-1498).
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
      // IME_ACTION_SEARCH (ActionBarMenuItem.java:1557).
      expect(field.textInputAction, TextInputAction.search);
    });

    testWidgets('hint uses actionBarDefaultSearchPlaceholder at 18dp',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: const GlassAppBarSearchField(hintText: 'Search'),
      ));
      final Text hint =
          tester.widget<Text>(find.byKey(GlassAppBarSearchField.hintKey));
      expect(hint.style!.color,
          _dayTheme.color(TelegramColorKey.actionBarDefaultSearchPlaceholder));
      expect(hint.style!.fontSize, kGlassAppBarSearchTextSize);
    });

    testWidgets('hint shows while empty and hides once text is entered',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: const GlassAppBarSearchField(hintText: 'Search'),
      ));
      double hintOpacity() => tester
          .widget<Opacity>(find.ancestor(
            of: find.byKey(GlassAppBarSearchField.hintKey),
            matching: find.byType(Opacity),
          ))
          .opacity;
      expect(hintOpacity(), 1.0);
      await tester.enterText(find.byType(EditableText), 'abc');
      await tester.pump();
      expect(hintOpacity(), 0.0);
      await tester.enterText(find.byType(EditableText), '');
      await tester.pump();
      expect(hintOpacity(), 1.0);
      await tester.pumpAndSettle();
    });
  });

  group('layout (ActionBarMenuItem.java:1575, 1645)', () {
    testWidgets('36dp band centered with a 6dp left margin',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: const GlassAppBarSearchField(hintText: 'Search'),
      ));
      final Rect field =
          tester.getRect(find.byKey(GlassAppBarSearchField.fieldKey));
      expect(field.left, kGlassAppBarSearchFieldLeftMargin);
      // Band: 36dp centered in the 56dp box -> [10, 46]; the single-line
      // editor sits start-centered inside it.
      expect(field.top, greaterThanOrEqualTo(10.0));
      expect(field.bottom, lessThanOrEqualTo(46.0));
      expect(field.center.dy, closeTo(28.0, 0.5));
      // Field stops at the 48dp clear slot.
      expect(field.right, lessThanOrEqualTo(334.0 - 48.0));

      final Rect clear =
          tester.getRect(find.byKey(GlassAppBarSearchField.clearButtonKey));
      expect(clear, const Rect.fromLTRB(334.0 - 48.0, 0, 334, 56));
    });
  });

  group('clear button (checkClearButton, ActionBarMenuItem.java:1660-1750)',
      () {
    testWidgets('hidden while empty: alpha 0, scale 0, rotation 45deg',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: const GlassAppBarSearchField(hintText: 'Search'),
      ));
      expect(_state(tester).debugClearFactor, 0.0);
      expect(_clearOpacity(tester), 0.0);
      expect(_clearRotation(tester),
          closeTo(45.0 * math.pi / 180.0, 1e-9));
    });

    testWidgets('typing animates it in over 180ms decelerate',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: const GlassAppBarSearchField(hintText: 'Search'),
      ));
      await tester.enterText(find.byType(EditableText), 'q');
      await tester.pump();

      // Half of 180ms: decelerate(0.5) = 0.75.
      await tester.pump(const Duration(milliseconds: 90));
      expect(_state(tester).debugClearFactor, closeTo(0.75, 1e-9));
      expect(_clearOpacity(tester), closeTo(0.75, 1e-9));
      // Rotation lerps 45deg -> 0 with the factor.
      expect(_clearRotation(tester),
          closeTo(0.25 * 45.0 * math.pi / 180.0, 1e-9));

      await tester.pump(const Duration(milliseconds: 100));
      expect(_state(tester).debugClearFactor, 1.0);
      expect(_clearOpacity(tester), 1.0);
      expect(_clearRotation(tester), closeTo(0.0, 1e-9));

      // Emptying animates it back out.
      await tester.enterText(find.byType(EditableText), '');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(_state(tester).debugClearFactor, closeTo(0.25, 1e-9));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_state(tester).debugClearFactor, 0.0);
    });

    testWidgets('a field mounted with text shows the clear button snapped',
        (WidgetTester tester) async {
      final TextEditingController controller =
          TextEditingController(text: 'prefilled');
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(
        child: GlassAppBarSearchField(
          controller: controller,
          hintText: 'Search',
        ),
      ));
      // First application snaps (the Java button is created directly in its
      // resting state, ActionBarMenuItem.java:1617-1618).
      expect(_state(tester).debugClearFactor, 1.0);
      expect(_clearOpacity(tester), 1.0);
    });

    testWidgets('tap clears the text and refocuses the field '
        '(ActionBarMenuItem.java:1621-1639)', (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController();
      final FocusNode focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      final List<String> changes = <String>[];
      await tester.pumpWidget(_host(
        child: GlassAppBarSearchField(
          controller: controller,
          focusNode: focusNode,
          hintText: 'Search',
          onChanged: changes.add,
        ),
      ));
      await tester.enterText(find.byType(EditableText), 'abc');
      await tester.pumpAndSettle();
      focusNode.unfocus();
      await tester.pump();
      expect(focusNode.hasFocus, isFalse);

      await tester.tap(find.byKey(GlassAppBarSearchField.clearButtonKey));
      await tester.pump();
      expect(controller.text, isEmpty);
      expect(changes.last, '');
      // searchField.requestFocus() (ActionBarMenuItem.java:1637-1638).
      expect(focusNode.hasFocus, isTrue);
      // And the button animates away.
      await tester.pumpAndSettle();
      expect(_state(tester).debugClearFactor, 0.0);
    });
  });

  group('callbacks and focus', () {
    testWidgets('onChanged mirrors typing; IME search submits keeping focus',
        (WidgetTester tester) async {
      final FocusNode focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      final List<String> changes = <String>[];
      final List<String> submits = <String>[];
      await tester.pumpWidget(_host(
        child: GlassAppBarSearchField(
          focusNode: focusNode,
          hintText: 'Search',
          onChanged: changes.add,
          onSubmitted: submits.add,
        ),
      ));
      await tester.enterText(find.byType(EditableText), 'cats');
      await tester.pumpAndSettle();
      expect(changes, <String>['cats']);
      expect(focusNode.hasFocus, isTrue);

      // The IME search action (ActionBarMenuItem.java:1509-1516): submit
      // fires and focus is kept (Java only hides the keyboard).
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(submits, <String>['cats']);
      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets('tapping the band focuses the internal node',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        child: const GlassAppBarSearchField(hintText: 'Search'),
      ));
      final GlassAppBarSearchFieldState state = _state(tester);
      expect(state.debugFocusNode.hasFocus, isFalse);
      await tester.tap(find.byKey(GlassAppBarSearchField.fieldKey),
          warnIfMissed: false);
      await tester.pump();
      expect(state.debugFocusNode.hasFocus, isTrue);
    });
  });
}
