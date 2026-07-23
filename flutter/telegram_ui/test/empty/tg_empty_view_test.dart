// Tests for lib/src/empty/tg_empty_view.dart (PLAN_UIKIT.md S3),
// golden-free:
//
//  * constants against StickerEmptyView.java (slot 117 :124, margins
//    12/8/16/28 :125-127, frame 46/30 :128, fade 150ms :366-380, scales
//    0.8/0.5 :133, 213);
//  * slots render with the TgTextStyles roles (title 20/RobotoMedium
//    :108-112, subtitle 14/400 :114-119) and the Java layout gaps;
//  * the 150ms loading↔content crossfade — content alpha/scale against
//    progress alpha/scale, progress unmounted when fully hidden (:222-227);
//  * the default TgRadialProgress vs the custom progress slot (:78-85,
//    130-136);
//  * theme key resolution + resources override, both directions;
//  * button wiring (round TgButton :121, 127) and pointer-ignoring while
//    loading.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/buttons/tg_button.dart';
import 'package:telegram_ui/src/empty/tg_empty_view.dart';
import 'package:telegram_ui/src/foundation/tg_text_styles.dart';
import 'package:telegram_ui/src/progress/tg_radial_progress.dart';
import 'package:telegram_ui/src/theme/resources_override.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// Shared day theme (constructing the 777-key palette once).
final TelegramThemeData _dayTheme = TelegramThemeData.day();

Widget _host(Widget child) {
  return TelegramTheme(
    data: _dayTheme,
    child: Directionality(textDirection: TextDirection.ltr, child: child),
  );
}

