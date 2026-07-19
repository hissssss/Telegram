// Tests for lib/src/menu/tg_popup_menu.dart (PLAN_UIKIT.md M4), golden-free:
//
//  * constants against the Java values (ActionBarPopupWindow.java, cited per
//    constant);
//  * cascade math (AndroidUtilities.java:5273-5278);
//  * open duration scales with the visible item count (150 + 16n,
//    ActionBarPopupWindow.java:896) and the reveal/alpha follow it;
//  * cascade order: item 0 lands first (ActionBarPopupWindow.java:875-895);
//  * rows forced 48dp, separator band 8dp (ItemOptions.java:786-792);
//  * first/last (and after-gap) selector rounding through TgMenuRowScope
//    (ActionBarPopupWindow.java:612-643);
//  * dismiss: 150ms fade + 5dp slide, scaleOut 0.8 variant, overlay removed
//    (ActionBarPopupWindow.java:1024-1100);
//  * tap fires + closes with the row value; disabled rows are inert at 0.5
//    alpha;
//  * opt-in 0.2 dim (ActionBarPopupWindow.java:783-795);
//  * scroll when taller than the screen (ActionBarPopupWindow.java:185-203);
//  * theme resolution + resources override in both directions.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/foundation/tg_motion.dart';
import 'package:telegram_ui/src/menu/tg_menu_item.dart';
import 'package:telegram_ui/src/menu/tg_popup_menu.dart';
import 'package:telegram_ui/src/theme/resources_override.dart';
import 'package:telegram_ui/src/theme/telegram_resources.dart';
import 'package:telegram_ui/src/theme/telegram_theme.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// Shared day theme (constructing the 777-key palette once).
final TelegramThemeData _dayTheme = TelegramThemeData.day();

const Size _screen = Size(800, 600);

/// A [TelegramResources] view over the day theme, the parent for sparse
/// [ResourcesOverride] layers in tests.
class _ThemeResources extends TelegramResources {
  const _ThemeResources(this.data);

  final TelegramThemeData data;

  @override
  Color getColor(int key) => data.color(key);
}

/// Standalone host for the bare [TgPopupMenu] surface.
Widget _host(Widget child) {
  return TelegramTheme(
    data: _dayTheme,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Align(alignment: Alignment.topLeft, child: child),
    ),
  );
}

/// A bare app: theme + directionality + media query + navigator with an
/// empty home page, for route tests.
Widget _app({Size size = _screen}) {
  return TelegramTheme(
    data: _dayTheme,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: Navigator(
          onGenerateRoute: (RouteSettings settings) => PageRouteBuilder<void>(
            settings: settings,
            pageBuilder: (BuildContext context, _, _) =>
                const ColoredBox(color: Color(0xFFFFFFFF)),
          ),
        ),
      ),
    ),
  );
}

NavigatorState _navigator(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator));

Finder get _menu => find.byType(TgPopupMenu);

TgPopupMenuSurfacePainter _surface(WidgetTester tester) =>
    tester.widget<CustomPaint>(find.byKey(TgPopupMenu.surfaceKey)).painter!
        as TgPopupMenuSurfacePainter;

/// The cascade [Opacity] wrapper of row [index] (an ancestor of the row —
/// the row's own disabled opacity is a descendant).
Opacity _cascadeOpacity(WidgetTester tester, int index) =>
    tester.widget<Opacity>(
      find
          .ancestor(
            of: find.byType(TgMenuItem).at(index),
            matching: find.byType(Opacity),
          )
          .first,
    );

List<Widget> _rows(int count) => <Widget>[
      for (int i = 0; i < count; i++) TgMenuItem(text: 'Item $i'),
    ];

