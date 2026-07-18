// Ring-1 tests for the glass surface color recipes:
// - GlassSurfaceStyle / GlassSurfaceStyleBuilder
//   (BlurredBackgroundProviderBuilder.java + BlurredBackgroundColorProviderThemed.java)
// - GlassPresets (BlurredBackgroundProviderImpl.java, all factories)
//
// Constants are asserted against literal hex/dp values hand-read from the
// Java sources (cited by line), independent of the generated
// glass_metrics.g.dart tables; derived colors (multAlpha / solveSrcColor
// backgrounds) are recomputed through the ported color math against real
// day/night theme palettes. The solveSrcColor recipes additionally get the
// documented composite invariant checked end to end:
// compositeColors(style.backgroundColor, bg) == target within +/-1/channel
// (BlurredBackgroundProviderImpl.java:288-316).

import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_ui/src/foundation/color_math.dart';
import 'package:telegram_ui/src/glass/presets.dart';
import 'package:telegram_ui/src/glass/strategy.dart';
import 'package:telegram_ui/src/glass/surface_colors.dart';
import 'package:telegram_ui/src/theme/telegram_resources.dart';
import 'package:telegram_ui/src/theme/telegram_theme_data.dart';
import 'package:telegram_ui/src/tokens/theme_keys.g.dart';

/// [TelegramResources] view over a [TelegramThemeData]; inherits the
/// brightness-based default `isDark` (windowBackgroundWhite < 0.721).
class _ThemeResources extends TelegramResources {
  _ThemeResources(this.data);

  final TelegramThemeData data;

  @override
  Color getColor(int key) => data.color(key);
}

/// Fixed sparse palette for targeted branch tests.
class _FixedResources extends TelegramResources {
  const _FixedResources(this.colors);

  final Map<int, Color> colors;

  @override
  Color getColor(int key) => colors[key] ?? const Color(0xFF808080);
}