Opacity _opacityAbove(WidgetTester tester, Finder finder) {
  return tester.widget<Opacity>(
    find.ancestor(of: finder, matching: find.byType(Opacity)).first,
  );
}

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      expect(kTgEmptyViewImageSize, 117.0); // StickerEmptyView.java:124
      expect(kTgEmptyViewTitleTopMargin, 12.0); // :125
      expect(kTgEmptyViewSubtitleTopMargin, 8.0); // :126
      expect(kTgEmptyViewButtonTopMargin, 16.0); // :127
      expect(kTgEmptyViewButtonSideMargin, 28.0); // :127
      expect(kTgEmptyViewSideMargin, 46.0); // :128
      expect(kTgEmptyViewBottomMargin, 30.0); // :128
      expect(
        kTgEmptyViewFadeDuration,
        const Duration(milliseconds: 150),
      ); // :366-380
      expect(kTgEmptyViewContentHiddenScale, 0.8); // :213, 366
      expect(kTgEmptyViewProgressHiddenScale, 0.5); // :133, 229
    });
  });

  group('slots and styles', () {
    testWidgets('all slots render with the Java metrics',
        (WidgetTester tester) async {
      const Key imageKey = Key('image');
      await tester.pumpWidget(_host(TgEmptyView(
        image: Container(key: imageKey),
        title: 'No results',
        subtitle: 'Try a different search',
        buttonText: 'Clear search',
        onButtonPressed: () {},
      )));

      // 117×117 image slot (StickerEmptyView.java:124).
      expect(tester.getSize(find.byKey(imageKey)), const Size(117, 117));

      // Vertical rhythm: image → 12 → title → 8 → subtitle → 16 → button
      // (StickerEmptyView.java:125-127).
      final Rect image = tester.getRect(find.byKey(imageKey));
      final Rect title = tester.getRect(find.text('No results'));
      final Rect subtitle = tester.getRect(find.text('Try a different search'));
      final Rect button = tester.getRect(find.byType(TgButton));
      expect(title.top - image.bottom, moreOrLessEquals(12.0, epsilon: 0.001));
      expect(subtitle.top - title.bottom, moreOrLessEquals(8.0, epsilon: 0.001));
      expect(button.top - subtitle.bottom,
          moreOrLessEquals(16.0, epsilon: 0.001));

      // Button: 48dp, inset 46 + 28 per side (StickerEmptyView.java:127-128).
      expect(button.height, 48.0);
      expect(button.left, 46.0 + 28.0);
      expect(button.right, 800.0 - 46.0 - 28.0);
      // setRound() = the 24dp stadium (StickerEmptyView.java:121).
      expect(
        tester.widget<TgButton>(find.byType(TgButton)).radius,
        kTgButtonRoundRadius,
      );

      // Content centered with the 30dp bottom margin shifting it up 15dp
      // (StickerEmptyView.java:128).
      final Rect column = tester.getRect(find.byType(Column));
      expect(column.center.dy, moreOrLessEquals(300.0 - 15.0, epsilon: 0.001));
    });

    testWidgets('title uses the TgTextStyles.title role (20/RobotoMedium, '
        'windowBackgroundWhiteBlackText)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgEmptyView(title: 'Empty')));
      final TextStyle style = tester.widget<Text>(find.text('Empty')).style!;
      expect(style.fontSize, TgTextStyles.title.fontSize); // 20 (:111)
      expect(style.fontWeight, FontWeight.w500); // bold() (:108)
      expect(style.fontFamily, 'packages/telegram_ui/RobotoMedium');
      expect(
        style.color,
        _dayTheme.color(TelegramColorKey.windowBackgroundWhiteBlackText),
      ); // :109-110
    });

    testWidgets('subtitle uses the TgTextStyles.subtitle role (14/400, '
        'windowBackgroundWhiteGrayText)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgEmptyView(subtitle: 'Sub')));
      final TextStyle style = tester.widget<Text>(find.text('Sub')).style!;
      expect(style.fontSize, TgTextStyles.subtitle.fontSize); // 14 (:118)
      expect(style.fontWeight, FontWeight.w400);
      expect(
        style.color,
        _dayTheme.color(TelegramColorKey.windowBackgroundWhiteGrayText),
      ); // :115-116
    });

    testWidgets('omitted slots do not build', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgEmptyView(title: 'Only title')));
      expect(find.byType(TgButton), findsNothing); // GONE default (:122)
      expect(find.byType(TgRadialProgress), findsNothing);
    });
  });

  group('loading crossfade (StickerEmptyView.java:354-414)', () {
    testWidgets('shows content and no spinner at rest',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgEmptyView(title: 'Empty')));
      expect(_opacityAbove(tester, find.text('Empty')).opacity, 1.0);
      expect(find.byType(TgRadialProgress), findsNothing);
    });

    testWidgets('crossfades over 150ms and back, unmounting the spinner',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgEmptyView(title: 'Empty')));
      final TgEmptyViewState state =
          tester.state<TgEmptyViewState>(find.byType(TgEmptyView));

      await tester
          .pumpWidget(_host(const TgEmptyView(title: 'Empty', loading: true)));
      // Halfway: AccelerateDecelerate(0.5) = 0.5 (:366-380, stock
      // interpolator).
      await tester.pump(const Duration(milliseconds: 75));
      expect(state.debugProgressFactor, moreOrLessEquals(0.5, epsilon: 0.001));
      expect(find.byType(TgRadialProgress), findsOneWidget);
      expect(
        _opacityAbove(tester, find.text('Empty')).opacity,
        moreOrLessEquals(0.5, epsilon: 0.001),
      );

      // Settled: content alpha 0 / scale 0.8, progress alpha 1 (:213, 366).
      await tester.pump(const Duration(milliseconds: 75));
      expect(state.debugProgressFactor, 1.0);
      expect(_opacityAbove(tester, find.text('Empty')).opacity, 0.0);
      expect(
        _opacityAbove(tester, find.byType(TgRadialProgress)).opacity,
        1.0,
      );

      // Back: 150ms out, then the spinner layer unmounts (GONE-on-end,
      // :222-227).
      await tester.pumpWidget(_host(const TgEmptyView(title: 'Empty')));
      await tester.pump(const Duration(milliseconds: 75));
      expect(find.byType(TgRadialProgress), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 75));
      expect(state.debugProgressFactor, 0.0);
      expect(find.byType(TgRadialProgress), findsNothing);
      expect(_opacityAbove(tester, find.text('Empty')).opacity, 1.0);
    });

    testWidgets('progress scales from 0.5 toward 1 while appearing (:132-134)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgEmptyView(title: 'Empty')));
      await tester
          .pumpWidget(_host(const TgEmptyView(title: 'Empty', loading: true)));
      await tester.pump(const Duration(milliseconds: 75));
      final Transform transform = tester.widget<Transform>(
        find
            .ancestor(
              of: find.byType(TgRadialProgress),
              matching: find.byType(Transform),
            )
            .first,
      );
      // scale = lerp(0.5, 1, 0.5) = 0.75.
      expect(transform.transform.getMaxScaleOnAxis(),
          moreOrLessEquals(0.75, epsilon: 0.001));
    });

    testWidgets('custom progress slot replaces TgRadialProgress (:78-85)',
        (WidgetTester tester) async {
      const Key progressKey = Key('progress');
      await tester.pumpWidget(_host(const TgEmptyView(
        title: 'Empty',
        loading: true,
        progress: SizedBox(key: progressKey, width: 20, height: 20),
      )));
      expect(find.byKey(progressKey), findsOneWidget);
      expect(find.byType(TgRadialProgress), findsNothing);
    });

    testWidgets('content ignores pointers while loading',
        (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(_host(TgEmptyView(
        title: 'Empty',
        buttonText: 'Retry',
        onButtonPressed: () => taps++,
        loading: true,
      )));
      final IgnorePointer ignore = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byType(TgButton),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(ignore.ignoring, isTrue);
      await tester.tap(find.byType(TgButton), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, 0);
    });

    testWidgets('button taps fire when not loading',
        (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(_host(TgEmptyView(
        title: 'Empty',
        buttonText: 'Retry',
        onButtonPressed: () => taps++,
      )));
      await tester.tap(find.byType(TgButton));
      // Let the press-release overshoot settle (no pending timers).
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, 1);
    });
  });

  group('theme keys', () {
    testWidgets('custom color keys resolve (`setColors`, :193-200)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgEmptyView(
        title: 'Empty',
        titleColorKey: TelegramColorKey.windowBackgroundWhiteGrayText,
      )));
      expect(
        tester.widget<Text>(find.text('Empty')).style!.color,
        _dayTheme.color(TelegramColorKey.windowBackgroundWhiteGrayText),
      );
    });

    testWidgets('resources override wins over the ambient theme',
        (WidgetTester tester) async {
      const Color override = Color(0xFF123456);
      await tester.pumpWidget(_host(Builder(builder: (BuildContext context) {
        return TgEmptyView(
          title: 'Empty',
          resources: ResourcesOverride(
            parent: TelegramTheme.resources(context),
            overrides: const <int, Color>{
              TelegramColorKey.windowBackgroundWhiteBlackText: override,
            },
          ),
        );
      })));
      expect(tester.widget<Text>(find.text('Empty')).style!.color, override);
    });
  });
}