void main() {
  group('constants', () {
    test('mirror the Java values', () {
      expect(kTgPopupMenuCornerRadius, 12.0); // ActionBarPopupWindow.java:549
      expect(kTgPopupMenuShadowPadding, 8.0); // ActionBarPopupWindow.java:166
      expect(kTgPopupMenuItemSlide, 6.0); // ActionBarPopupWindow.java:885
      expect(kTgPopupMenuCascadeWaveLength, 4.0); // :884
      expect(kTgPopupMenuDismissSlide, 5.0); // ActionBarPopupWindow.java:1066
      expect(kTgPopupMenuDismissScale, 0.8); // :1058-1063
      expect(kTgPopupMenuDimAmount, 0.2); // ActionBarPopupWindow.java:784
      expect(kTgMenuGapHeight, 8.0); // ItemOptions.java:786-792
    });

    test('route defaults mirror the Java popup', () {
      final TgPopupMenuRoute<void> route = TgPopupMenuRoute<void>(
        position: RelativeRect.fill,
        entries: const <TgPopupMenuEntry<void>>[],
      );
      // The window shows instantly; the surface animates itself
      // (ActionBarPopupWindow.java:833-841).
      expect(route.transitionDuration, Duration.zero);
      // dismissAnimationDuration = 150 (ActionBarPopupWindow.java:69).
      expect(route.reverseTransitionDuration, TgMotion.menuCloseDuration);
      expect(
        route.reverseTransitionDuration,
        const Duration(milliseconds: 150),
      );
      // Dim is opt-in (ActionBarPopupWindow.java:783-795).
      expect(route.barrierColor, isNull);
      expect(route.barrierDismissible, isTrue);
    });

    test('dim opts into the 0.2 barrier (ActionBarPopupWindow.java:783-795)',
        () {
      final TgPopupMenuRoute<void> route = TgPopupMenuRoute<void>(
        position: RelativeRect.fill,
        entries: const <TgPopupMenuEntry<void>>[],
        dim: true,
      );
      expect(route.barrierColor, const Color(0x33000000));
    });

    test('visibleItemCount skips gaps (ActionBarPopupWindow.java:851-863)',
        () {
      expect(
        TgPopupMenu.visibleItemCount(<Widget>[
          const TgMenuItem(text: 'a'),
          const TgMenuGap(),
          const TgMenuItem(text: 'b'),
        ]),
        2,
      );
    });
  });

  group('cascade math (AndroidUtilities.java:5273-5278)', () {
    test('count <= waveLength runs every item in unison', () {
      for (final double position in <double>[0, 1, 2]) {
        expect(tgMenuCascade(0.3, position, 3, 4), moreOrLessEquals(0.3));
      }
    });

    test('spot values for count 8, waveLength 4', () {
      // waveDuration = 4/8 = 0.5; offset(pos) = pos/8 * 0.5.
      expect(tgMenuCascade(0.25, 0, 8, 4), moreOrLessEquals(0.5));
      expect(tgMenuCascade(0.25, 4, 8, 4), moreOrLessEquals(0.0));
      expect(tgMenuCascade(0.4375, 7, 8, 4), moreOrLessEquals(0.0));
      expect(tgMenuCascade(1.0, 7, 8, 4), 1.0);
    });

    test('clamps to 0..1 and passes t through for count <= 0', () {
      expect(tgMenuCascade(2.0, 0, 8, 4), 1.0);
      expect(tgMenuCascade(-1.0, 0, 8, 4), 0.0);
      expect(tgMenuCascade(0.42, 3, 0, 4), 0.42);
    });
  });

  group('open animation', () {
    testWidgets('duration is 150 + 16n: a 1-item menu settles at 166ms '
        '(ActionBarPopupWindow.java:896)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgPopupMenu(children: _rows(1))));
      expect(_surface(tester).revealFraction, 0.0);
      expect(_surface(tester).alpha, 0.0);

      // Half of 166ms: the accelerate-decelerate curve is exactly 0.5 at
      // its midpoint.
      await tester.pump(const Duration(milliseconds: 83));
      expect(_surface(tester).revealFraction, moreOrLessEquals(0.5));
      expect(_surface(tester).alpha, moreOrLessEquals(0.5));

      await tester.pump(const Duration(milliseconds: 83));
      expect(_surface(tester).revealFraction, 1.0);
      // The completing tick unschedules the ticker after this frame.
      await tester.pump(const Duration(milliseconds: 1));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a 5-item menu is still revealing at 166ms and settles at '
        '230ms', (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgPopupMenu(children: _rows(5))));
      await tester.pump(const Duration(milliseconds: 166));
      final double fraction = _surface(tester).revealFraction;
      expect(fraction, greaterThan(0.0));
      expect(fraction, lessThan(1.0));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pump(const Duration(milliseconds: 64));
      expect(_surface(tester).revealFraction, 1.0);
      // The completing tick unschedules the ticker after this frame.
      await tester.pump(const Duration(milliseconds: 1));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('cascade: item 0 leads and lands first; rows slide from '
        '-6dp (ActionBarPopupWindow.java:875-895)',
        (WidgetTester tester) async {
      // 6 items: duration 246ms; waveDuration = 4/6, offset step = 1/18.
      await tester.pumpWidget(_host(TgPopupMenu(children: _rows(6))));

      // Midpoint: curved t = 0.5 exactly.
      await tester.pump(const Duration(milliseconds: 123));
      final double first = _cascadeOpacity(tester, 0).opacity;
      final double middle = _cascadeOpacity(tester, 3).opacity;
      final double last = _cascadeOpacity(tester, 5).opacity;
      // cascade(0.5, 0, 6, 4) = 0.75; cascade(0.5, 5, 6, 4) = 1/3.
      expect(first, moreOrLessEquals(0.75, epsilon: 1e-9));
      expect(last, moreOrLessEquals(1.0 / 3.0, epsilon: 1e-9));
      expect(first, greaterThan(middle));
      expect(middle, greaterThan(last));

      // translationY = (1 - at) * -6 (ActionBarPopupWindow.java:885).
      final Transform transform = tester.widget<Transform>(
        find
            .ancestor(
              of: find.byType(TgMenuItem).at(0),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(
        transform.transform.getTranslation().y,
        moreOrLessEquals((1.0 - first) * -kTgPopupMenuItemSlide, epsilon: 1e-9),
      );

      // t = 0.8536 (u = 0.75): item 0 has landed, item 5 has not.
      await tester.pump(const Duration(microseconds: 61500));
      expect(_cascadeOpacity(tester, 0).opacity, 1.0);
      expect(_cascadeOpacity(tester, 5).opacity, lessThan(1.0));

      await tester.pumpAndSettle();
      expect(_cascadeOpacity(tester, 5).opacity, 1.0);
    });

    testWidgets('animateOpen: false renders the settled menu',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(TgPopupMenu(animateOpen: false, children: _rows(3))),
      );
      expect(_surface(tester).revealFraction, 1.0);
      expect(_cascadeOpacity(tester, 2).opacity, 1.0);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('layout', () {
    testWidgets('rows are 48dp, the gap band is 8dp, and the surface adds '
        'the 8dp shadow ring (ActionBarPopupWindow.java:166; '
        'ItemOptions.java:786-792)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgPopupMenu(
        animateOpen: false,
        children: <Widget>[
          TgMenuItem(text: 'One'),
          TgMenuGap(),
          TgMenuItem(text: 'Two'),
        ],
      )));
      final Size menu = tester.getSize(_menu);
      // 48 + 8 + 48 + 2 * 8.
      expect(
        menu.height,
        2 * kTgMenuItemHeight +
            kTgMenuGapHeight +
            2 * kTgPopupMenuShadowPadding,
      );
      expect(
        tester.getSize(find.byType(TgMenuItem).first).height,
        kTgMenuItemHeight,
      );
      final Finder gap = find.byType(TgMenuGap);
      expect(tester.getSize(gap).height, kTgMenuGapHeight);
      // Rows and gap span the padded content width.
      expect(
        tester.getSize(gap).width,
        menu.width - 2 * kTgPopupMenuShadowPadding,
      );
      // Separator fill (ActionBarPopupWindow.java:1115).
      final ColoredBox fill = tester.widget<ColoredBox>(
        find.descendant(of: gap, matching: find.byType(ColoredBox)),
      );
      expect(
        fill.color,
        _dayTheme.color(TelegramColorKey.actionBarDefaultSubmenuSeparator),
      );
    });

    testWidgets('first, last, and after-gap rows get the selector rounding '
        '(ActionBarPopupWindow.java:612-643)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const TgPopupMenu(
        animateOpen: false,
        children: <Widget>[
          TgMenuItem(text: 'a'),
          TgMenuItem(text: 'b'),
          TgMenuGap(),
          TgMenuItem(text: 'c'),
        ],
      )));
      final List<TgMenuRowScope> scopes = tester
          .widgetList<TgMenuRowScope>(find.byType(TgMenuRowScope))
          .toList();
      expect(scopes, hasLength(3));
      expect(scopes[0].roundTop, isTrue);
      expect(scopes[0].roundBottom, isFalse);
      expect(scopes[1].roundTop, isFalse);
      expect(scopes[1].roundBottom, isFalse);
      // After the gap the top corners round again; last row rounds bottom.
      expect(scopes[2].roundTop, isTrue);
      expect(scopes[2].roundBottom, isTrue);
    });

    testWidgets('surface resolves actionBarDefaultSubmenuBackground; a '
        'resources override recolors it in both directions',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(TgPopupMenu(animateOpen: false, children: _rows(1))),
      );
      expect(
        _surface(tester).color,
        _dayTheme.color(TelegramColorKey.actionBarDefaultSubmenuBackground),
      );

      const Color override = Color(0xFF223344);
      await tester.pumpWidget(_host(TgPopupMenu(
        animateOpen: false,
        resources: ResourcesOverride(
          parent: _ThemeResources(_dayTheme),
          overrides: const <int, Color>{
            TelegramColorKey.actionBarDefaultSubmenuBackground: override,
          },
        ),
        children: _rows(1),
      )));
      expect(_surface(tester).color, override);
    });
  });

  group('route', () {
    testWidgets('opens at the anchor position', (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      showTgPopupMenu<String>(
        _navigator(tester).context,
        position: const RelativeRect.fromLTRB(100, 50, 0, 0),
        entries: const <TgPopupMenuEntry<String>>[
          TgPopupMenuItem<String>(text: 'One', value: 'one'),
          TgPopupMenuItem<String>(text: 'Two', value: 'two'),
        ],
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(_menu), const Offset(100, 50));
    });

    testWidgets('clamps on screen (PopupWindow edge fitting)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      showTgPopupMenu<String>(
        _navigator(tester).context,
        position: const RelativeRect.fromLTRB(790, 590, 0, 0),
        entries: const <TgPopupMenuEntry<String>>[
          TgPopupMenuItem<String>(text: 'One', value: 'one'),
        ],
      );
      await tester.pumpAndSettle();
      final Rect menu = tester.getRect(_menu);
      expect(menu.right, _screen.width);
      expect(menu.bottom, _screen.height);
    });

    testWidgets('tap fires the row callback and pops with its value',
        (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(_app());
      final Future<String?> result = showTgPopupMenu<String>(
        _navigator(tester).context,
        position: const RelativeRect.fromLTRB(100, 50, 0, 0),
        entries: <TgPopupMenuEntry<String>>[
          const TgPopupMenuItem<String>(text: 'One', value: 'one'),
          TgPopupMenuItem<String>(
            text: 'Two',
            value: 'two',
            onTap: () => taps++,
          ),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Two'));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(_menu, findsNothing);
      expect(await result, 'two');
    });

    testWidgets('disabled rows are inert at 0.5 alpha '
        '(ActionBarPopupWindow.java:886)', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(_app());
      showTgPopupMenu<String>(
        _navigator(tester).context,
        position: const RelativeRect.fromLTRB(100, 50, 0, 0),
        entries: <TgPopupMenuEntry<String>>[
          const TgPopupMenuItem<String>(text: 'One', value: 'one'),
          TgPopupMenuItem<String>(
            text: 'Two',
            value: 'two',
            enabled: false,
            onTap: () => taps++,
          ),
        ],
      );
      await tester.pumpAndSettle();

      final Opacity rowAlpha = tester.widget<Opacity>(
        find
            .descendant(
              of: find.byType(TgMenuItem).at(1),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(rowAlpha.opacity, kTgMenuItemDisabledAlpha);

      await tester.tap(find.text('Two'));
      await tester.pumpAndSettle();
      expect(taps, 0);
      expect(_menu, findsOneWidget);
    });

    testWidgets('barrier tap dismisses with a null result',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      final Future<String?> result = showTgPopupMenu<String>(
        _navigator(tester).context,
        position: const RelativeRect.fromLTRB(100, 50, 0, 0),
        entries: const <TgPopupMenuEntry<String>>[
          TgPopupMenuItem<String>(text: 'One', value: 'one'),
        ],
      );
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(700, 500));
      await tester.pumpAndSettle();
      expect(_menu, findsNothing);
      expect(await result, isNull);
    });

    testWidgets('dismiss: 150ms fade + 5dp upward slide, then the overlay '
        'is removed (ActionBarPopupWindow.java:1064-1068)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgPopupMenuRoute<String>(
        position: const RelativeRect.fromLTRB(100, 50, 0, 0),
        entries: const <TgPopupMenuEntry<String>>[
          TgPopupMenuItem<String>(text: 'One', value: 'one'),
        ],
      ));
      await tester.pumpAndSettle();

      _navigator(tester).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      // Accelerate-decelerate midpoint = 0.5 exactly.
      final Opacity fade = tester.widget<Opacity>(
        find.ancestor(of: _menu, matching: find.byType(Opacity)).first,
      );
      expect(fade.opacity, moreOrLessEquals(0.5));
      final Transform slide = tester.widget<Transform>(
        find.ancestor(of: _menu, matching: find.byType(Transform)).first,
      );
      expect(
        slide.transform.getTranslation().y,
        moreOrLessEquals(-kTgPopupMenuDismissSlide * 0.5),
      );

      await tester.pump(const Duration(milliseconds: 75));
      await tester.pumpAndSettle();
      expect(_menu, findsNothing);
    });

    testWidgets('scaleOut dismiss shrinks toward the top-right pivot '
        '(ActionBarPopupWindow.java:847-848, 1058-1063)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgPopupMenuRoute<String>(
        position: const RelativeRect.fromLTRB(100, 50, 0, 0),
        scaleOutDismiss: true,
        entries: const <TgPopupMenuEntry<String>>[
          TgPopupMenuItem<String>(text: 'One', value: 'one'),
        ],
      ));
      await tester.pumpAndSettle();

      _navigator(tester).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      final Transform scale = tester.widget<Transform>(
        find.ancestor(of: _menu, matching: find.byType(Transform)).first,
      );
      // scale = 0.8 + 0.2 * t at t = 0.5 (x/y entries; z stays 1).
      expect(scale.transform.entry(0, 0), moreOrLessEquals(0.9));
      expect(scale.transform.entry(1, 1), moreOrLessEquals(0.9));
      expect(scale.alignment, Alignment.topRight);

      await tester.pump(const Duration(milliseconds: 75));
      await tester.pumpAndSettle();
      expect(_menu, findsNothing);
    });

    testWidgets('no dim by default; dim: true carries the 0.2 barrier '
        '(ActionBarPopupWindow.java:783-795)', (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgPopupMenuRoute<String>(
        position: const RelativeRect.fromLTRB(100, 50, 0, 0),
        entries: const <TgPopupMenuEntry<String>>[
          TgPopupMenuItem<String>(text: 'One', value: 'one'),
        ],
      ));
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedModalBarrier), findsNothing);
      _navigator(tester).pop();
      await tester.pumpAndSettle();

      _navigator(tester).push(TgPopupMenuRoute<String>(
        position: const RelativeRect.fromLTRB(100, 50, 0, 0),
        dim: true,
        entries: const <TgPopupMenuEntry<String>>[
          TgPopupMenuItem<String>(text: 'One', value: 'one'),
        ],
      ));
      await tester.pumpAndSettle();
      final AnimatedModalBarrier barrier = tester
          .widget<AnimatedModalBarrier>(find.byType(AnimatedModalBarrier));
      expect(barrier.color.value, const Color(0x33000000));
    });

    testWidgets('a gap entry renders the 8dp band',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgPopupMenuRoute<String>(
        position: const RelativeRect.fromLTRB(100, 50, 0, 0),
        entries: const <TgPopupMenuEntry<String>>[
          TgPopupMenuItem<String>(text: 'One', value: 'one'),
          TgPopupMenuGap<String>(),
          TgPopupMenuItem<String>(text: 'Two', value: 'two'),
        ],
      ));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(TgMenuGap)).height, kTgMenuGapHeight);
    });

    testWidgets('a menu taller than the screen caps and scrolls '
        '(ActionBarPopupWindow.java:185-203)', (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      _navigator(tester).push(TgPopupMenuRoute<int>(
        position: const RelativeRect.fromLTRB(0, 0, 0, 0),
        entries: <TgPopupMenuEntry<int>>[
          for (int i = 0; i < 20; i++)
            TgPopupMenuItem<int>(text: 'Item $i', value: i),
        ],
      ));
      await tester.pumpAndSettle();
      // 20 * 48 + 16 = 976 > 600.
      expect(tester.getSize(_menu).height, lessThanOrEqualTo(_screen.height));
      expect(
        find.descendant(
          of: _menu,
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
    });
  });

  group('shownFromBottom', () {
    testWidgets('reverses the cascade and slides rows from +6dp '
        '(ActionBarPopupWindow.java:884, 385)', (WidgetTester tester) async {
      await tester.pumpWidget(_host(TgPopupMenu(
        shownFromBottom: true,
        children: _rows(6),
      )));
      await tester.pump(const Duration(milliseconds: 123));
      // Bottom-up: the LAST row leads.
      final double first = _cascadeOpacity(tester, 0).opacity;
      final double last = _cascadeOpacity(tester, 5).opacity;
      expect(last, moreOrLessEquals(0.75, epsilon: 1e-9));
      expect(first, moreOrLessEquals(1.0 / 3.0, epsilon: 1e-9));
      final Transform transform = tester.widget<Transform>(
        find
            .ancestor(
              of: find.byType(TgMenuItem).at(0),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(transform.transform.getTranslation().y, greaterThan(0.0));
      await tester.pumpAndSettle();
    });
  });
}