void main() {
  final TelegramThemeData day = TelegramThemeData.day();
  final TelegramThemeData night = TelegramThemeData.night();
  final _ThemeResources dayRes = _ThemeResources(day);
  final _ThemeResources nightRes = _ThemeResources(night);

  int themeArgb(TelegramThemeData theme, int key) => theme.color(key).toARGB32();

  void expectWithinOnePerChannel(int actual, int expected, {required String reason}) {
    for (final int shift in <int>[24, 16, 8, 0]) {
      final int a = (actual >> shift) & 0xFF;
      final int e = (expected >> shift) & 0xFF;
      expect(
        (a - e).abs(),
        lessThanOrEqualTo(1),
        reason: '$reason: channel at shift $shift — actual '
            '0x${actual.toRadixString(16)}, expected 0x${expected.toRadixString(16)}',
      );
    }
  }

  setUp(() {
    // Sanity: the two bundled palettes classify as expected, so the
    // light/dark pair resolution below exercises both branches.
    expect(dayRes.isDark, isFalse);
    expect(nightRes.isDark, isTrue);
  });

  group('solveSrcColor invariant on real themes (BlurredBackgroundProviderImpl.java:288-316)', () {
    for (final (String name, _ThemeResources res, TelegramThemeData theme) in [
      ('day', dayRes, day),
      ('night', nightRes, night),
    ]) {
      for (final GlassTier tier in <GlassTier>[GlassTier.liquid, GlassTier.frosted]) {
        test('mainTabs $name/$tier composites onto glass_targetMainTabs', () {
          final GlassSurfaceStyle style = GlassPresets.mainTabs(res, tier: tier);
          final int bg = themeArgb(theme, TelegramColorKey.windowBackgroundWhite);
          final int target = themeArgb(theme, TelegramColorKey.glass_targetMainTabs);
          expectWithinOnePerChannel(
            compositeColors(style.backgroundColor.toARGB32(), bg),
            target,
            reason: 'mainTabs $name/$tier',
          );
        });

        test('topPanel $name/$tier composites onto glass_targetMainTopPanel', () {
          final GlassSurfaceStyle style = GlassPresets.topPanel(res, tier: tier);
          final int bg = themeArgb(theme, TelegramColorKey.windowBackgroundWhite);
          final int target = themeArgb(theme, TelegramColorKey.glass_targetMainTopPanel);
          expectWithinOnePerChannel(
            compositeColors(style.backgroundColor.toARGB32(), bg),
            target,
            reason: 'topPanel $name/$tier',
          );
        });
      }
    }

    test('inputFieldShareAlert day composites onto chat_messagePanelBackground', () {
      final GlassSurfaceStyle style = GlassPresets.inputFieldShareAlert(dayRes);
      final int bg = themeArgb(day, TelegramColorKey.windowBackgroundWhite);
      final int target = themeArgb(day, TelegramColorKey.chat_messagePanelBackground);
      expectWithinOnePerChannel(
        compositeColors(style.backgroundColor.toARGB32(), bg),
        target,
        reason: 'inputFieldShareAlert day',
      );
    });
  });

  group('mainTabs (BlurredBackgroundProviderImpl.java:19-33)', () {
    test('light constants', () {
      final GlassSurfaceStyle style = GlassPresets.mainTabs(dayRes);
      expect(style.strokeColorTop, const Color(0x11000000)); // line 27
      expect(style.strokeColorBottom, const Color(0x20000000)); // line 28
      expect(style.shadowColor, const Color(0x20000000)); // line 29
      expect(style.shadowRadius, 2.667); // line 30
      expect(style.shadowDx, 0.0);
      expect(style.shadowDy, 0.85);
      expect(style.strokeWidthTop, 0.4); // line 31
      expect(style.strokeWidthBottom, 0.4);
      expect(style.tintAlpha, 0.85); // liquid, line 22
    });

    test('dark constants', () {
      final GlassSurfaceStyle style = GlassPresets.mainTabs(nightRes);
      expect(style.strokeColorTop, const Color(0x06FFFFFF)); // line 27
      expect(style.strokeColorBottom, const Color(0x11FFFFFF)); // line 28
      expect(style.shadowColor, const Color(0x04FFFFFF)); // line 29
    });

    test('frosted tier drops the tint alpha to 0.76 (line 22)', () {
      final GlassSurfaceStyle style = GlassPresets.mainTabs(dayRes, tier: GlassTier.frosted);
      expect(style.tintAlpha, 0.76);
      // solveSrcColor stamps round(alpha * 255) into the solved color.
      expect((style.backgroundColor.toARGB32() >> 24) & 0xFF, (0.76 * 255).round());
    });

    test('is assignable to GlassSurfaceStyleResolver', () {
      const GlassSurfaceStyleResolver resolver = GlassPresets.mainTabs;
      expect(resolver(dayRes, tier: GlassTier.liquid), GlassPresets.mainTabs(dayRes));
    });
  });

  group('topPanel (lines 35-49)', () {
    test('shares the mainTabs constants, solves the topPanel target', () {
      final GlassSurfaceStyle style = GlassPresets.topPanel(dayRes);
      expect(style.strokeColorTop, const Color(0x11000000)); // line 43
      expect(style.strokeColorBottom, const Color(0x20000000)); // line 44
      expect(style.shadowColor, const Color(0x20000000)); // line 45
      expect(style.shadowRadius, 2.667); // line 46
      expect(style.shadowDy, 0.85);
      expect(style.strokeWidthTop, 0.4); // line 47
      expect(style.strokeWidthBottom, 0.4);
    });

    test('inputFieldDialog delegates to topPanel verbatim (lines 223-225)', () {
      expect(GlassPresets.inputFieldDialog(dayRes), GlassPresets.topPanel(dayRes));
      expect(
        GlassPresets.inputFieldDialog(nightRes, tier: GlassTier.frosted),
        GlassPresets.topPanel(nightRes, tier: GlassTier.frosted),
      );
    });
  });

  group('emojiViewButton (lines 51-64)', () {
    test('light', () {
      final GlassSurfaceStyle style = GlassPresets.emojiViewButton(dayRes);
      expect(
        style.backgroundColor.toARGB32(),
        multAlpha(themeArgb(day, TelegramColorKey.windowBackgroundWhite), 0.85), // lines 54-56
      );
      expect(style.strokeColorTop, const Color(0xFFFFFFFF)); // line 58
      expect(style.strokeColorBottom, const Color(0xFFFFFFFF)); // line 59
      expect(style.shadowColor, const Color(0x40000000)); // line 60
      expect(style.shadowRadius, 11 / 3); // line 61
      expect(style.shadowDy, 2 / 3);
      expect(style.strokeWidthTop, 0.5); // line 62
      expect(style.strokeWidthBottom, 0.5);
    });

    test('dark', () {
      final GlassSurfaceStyle style = GlassPresets.emojiViewButton(nightRes);
      expect(style.strokeColorTop, const Color(0x28FFFFFF)); // line 58
      expect(style.strokeColorBottom, const Color(0x14FFFFFF)); // line 59
      expect(style.shadowColor, const Color(0x00000000)); // line 60
    });
  });

  group('counterMini (lines 66-79)', () {
    test('theme-independent background multAlpha(black, 0.075)', () {
      for (final _ThemeResources res in <_ThemeResources>[dayRes, nightRes]) {
        final GlassSurfaceStyle style = GlassPresets.counterMini(res);
        // (255 * 0.075).truncate() == 19 == 0x13 (multAlpha truncates).
        expect(style.backgroundColor, const Color(0x13000000)); // lines 68-72
        expect(style.strokeColorBottom, const Color(0x24000000)); // line 74
        expect(style.shadowColor, const Color(0x00000000)); // line 75
        expect(style.shadowRadius, 0.0); // line 76
        expect(style.shadowDy, 0.0);
        expect(style.strokeWidthTop, 0.43); // line 77
        expect(style.strokeWidthBottom, 0.43);
        expect(style.tintAlpha, 0.075);
      }
    });

    test('stroke top pair', () {
      expect(GlassPresets.counterMini(dayRes).strokeColorTop, const Color(0x60FFFFFF)); // line 73
      expect(GlassPresets.counterMini(nightRes).strokeColorTop, const Color(0x50FFFFFF));
    });
  });

  group('scrimMenu (lines 81-91)', () {
    test('light: alpha 0.76 despite liquid tier — branches on isDark, not LiteMode', () {
      final GlassSurfaceStyle style = GlassPresets.scrimMenu(dayRes);
      expect(style.tintAlpha, 0.76); // line 84
      expect(
        style.backgroundColor.toARGB32(),
        multAlpha(themeArgb(day, TelegramColorKey.actionBarDefaultSubmenuBackground), 0.76),
      );
      expect(style.strokeColorTop, const Color(0xFFFFFFFF)); // line 85
      expect(style.strokeColorBottom, const Color(0xFFFFFFFF)); // line 86
      expect(style.shadowColor, const Color(0x26000000)); // line 87
      expect(style.shadowRadius, 4.0); // line 88
      expect(style.shadowDy, 0.0);
      expect(style.strokeWidthTop, 2 / 3); // line 89
      expect(style.strokeWidthBottom, 2 / 3);
    });

    test('dark: alpha 0.85, no strokes, no shadow', () {
      final GlassSurfaceStyle style = GlassPresets.scrimMenu(nightRes);
      expect(style.tintAlpha, 0.85);
      expect(
        style.backgroundColor.toARGB32(),
        multAlpha(themeArgb(night, TelegramColorKey.actionBarDefaultSubmenuBackground), 0.85),
      );
      expect(style.strokeColorTop, const Color(0x00000000));
      expect(style.strokeColorBottom, const Color(0x00000000));
      expect(style.shadowColor, const Color(0x00000000));
    });
  });

  group('attachMenuSearch (lines 93-106)', () {
    test('light', () {
      final GlassSurfaceStyle style = GlassPresets.attachMenuSearch(dayRes);
      expect(
        style.backgroundColor.toARGB32(),
        multAlpha(themeArgb(day, TelegramColorKey.windowBackgroundWhite), 0.85), // lines 96-98
      );
      expect(style.strokeColorTop, const Color(0x17000000)); // line 100
      expect(style.strokeColorBottom, const Color(0x17000000)); // line 101
      expect(style.shadowColor, const Color(0x11000000)); // line 102
      expect(style.shadowRadius, 2.0); // line 103
      expect(style.shadowDy, 1 / 3);
      expect(style.strokeWidthTop, 0.4); // line 104
      expect(style.strokeWidthBottom, 0.4);
    });

    test('dark', () {
      final GlassSurfaceStyle style = GlassPresets.attachMenuSearch(nightRes);
      expect(style.strokeColorTop, const Color(0x17FFFFFF));
      expect(style.strokeColorBottom, const Color(0x17FFFFFF));
      expect(style.shadowColor, const Color(0x04FFFFFF));
    });
  });

  group('searchFloatingDate (lines 108-116)', () {
    test('fixed background, default shadow layer, raw 1px strokes', () {
      final GlassSurfaceStyle style = GlassPresets.searchFloatingDate(dayRes);
      expect(style.backgroundColor, const Color(0x33000000)); // line 110
      expect(style.strokeColorTop, const Color(0x17000000)); // line 111
      expect(style.strokeColorBottom, const Color(0x17000000)); // line 112
      expect(style.shadowColor, const Color(0x00000000)); // line 113
      // No setShadowLayer call — builder defaults survive
      // (BlurredBackgroundProviderBuilder.java:15).
      expect(style.shadowRadius, 1.0);
      expect(style.shadowDx, 0.0);
      expect(style.shadowDy, 1 / 3);
      expect(style.strokeWidthTop, 1.0); // line 114 (raw 1, not dpf2)
      expect(style.strokeWidthBottom, 1.0);
    });

    test('dark strokes flip to white hex', () {
      final GlassSurfaceStyle style = GlassPresets.searchFloatingDate(nightRes);
      expect(style.backgroundColor, const Color(0x33000000)); // theme-independent
      expect(style.strokeColorTop, const Color(0x17FFFFFF));
      expect(style.strokeColorBottom, const Color(0x17FFFFFF));
    });
  });

  group('bottomPanelChat (lines 118-135)', () {
    test('liquid: translucent panel tint, light strokes', () {
      final GlassSurfaceStyle style = GlassPresets.bottomPanelChat(dayRes);
      expect(
        style.backgroundColor.toARGB32(),
        multAlpha(themeArgb(day, TelegramColorKey.chat_messagePanelBackground), 0.85), // 125-127
      );
      expect(style.strokeColorTop, const Color(0xFFFFFFFF)); // line 129
      expect(style.strokeColorBottom, const Color(0xFFFFFFFF)); // line 130
      expect(style.shadowColor, const Color(0x20000000)); // line 131
      // setShadowLayer is commented out (line 132) — defaults survive.
      expect(style.shadowRadius, 1.0);
      expect(style.shadowDy, 1 / 3);
      expect(style.strokeWidthTop, 0.5); // line 133
      expect(style.strokeWidthBottom, 0.5);
    });

    test('dark strokes and no shadow', () {
      final GlassSurfaceStyle style = GlassPresets.bottomPanelChat(nightRes);
      expect(style.strokeColorTop, const Color(0x28FFFFFF));
      expect(style.strokeColorBottom, const Color(0x14FFFFFF));
      expect(style.shadowColor, const Color(0x00000000));
    });

    test('flat tier: opaque fallback (checkBlurEnabled false, lines 121-123)', () {
      final GlassSurfaceStyle style = GlassPresets.bottomPanelChat(dayRes, tier: GlassTier.flat);
      expect(
        style.backgroundColor.toARGB32(),
        0xFF000000 | (themeArgb(day, TelegramColorKey.chat_messagePanelBackground) & 0xFFFFFF),
      );
      expect(style.tintAlpha, 1.0);
    });
  });

  group('topPanelChat (lines 137-155)', () {
    test('liquid: chat_topPanelBackground tint', () {
      final GlassSurfaceStyle style = GlassPresets.topPanelChat(dayRes);
      expect(
        style.backgroundColor.toARGB32(),
        multAlpha(themeArgb(day, TelegramColorKey.chat_topPanelBackground), 0.85), // 145-147
      );
      expect(style.strokeColorTop, const Color(0xFFFFFFFF)); // line 149
      expect(style.strokeColorBottom, const Color(0xFFFFFFFF)); // line 150
      expect(style.shadowColor, const Color(0x20000000)); // line 151
      expect(style.strokeWidthTop, 0.55); // line 153
      expect(style.strokeWidthBottom, 0.55);
    });

    test('dark strokes 0x20FFFFFF / 0x14FFFFFF', () {
      final GlassSurfaceStyle style = GlassPresets.topPanelChat(nightRes);
      expect(style.strokeColorTop, const Color(0x20FFFFFF)); // line 149
      expect(style.strokeColorBottom, const Color(0x14FFFFFF)); // line 150
      expect(style.shadowColor, const Color(0x00000000));
    });

    test('flat tier: opaque actionBarDefault (dark) / chat_topPanelBackground (light)', () {
      // Lines 140-143.
      expect(
        GlassPresets.topPanelChat(nightRes, tier: GlassTier.flat).backgroundColor.toARGB32(),
        0xFF000000 | (themeArgb(night, TelegramColorKey.actionBarDefault) & 0xFFFFFF),
      );
      expect(
        GlassPresets.topPanelChat(dayRes, tier: GlassTier.flat).backgroundColor.toARGB32(),
        0xFF000000 | (themeArgb(day, TelegramColorKey.chat_topPanelBackground) & 0xFFFFFF),
      );
    });
  });

  group('attachMenuActionBar (lines 157-171)', () {
    test('light: solve dialogBackgroundGray -> windowBackgroundWhite', () {
      final GlassSurfaceStyle style = GlassPresets.attachMenuActionBar(dayRes);
      expect(
        style.backgroundColor.toARGB32(),
        solveSrcColor(
          themeArgb(day, TelegramColorKey.dialogBackgroundGray), // line 161, light
          themeArgb(day, TelegramColorKey.windowBackgroundWhite), // line 162
          0.85,
        ),
      );
      expect(style.strokeColorTop, const Color(0xFFFFFFFF)); // line 165
      expect(style.strokeColorBottom, const Color(0xFFFFFFFF)); // line 166
      expect(style.shadowColor, const Color(0x20000000)); // line 167
      expect(style.strokeWidthTop, 1.0); // line 169
      expect(style.strokeWidthBottom, 2 / 3);
    });

    test('dark: solve windowBackgroundGray -> windowBackgroundWhite', () {
      final GlassSurfaceStyle style = GlassPresets.attachMenuActionBar(nightRes);
      expect(
        style.backgroundColor.toARGB32(),
        solveSrcColor(
          themeArgb(night, TelegramColorKey.windowBackgroundGray), // line 161, dark
          themeArgb(night, TelegramColorKey.windowBackgroundWhite),
          0.85,
        ),
      );
      expect(style.strokeColorTop, const Color(0x28FFFFFF));
      expect(style.strokeColorBottom, const Color(0x14FFFFFF));
      expect(style.shadowColor, const Color(0x00000000));
    });
  });

  group('topPanelChatTags (lines 173-191)', () {
    test('topPanelChat background with everything else zeroed', () {
      final GlassSurfaceStyle style = GlassPresets.topPanelChatTags(dayRes);
      expect(
        style.backgroundColor.toARGB32(),
        multAlpha(themeArgb(day, TelegramColorKey.chat_topPanelBackground), 0.85),
      );
      expect(style.strokeColorTop, const Color(0x00000000)); // line 185
      expect(style.strokeColorBottom, const Color(0x00000000)); // line 186
      expect(style.shadowColor, const Color(0x00000000)); // line 187
      expect(style.shadowRadius, 0.0); // line 188
      expect(style.shadowDy, 0.0);
      expect(style.strokeWidthTop, 0.0); // line 189
      expect(style.strokeWidthBottom, 0.0);
    });

    test('flat dark falls back to opaque actionBarDefault (lines 176-179)', () {
      expect(
        GlassPresets.topPanelChatTags(nightRes, tier: GlassTier.flat).backgroundColor.toARGB32(),
        0xFF000000 | (themeArgb(night, TelegramColorKey.actionBarDefault) & 0xFFFFFF),
      );
    });
  });

  group('topPanelChatSearchList (lines 193-206)', () {
    test('windowBackgroundWhite at fixed 0.7 alpha, all chrome zeroed', () {
      for (final (TelegramThemeData theme, _ThemeResources res) in [(day, dayRes), (night, nightRes)]) {
        final GlassSurfaceStyle style = GlassPresets.topPanelChatSearchList(res);
        expect(
          style.backgroundColor.toARGB32(),
          multAlpha(themeArgb(theme, TelegramColorKey.windowBackgroundWhite), 0.7), // 196-198
        );
        expect(style.tintAlpha, 0.7);
        expect(style.strokeColorTop, const Color(0x00000000));
        expect(style.shadowColor, const Color(0x00000000));
        expect(style.shadowRadius, 0.0);
        expect(style.strokeWidthTop, 0.0);
        expect(style.strokeWidthBottom, 0.0);
      }
    });
  });

  group('bulletin (lines 208-221)', () {
    test('undo_background tint, no strokes/shadow colors, 0.5dp widths', () {
      final GlassSurfaceStyle style = GlassPresets.bulletin(nightRes);
      expect(
        style.backgroundColor.toARGB32(),
        multAlpha(themeArgb(night, TelegramColorKey.undo_background), 0.85), // lines 210-213
      );
      // Stroke/shadow setters are commented out (lines 215-218).
      expect(style.strokeColorTop, const Color(0x00000000));
      expect(style.strokeColorBottom, const Color(0x00000000));
      expect(style.shadowColor, const Color(0x00000000));
      // Builder defaults survive for the layer metrics.
      expect(style.shadowRadius, 1.0);
      expect(style.shadowDy, 1 / 3);
      expect(style.strokeWidthTop, 0.5); // line 219
      expect(style.strokeWidthBottom, 0.5);
    });
  });

  group('inputFieldShareAlert (lines 227-241)', () {
    test('constants are palette-independent where Java repeats them', () {
      for (final _ThemeResources res in <_ThemeResources>[dayRes, nightRes]) {
        final GlassSurfaceStyle style = GlassPresets.inputFieldShareAlert(res);
        expect(style.strokeColorTop, const Color(0x28FFFFFF)); // line 235
        expect(style.strokeColorBottom, const Color(0x14FFFFFF)); // line 236
        expect(style.shadowRadius, 10 / 3); // line 238
        expect(style.shadowDy, 2 / 3);
        expect(style.strokeWidthTop, 1.0); // line 239
        expect(style.strokeWidthBottom, 2 / 3);
      }
      expect(GlassPresets.inputFieldShareAlert(dayRes).shadowColor, const Color(0x20000000)); // 237
      expect(GlassPresets.inputFieldShareAlert(nightRes).shadowColor, const Color(0x00000000));
    });
  });

  group('photoViewer + photoViewerMenu (lines 243-264)', () {
    test('photoViewer paints no background — Java returns 0 (line 249)', () {
      for (final _ThemeResources res in <_ThemeResources>[dayRes, nightRes]) {
        final GlassSurfaceStyle style = GlassPresets.photoViewer(res);
        expect(style.backgroundColor, const Color(0x00000000));
        expect(style.tintAlpha, 0.0);
        expect(style.strokeColorTop, const Color(0x28FFFFFF)); // line 251
        expect(style.strokeColorBottom, const Color(0x14FFFFFF)); // line 252
        expect(style.shadowColor, const Color(0x00000000)); // never set
        expect(style.strokeWidthTop, 2 / 3); // line 253
        expect(style.strokeWidthBottom, 2 / 3);
      }
    });

    test('photoViewerMenu fixed 0x40000000 background (line 259)', () {
      final GlassSurfaceStyle style = GlassPresets.photoViewerMenu(dayRes);
      expect(style.backgroundColor, const Color(0x40000000));
      expect(style.strokeColorTop, const Color(0x28FFFFFF)); // line 260
      expect(style.strokeColorBottom, const Color(0x14FFFFFF)); // line 261
      expect(style.strokeWidthTop, 2 / 3); // line 262
    });
  });

  group('premiumButton (lines 266-276)', () {
    test('light', () {
      final GlassSurfaceStyle style = GlassPresets.premiumButton(dayRes);
      expect(
        style.backgroundColor.toARGB32(),
        multAlpha(themeArgb(day, TelegramColorKey.dialogBackground), 0.78), // lines 268-269
      );
      expect(style.tintAlpha, 0.78);
      expect(style.strokeColorTop, const Color(0xFFFFFFFF)); // line 270
      expect(style.strokeColorBottom, const Color(0x00000000)); // line 271
      expect(style.shadowColor, const Color(0x30000000)); // line 272
      expect(style.shadowRadius, 12 / 3); // line 273
      expect(style.shadowDy, 1 / 3);
      expect(style.strokeWidthTop, 0.67); // line 274
      expect(style.strokeWidthBottom, 0.67);
    });

    test('dark', () {
      final GlassSurfaceStyle style = GlassPresets.premiumButton(nightRes);
      expect(style.strokeColorTop, const Color(0x20FFFFFF)); // line 270
      expect(style.strokeColorBottom, const Color(0x20FFFFFF)); // line 271
      expect(style.shadowColor, const Color(0x04FFFFFF)); // line 272
    });
  });

  group('shadow (lines 278-286)', () {
    test('no background in either palette', () {
      for (final _ThemeResources res in <_ThemeResources>[dayRes, nightRes]) {
        final GlassSurfaceStyle style = GlassPresets.shadow(res);
        expect(style.backgroundColor, const Color(0x00000000));
        expect(style.tintAlpha, 0.0);
        expect(style.shadowRadius, 12 / 3); // line 283
        expect(style.shadowDy, 1 / 3);
        expect(style.strokeWidthTop, 0.4); // line 284
        expect(style.strokeWidthBottom, 0.4);
      }
    });

    test('light: shadow only; dark: hairlines + faint glow', () {
      final GlassSurfaceStyle light = GlassPresets.shadow(dayRes);
      expect(light.strokeColorTop, const Color(0x00000000)); // line 280
      expect(light.strokeColorBottom, const Color(0x00000000)); // line 281
      expect(light.shadowColor, const Color(0x30000000)); // line 282

      final GlassSurfaceStyle dark = GlassPresets.shadow(nightRes);
      expect(dark.strokeColorTop, const Color(0x28FFFFFF));
      expect(dark.strokeColorBottom, const Color(0x14FFFFFF));
      expect(dark.shadowColor, const Color(0x04FFFFFF));
    });
  });

  group('GlassSurfaceStyle.themed (BlurredBackgroundColorProviderThemed.java)', () {
    const int key = TelegramColorKey.windowBackgroundWhite;

    test('light branch (lines 47-51): white strokes, 0x20000000 shadow', () {
      const _FixedResources res = _FixedResources(<int, Color>{key: Color(0xFFF0F0F0)});
      final GlassSurfaceStyle style =
          GlassSurfaceStyle.themed(resources: res, colorKey: key);
      expect(style.backgroundColor.toARGB32(), multAlpha(0xFFF0F0F0, 0.85)); // line 41
      expect(style.strokeColorTop, const Color(0xFFFFFFFF)); // line 48
      expect(style.strokeColorBottom, const Color(0xFFFFFFFF)); // line 49
      expect(style.shadowColor, const Color(0x20000000)); // line 50
      expect(style.tintAlpha, 0.85); // line 16, liquid default
      // Metrics stay at the BlurredBackgroundDrawable defaults (lines 46-53).
      expect(style.strokeWidthTop, 1.0);
      expect(style.strokeWidthBottom, 2 / 3);
      expect(style.shadowRadius, 1.0);
      expect(style.shadowDx, 0.0);
      expect(style.shadowDy, 1 / 3);
    });

    test('dark branch (lines 43-46): 0x28/0x14 white strokes, no shadow', () {
      const _FixedResources res = _FixedResources(<int, Color>{key: Color(0xFF1D2733)});
      final GlassSurfaceStyle style =
          GlassSurfaceStyle.themed(resources: res, colorKey: key);
      expect(style.backgroundColor.toARGB32(), multAlpha(0xFF1D2733, 0.85));
      expect(style.strokeColorTop, const Color(0x28FFFFFF)); // line 44
      expect(style.strokeColorBottom, const Color(0x14FFFFFF)); // line 45
      expect(style.shadowColor, const Color(0x00000000)); // line 46
    });

    test('branch selection uses the resolved key color, not the ambient palette (lines 34-37)', () {
      // windowBackgroundWhite is light (so resources.isDark == false), yet a
      // dark colorKey must still select the dark stroke set.
      const int panelKey = TelegramColorKey.chat_messagePanelBackground;
      const _FixedResources res = _FixedResources(<int, Color>{
        key: Color(0xFFFFFFFF),
        panelKey: Color(0xFF101010),
      });
      expect(res.isDark, isFalse);
      final GlassSurfaceStyle style =
          GlassSurfaceStyle.themed(resources: res, colorKey: panelKey);
      expect(style.strokeColorTop, const Color(0x28FFFFFF));
      expect(style.shadowColor, const Color(0x00000000));
    });

    test('threshold is perceivedBrightness < 0.721 on the key color', () {
      // 0xFFB8B8B8: brightness = 184/255 = 0.7216 -> light (just above).
      // 0xFFB7B7B7: brightness = 183/255 = 0.7176 -> dark (just below).
      const _FixedResources res = _FixedResources(<int, Color>{
        1: Color(0xFFB8B8B8),
        2: Color(0xFFB7B7B7),
      });
      expect(
        GlassSurfaceStyle.themed(resources: res, colorKey: 1).strokeColorTop,
        const Color(0xFFFFFFFF),
      );
      expect(
        GlassSurfaceStyle.themed(resources: res, colorKey: 2).strokeColorTop,
        const Color(0x28FFFFFF),
      );
    });

    test('frosted tier defaults alpha to 0.76; explicit alpha wins (lines 15-22)', () {
      const _FixedResources res = _FixedResources(<int, Color>{key: Color(0xFFFFFFFF)});
      final GlassSurfaceStyle frosted = GlassSurfaceStyle.themed(
        resources: res,
        colorKey: key,
        tier: GlassTier.frosted,
      );
      expect(frosted.tintAlpha, 0.76);
      expect(frosted.backgroundColor.toARGB32(), multAlpha(0xFFFFFFFF, 0.76));

      final GlassSurfaceStyle custom = GlassSurfaceStyle.themed(
        resources: res,
        colorKey: key,
        alpha: 0.5,
        tier: GlassTier.frosted,
      );
      expect(custom.tintAlpha, 0.5);
      expect(custom.backgroundColor.toARGB32(), multAlpha(0xFFFFFFFF, 0.5));
    });
  });

  group('GlassSurfaceStyleBuilder (BlurredBackgroundProviderBuilder.java)', () {
    test('constructor defaults: shadow (1, 0, 1/3)dp, strokes (1, 2/3)dp (lines 15-16)', () {
      final GlassSurfaceStyle style = GlassSurfaceStyleBuilder(dayRes).build();
      expect(style.shadowRadius, 1.0);
      expect(style.shadowDx, 0.0);
      expect(style.shadowDy, 1 / 3);
      expect(style.strokeWidthTop, 1.0);
      expect(style.strokeWidthBottom, 2 / 3);
      // Unset colors resolve to transparent (Java get(provider, 0), 114-116).
      expect(style.backgroundColor, const Color(0x00000000));
      expect(style.strokeColorTop, const Color(0x00000000));
      expect(style.strokeColorBottom, const Color(0x00000000));
      expect(style.shadowColor, const Color(0x00000000));
      expect(style.tintAlpha, 0.0);
    });

    test('(light, dark) pairs resolve by resources.isDark (lines 29-42, 114-125)', () {
      GlassSurfaceStyleBuilder recipe(TelegramResources res) => GlassSurfaceStyleBuilder(res)
          .setStrokeColorTop(0x11111111, 0x22222222)
          .setStrokeColorBottom(0x33333333, 0x44444444)
          .setShadowColor(0x55555555, 0x66666666);
      final GlassSurfaceStyle light = recipe(dayRes).build();
      expect(light.strokeColorTop, const Color(0x11111111));
      expect(light.strokeColorBottom, const Color(0x33333333));
      expect(light.shadowColor, const Color(0x55555555));
      final GlassSurfaceStyle dark = recipe(nightRes).build();
      expect(dark.strokeColorTop, const Color(0x22222222));
      expect(dark.strokeColorBottom, const Color(0x44444444));
      expect(dark.shadowColor, const Color(0x66666666));
    });

    test('background provider receives the resources and the resolved isDark', () {
      TelegramResources? seenResources;
      bool? seenIsDark;
      final GlassSurfaceStyle style = GlassSurfaceStyleBuilder(nightRes)
          .setBackgroundColor((r, isDark) {
            seenResources = r;
            seenIsDark = isDark;
            return 0xAABBCCDD;
          })
          .build();
      expect(seenResources, same(nightRes));
      expect(seenIsDark, isTrue);
      expect(style.backgroundColor, const Color(0xAABBCCDD));
    });

    test('copyWith and value equality', () {
      final GlassSurfaceStyle a = GlassPresets.mainTabs(dayRes);
      final GlassSurfaceStyle b = GlassPresets.mainTabs(dayRes);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == GlassPresets.mainTabs(nightRes), isFalse);
      final GlassSurfaceStyle widened = a.copyWith(strokeWidthTop: 2.0);
      expect(widened.strokeWidthTop, 2.0);
      expect(widened.strokeColorTop, a.strokeColorTop);
      expect(widened == a, isFalse);
    });
  });
}
