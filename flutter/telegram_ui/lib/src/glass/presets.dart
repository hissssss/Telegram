// The per-surface glass color recipes of the Android app.
//
// Port of every factory in
// `java/org/telegram/ui/Components/blur3/drawable/color/impl/BlurredBackgroundProviderImpl.java`
// (all hex constants verbatim, cited by line). Each Java factory builds a
// live `BlurredBackgroundProvider`; the Dart port resolves it eagerly into a
// [GlassSurfaceStyle] for the given [TelegramResources] + [GlassTier].
//
// Two pieces of Android global state are mapped onto [GlassTier]:
// - `LiteMode.isEnabled(LiteMode.FLAG_LIQUID_GLASS)` — selects the tint
//   alpha, 0.85 liquid / 0.76 otherwise. Port: `tier == GlassTier.liquid`.
// - `checkBlurEnabled(...)` (lines 318-337; SharedConfig.chatBlurEnabled
//   plus the per-brightness server kill-switches) — when false, the chat
//   panels fall back to a fully opaque theme color. Port:
//   `tier == GlassTier.flat`, the no-backdrop floor of the ladder.
//
// Stroke widths and shadow metrics are logical dp — the Java sources wrap
// the same numbers in `dpf2()` (physical px) at draw time.
library;

import '../foundation/color_math.dart';
import '../theme/telegram_resources.dart';
import '../tokens/glass_metrics.g.dart';
import '../tokens/theme_keys.g.dart';
import 'strategy.dart';
import 'surface_colors.dart';

/// Resolves a preset into a style — the shape of every [GlassPresets]
/// factory, so surfaces can take a preset reference as a parameter
/// (e.g. `GlassPanel(style: GlassPresets.mainTabs)`).
typedef GlassSurfaceStyleResolver = GlassSurfaceStyle Function(
  TelegramResources resources, {
  GlassTier tier,
});

/// Static port of `BlurredBackgroundProviderImpl` — one factory per
/// production glass surface, exact constants.
abstract final class GlassPresets {
  /// `LiteMode.isEnabled(LiteMode.FLAG_LIQUID_GLASS) ? 0.85f : 0.76f` — the
  /// tint alpha shared by most recipes (e.g. lines 22, 38, 54).
  static double _tintAlpha(GlassTier tier) =>
      tier == GlassTier.liquid ? kGlassTintAlphaLiquid : kGlassTintAlphaFrosted;

  /// `checkBlurEnabled(resourcesProvider)` (lines 318-337) mapped onto the
  /// tier ladder: only [GlassTier.flat] renders with blur disabled.
  static bool _blurEnabled(GlassTier tier) => tier != GlassTier.flat;

  /// `ColorUtils.setAlphaComponent(color, 255)` — the opaque fallback of the
  /// blur-disabled branches (lines 122, 141, 177).
  static int _opaque(int color) => 0xFF000000 | (color & 0x00FFFFFF);

  /// `mainTabs` (lines 19-33) — the floating main tab bar pill.
  ///
  /// Background: `solveSrcColor(windowBackgroundWhite ->
  /// glass_targetMainTabs @ 0.85/0.76)` (lines 22-25) — the tint that
  /// composites over the window background to land exactly on the target.
  /// Strokes top `0x11000000`/`0x06FFFFFF`, bottom `0x20000000`/`0x11FFFFFF`;
  /// shadow `0x20000000`/`0x04FFFFFF`, radius 2.667dp, dy 0.85dp; widths
  /// 0.4dp/0.4dp (lines 27-31; generated `kMainTabs*` constants).
  static GlassSurfaceStyle mainTabs(
    TelegramResources resources, {
    GlassTier tier = GlassTier.liquid,
  }) {
    final double alpha = _tintAlpha(tier);
    return GlassSurfaceStyleBuilder(resources)
        .setBackgroundColor((r, isDark) => solveSrcColor(
              r.getColor(TelegramColorKey.windowBackgroundWhite).toARGB32(),
              r.getColor(TelegramColorKey.glass_targetMainTabs).toARGB32(),
              alpha,
            ))
        .setStrokeColorTop(kMainTabsStrokeTopColorLight, kMainTabsStrokeTopColorDark)
        .setStrokeColorBottom(kMainTabsStrokeBottomColorLight, kMainTabsStrokeBottomColorDark)
        .setShadowColor(kMainTabsShadowColorLight, kMainTabsShadowColorDark)
        .setShadowLayer(kMainTabsShadowRadiusDp, kMainTabsShadowDxDp, kMainTabsShadowDyDp)
        .setStrokeWidth(kMainTabsStrokeWidthTopDp, kMainTabsStrokeWidthBottomDp)
        .setTintAlpha(alpha)
        .build();
  }

  /// `topPanel` (lines 35-49) — the main-screen top panel; identical
  /// constants to [mainTabs] (lines 43-47) with the solve target
  /// `glass_targetMainTopPanel` (line 40).
  static GlassSurfaceStyle topPanel(
    TelegramResources resources, {
    GlassTier tier = GlassTier.liquid,
  }) {
    final double alpha = _tintAlpha(tier);
    return GlassSurfaceStyleBuilder(resources)
        .setBackgroundColor((r, isDark) => solveSrcColor(
              r.getColor(TelegramColorKey.windowBackgroundWhite).toARGB32(),
              r.getColor(TelegramColorKey.glass_targetMainTopPanel).toARGB32(),
              alpha,
            ))
        .setStrokeColorTop(kMainTabsStrokeTopColorLight, kMainTabsStrokeTopColorDark)
        .setStrokeColorBottom(kMainTabsStrokeBottomColorLight, kMainTabsStrokeBottomColorDark)
        .setShadowColor(kMainTabsShadowColorLight, kMainTabsShadowColorDark)
        .setShadowLayer(kMainTabsShadowRadiusDp, kMainTabsShadowDxDp, kMainTabsShadowDyDp)
        .setStrokeWidth(kMainTabsStrokeWidthTopDp, kMainTabsStrokeWidthBottomDp)
        .setTintAlpha(alpha)
        .build();
  }

  /// `emojiViewButton` (lines 51-64) — the round button over the emoji view.
  ///
  /// Background `multAlpha(windowBackgroundWhite, 0.85/0.76)` (lines 54-56);
  /// strokes white/white light, `0x28FFFFFF`/`0x14FFFFFF` dark; shadow
  /// `0x40000000`/0, radius (11/3)dp, dy (2/3)dp; widths 0.5dp (lines 58-62).
  static GlassSurfaceStyle emojiViewButton(
    TelegramResources resources, {
    GlassTier tier = GlassTier.liquid,
  }) {
    final double alpha = _tintAlpha(tier);
    return GlassSurfaceStyleBuilder(resources)
        .setBackgroundColor((r, isDark) => multAlpha(
              r.getColor(TelegramColorKey.windowBackgroundWhite).toARGB32(),
              alpha,
            ))
        .setStrokeColorTop(0xFFFFFFFF, 0x28FFFFFF)
        .setStrokeColorBottom(0xFFFFFFFF, 0x14FFFFFF)
        .setShadowColor(0x40000000, 0)
        .setShadowLayer(11 / 3, 0, 2 / 3)
        .setStrokeWidth(0.5, 0.5)
        .setTintAlpha(alpha)
        .build();
  }

  /// `counterMini` (lines 66-79) — the miniature unread counter chip.
  ///
  /// Background `multAlpha(BLACK, 0.075)` regardless of theme (lines 68-72);
  /// strokes top `0x60FFFFFF`/`0x50FFFFFF`, bottom `0x24000000` both; no
  /// shadow (color 0, layer 0); widths 0.43dp (lines 73-77). [tier] is
  /// unused — the Java recipe consults no LiteMode state.
  static GlassSurfaceStyle counterMini(
    TelegramResources resources, {
    GlassTier tier = GlassTier.liquid,
  }) {
    const double alpha = 0.075;
    return GlassSurfaceStyleBuilder(resources)
        .setBackgroundColor((r, isDark) => multAlpha(0xFF000000, alpha))
        .setStrokeColorTop(0x60FFFFFF, 0x50FFFFFF)
        .setStrokeColorBottom(0x24000000, 0x24000000)
        .setShadowColor(0, 0)
        .setShadowLayer(0, 0, 0)
        .setStrokeWidth(0.43, 0.43)
        .setTintAlpha(alpha)
        .build();
  }

  /// `scrimMenuBackground` (lines 81-91) — popup menus over a scrim.
  ///
  /// Background `multAlpha(actionBarDefaultSubmenuBackground,
  /// isDark ? 0.85 : 0.76)` (lines 83-84) — note the alpha branches on the
  /// *palette*, not on LiteMode, so [tier] is unused. Strokes white/0 (both
  /// pairs); shadow `0x26000000`/0, radius 4dp, dy 0; widths (2/3)dp
  /// (lines 85-89).
  ///
  /// Port note: the Java call omits the `resourcesProvider` argument on
  /// `Theme.getColor` (line 84 reads the *global* theme, an upstream
  /// oversight); the port resolves through [resources] like every other
  /// recipe — there is no global palette here.
  static GlassSurfaceStyle scrimMenu(
    TelegramResources resources, {
    GlassTier tier = GlassTier.liquid,
  }) {
    final bool isDark = resources.isDark;
    final double alpha = isDark ? 0.85 : 0.76;
    return GlassSurfaceStyleBuilder(resources)
        .setBackgroundColor((r, dark) => multAlpha(
              r.getColor(TelegramColorKey.actionBarDefaultSubmenuBackground).toARGB32(),
              dark ? 0.85 : 0.76,
            ))
        .setStrokeColorTop(0xFFFFFFFF, 0)
        .setStrokeColorBottom(0xFFFFFFFF, 0)
        .setShadowColor(0x26000000, 0)
        .setShadowLayer(4, 0, 0)
        .setStrokeWidth(2 / 3, 2 / 3)
        .setTintAlpha(alpha)
        .build();
  }

  /// `attachMenuSearch` (lines 93-106) — the attach sheet's search field.
  ///
  /// Background `multAlpha(windowBackgroundWhite, 0.85/0.76)` (lines 96-98);
  /// strokes `0x17000000`/`0x17FFFFFF` (both pairs); shadow
  /// `0x11000000`/`0x04FFFFFF`, radius 2dp, dy (1/3)dp; widths 0.4dp
  /// (lines 100-104).
  static GlassSurfaceStyle attachMenuSearch(
    TelegramResources resources, {
    GlassTier tier = GlassTier.liquid,
  }) {
    final double alpha = _tintAlpha(tier);
    return GlassSurfaceStyleBuilder(resources)
        .setBackgroundColor((r, isDark) => multAlpha(
              r.getColor(TelegramColorKey.windowBackgroundWhite).toARGB32(),
              alpha,
            ))
        .setStrokeColorTop(0x17000000, 0x17FFFFFF)
        .setStrokeColorBottom(0x17000000, 0x17FFFFFF)
        .setShadowColor(0x11000000, 0x04FFFFFF)
        .setShadowLayer(2, 0, 1 / 3)
        .setStrokeWidth(0.4, 0.4)
        .setTintAlpha(alpha)
        .build();
  }

  /// `searchFloatingDate` (lines 108-116) — the floating date chip in
  /// calendar search.
  ///
  /// Fixed `0x33000000` background in both palettes (line 110); strokes
  /// `0x17000000`/`0x17FFFFFF`; no shadow color; shadow layer stays at the
  /// builder default (1, 0, 1/3)dp — the Java recipe never calls
  /// `setShadowLayer`. Widths: Java passes a raw `1` px (line 114, not
  /// `dpf2(1)`), preserved here as 1.0. [tier] is unused.
  static GlassSurfaceStyle searchFloatingDate(
    TelegramResources resources, {
    GlassTier tier = GlassTier.liquid,
  }) {
    return GlassSurfaceStyleBuilder(resources)
        .setBackgroundColor((r, isDark) => 0x33000000)
        .setStrokeColorTop(0x17000000, 0x17FFFFFF)
        .setStrokeColorBottom(0x17000000, 0x17FFFFFF)
        .setShadowColor(0, 0)
        .setStrokeWidth(1, 1)
        .setTintAlpha(0x33 / 0xFF)
        .build();
  }

  /// `bottomPanelChatActivity` (lines 118-135) — the chat input panel.
  ///
  /// Background `multAlpha(chat_messagePanelBackground, 0.85/0.76)`
  /// (lines 125-127); blur disabled ([GlassTier.flat]) falls back to the
  /// opaque panel color (lines 121-123). Strokes white/white light,
  /// `0x28FFFFFF`/`0x14FFFFFF` dark; shadow `0x20000000`/0 with the layer
  /// left at the builder default — the `setShadowLayer` call is commented
  /// out in Java (line 132). Widths 0.5dp (lines 129-133).
  static GlassSurfaceStyle bottomPanelChat(
    TelegramResources resources, {
    GlassTier tier = GlassTier.liquid,
  }) {
    final bool blurEnabled = _blurEnabled(tier);
    final double alpha = _tintAlpha(tier);
    return GlassSurfaceStyleBuilder(resources)
        .setBackgroundColor((r, isDark) {
          final int colorBg = r.getColor(TelegramColorKey.chat_messagePanelBackground).toARGB32();
          if (!blurEnabled) {
            return _opaque(colorBg);
          }
          return multAlpha(colorBg, alpha);
        })
        .setStrokeColorTop(0xFFFFFFFF, 0x28FFFFFF)
        .setStrokeColorBottom(0xFFFFFFFF, 0x14FFFFFF)
        .setShadowColor(0x20000000, 0)
        .setStrokeWidth(0.5, 0.5)
        .setTintAlpha(blurEnabled ? alpha : 1.0)
        .build();
  }

  /// `topPanelChatActivity` (lines 137-155) — the chat top panel (pinned
  /// messages / reply bar).
  ///
  /// Background `multAlpha(chat_topPanelBackground, 0.85/0.76)`
  /// (lines 145-147); blur disabled falls back to the opaque
  /// `actionBarDefault` (dark) or `chat_topPanelBackground` (light)
  /// (lines 140-143). Strokes white/`0x20FFFFFF` top, white/`0x14FFFFFF`
  /// bottom; shadow `0x20000000`/0, layer at the builder default (commented
  /// out, line 152); widths 0.55dp (lines 149-153).
  static GlassSurfaceStyle topPanelChat(
    TelegramResources resources, {
    GlassTier tier = GlassTier.liquid,
  }) {
    final bool blurEnabled = _blurEnabled(tier);
    final double alpha = _tintAlpha(tier);
    return GlassSurfaceStyleBuilder(resources)
        .setBackgroundColor((r, isDark) {
          if (!blurEnabled) {
            return _opaque(r
                .getColor(isDark
                    ? TelegramColorKey.actionBarDefault
                    : TelegramColorKey.chat_topPanelBackground)
                .toARGB32());
          }
          return multAlpha(
            r.getColor(TelegramColorKey.chat_topPanelBackground).toARGB32(),
            alpha,
          );
        })
        .setStrokeColorTop(0xFFFFFFFF, 0x20FFFFFF)
        .setStrokeColorBottom(0xFFFFFFFF, 0x14FFFFFF)
        .setShadowColor(0x20000000, 0)
        .setStrokeWidth(0.55, 0.55)
        .setTintAlpha(blurEnabled ? alpha : 1.0)
        .build();
  }

  /// `attachMenuActionBar` (lines 157-171) — the attach sheet's expanded
  /// action bar.
  ///
  /// Background `solveSrcColor((isDark ? windowBackgroundGray :
  /// dialogBackgroundGray) -> windowBackgroundWhite @ 0.85/0.76)`
  /// (lines 160-163); strokes white/white light, `0x28FFFFFF`/`0x14FFFFFF`
  /// dark; shadow `0x20000000`/0, layer at the builder default (commented
  /// out, line 168); widths 1dp top, (2/3)dp bottom (lines 165-169).
  static GlassSurfaceStyle attachMenuActionBar(
    TelegramResources resources, {
    GlassTier tier = GlassTier.liquid,
  }) {
    final double alpha = _tintAlpha(tier);
    return GlassSurfaceStyleBuilder(resources)
        .setBackgroundColor((r, isDark) => solveSrcColor(
              r
                  .getColor(isDark
                      ? TelegramColorKey.windowBackgroundGray
                      : TelegramColorKey.dialogBackgroundGray)
                  .toARGB32(),
              r.getColor(TelegramColorKey.windowBackgroundWhite).toARGB32(),
              alpha,
            ))
        .setStrokeColorTop(0xFFFFFFFF, 0x28FFFFFF)
        .setStrokeColorBottom(0xFFFFFFFF, 0x14FFFFFF)
        .setShadowColor(0x20000000, 0)
        .setStrokeWidth(1, 2 / 3)
        .setTintAlpha(alpha)
        .build();
  }

  /// `topPanelChatActivityTags` (lines 173-191) — the saved-messages tag
  /// row: the [topPanelChat] background with every stroke, shadow, and width
  /// zeroed (lines 185-189).
  static GlassSurfaceStyle topPanelChatTags(
    TelegramResources resources, {
    GlassTier tier = GlassTier.liquid,
  }) {
    final bool blurEnabled = _blurEnabled(tier);
    final double alpha = _tintAlpha(tier);
    return GlassSurfaceStyleBuilder(resources)
        .setBackgroundColor((r, isDark) {
          if (!blurEnabled) {
            return _opaque(r
                .getColor(isDark
                    ? TelegramColorKey.actionBarDefault
                    : TelegramColorKey.chat_topPanelBackground)
                .toARGB32());
          }
          return multAlpha(
            r.getColor(TelegramColorKey.chat_topPanelBackground).toARGB32(),
            alpha,
          );
        })
        .setStrokeColorTop(0, 0)
        .setStrokeColorBottom(0, 0)
        .setShadowColor(0, 0)
        .setShadowLayer(0, 0, 0)
        .setStrokeWidth(0, 0)
        .setTintAlpha(blurEnabled ? alpha : 1.0)
        .build();
  }

  /// `topPanelChatActivitySearchListBg` (lines 193-206) — the search
  /// results list backdrop: `multAlpha(windowBackgroundWhite, 0.7)`
  /// (lines 196-198) with everything else zeroed (lines 200-204). [tier]
  /// is unused.
  static GlassSurfaceStyle topPanelChatSearchList(
    TelegramResources resources, {
    GlassTier tier = GlassTier.liquid,
  }) {
    const double alpha = 0.7;
    return GlassSurfaceStyleBuilder(resources)
        .setBackgroundColor((r, isDark) => multAlpha(
              r.getColor(TelegramColorKey.windowBackgroundWhite).toARGB32(),
              alpha,
            ))
        .setStrokeColorTop(0, 0)
        .setStrokeColorBottom(0, 0)
        .setShadowColor(0, 0)
        .setShadowLayer(0, 0, 0)
        .setStrokeWidth(0, 0)
        .setTintAlpha(alpha)
        .build();
  }

  /// `bulletin` (lines 208-221) — the undo/toast bulletin.
  ///
  /// Background `multAlpha(undo_background, 0.85/0.76)` (lines 210-213);
  /// stroke and shadow colors stay unset (the Java calls are commented out,
  /// lines 215-218) so they resolve transparent, with the shadow layer at
  /// the builder default; widths 0.5dp (line 219).
  static GlassSurfaceStyle bulletin(
    TelegramResources resources, {
    GlassTier tier = GlassTier.liquid,
  }) {
    final double alpha = _tintAlpha(tier);
    return GlassSurfaceStyleBuilder(resources)
        .setBackgroundColor((r, isDark) => multAlpha(
              r.getColor(TelegramColorKey.undo_background).toARGB32(),
              alpha,
            ))
        .setStrokeWidth(0.5, 0.5)
        .setTintAlpha(alpha)
        .build();
  }

  /// `inputFieldDialogActivity` (lines 223-225) — delegates to [topPanel]
  /// verbatim.
  static GlassSurfaceStyle inputFieldDialog(
    TelegramResources resources, {
    GlassTier tier = GlassTier.liquid,
  }) =>
      topPanel(resources, tier: tier);

  /// `inputFieldShareAlert` (lines 227-241) — the share sheet's comment
  /// field.
  ///
  /// Background `solveSrcColor(windowBackgroundWhite ->
  /// chat_messagePanelBackground @ 0.85/0.76)` (lines 230-233); strokes
  /// `0x28FFFFFF` top / `0x14FFFFFF` bottom in both palettes; shadow
  /// `0x20000000`/0, radius (10/3)dp, dy (2/3)dp; widths 1dp top, (2/3)dp
  /// bottom (lines 235-239).
  static GlassSurfaceStyle inputFieldShareAlert(
    TelegramResources resources, {
    GlassTier tier = GlassTier.liquid,
  }) {
    final double alpha = _tintAlpha(tier);
    return GlassSurfaceStyleBuilder(resources)
        .setBackgroundColor((r, isDark) => solveSrcColor(
              r.getColor(TelegramColorKey.windowBackgroundWhite).toARGB32(),
              r.getColor(TelegramColorKey.chat_messagePanelBackground).toARGB32(),
              alpha,
            ))
        .setStrokeColorTop(0x28FFFFFF, 0x28FFFFFF)
        .setStrokeColorBottom(0x14FFFFFF, 0x14FFFFFF)
        .setShadowColor(0x20000000, 0)
        .setShadowLayer(10 / 3, 0, 2 / 3)
        .setStrokeWidth(1, 2 / 3)
        .setTintAlpha(alpha)
        .build();
  }

  /// `photoViewer` (lines 243-255) — photo viewer chrome.
  ///
  /// The Java background provider returns `0` — its `solveSrcColor(black ->
  /// 0xFF1A1A1A)` expression is commented out (lines 245-250) — so the
  /// surface has no tint. Strokes `0x28FFFFFF` top / `0x14FFFFFF` bottom in
  /// both palettes; no shadow color; widths (2/3)dp (lines 251-253). [tier]
  /// is unused.
  static GlassSurfaceStyle photoViewer(
    TelegramResources resources, {
    GlassTier tier = GlassTier.liquid,
  }) {
    return GlassSurfaceStyleBuilder(resources)
        .setBackgroundColor((r, isDark) => 0)
        .setStrokeColorTop(0x28FFFFFF, 0x28FFFFFF)
        .setStrokeColorBottom(0x14FFFFFF, 0x14FFFFFF)
        .setStrokeWidth(2 / 3, 2 / 3)
        .build();
  }

  /// `photoViewerMenu` (lines 257-264) — the photo viewer's popup menu:
  /// fixed `0x40000000` background (line 259), otherwise identical to
  /// [photoViewer]. [tier] is unused.
  static GlassSurfaceStyle photoViewerMenu(
    TelegramResources resources, {
    GlassTier tier = GlassTier.liquid,
  }) {
    return GlassSurfaceStyleBuilder(resources)
        .setBackgroundColor((r, isDark) => 0x40000000)
        .setStrokeColorTop(0x28FFFFFF, 0x28FFFFFF)
        .setStrokeColorBottom(0x14FFFFFF, 0x14FFFFFF)
        .setStrokeWidth(2 / 3, 2 / 3)
        .setTintAlpha(0x40 / 0xFF)
        .build();
  }

  /// `premiumButton` (lines 266-276) — the floating premium CTA.
  ///
  /// Background `multAlpha(dialogBackground, 0.78)` (lines 268-269); strokes
  /// top white/`0x20FFFFFF`, bottom 0/`0x20FFFFFF`; shadow
  /// `0x30000000`/`0x04FFFFFF`, radius (12/3)dp, dy (1/3)dp; widths 0.67dp
  /// (lines 270-274). [tier] is unused.
  static GlassSurfaceStyle premiumButton(
    TelegramResources resources, {
    GlassTier tier = GlassTier.liquid,
  }) {
    const double alpha = 0.78;
    return GlassSurfaceStyleBuilder(resources)
        .setBackgroundColor((r, isDark) => multAlpha(
              r.getColor(TelegramColorKey.dialogBackground).toARGB32(),
              alpha,
            ))
        .setStrokeColorTop(0xFFFFFFFF, 0x20FFFFFF)
        .setStrokeColorBottom(0, 0x20FFFFFF)
        .setShadowColor(0x30000000, 0x04FFFFFF)
        .setShadowLayer(12 / 3, 0, 1 / 3)
        .setStrokeWidth(0.67, 0.67)
        .setTintAlpha(alpha)
        .build();
  }

  /// `shadow` (lines 278-286) — stroke-and-shadow-only chrome with no
  /// background at all.
  ///
  /// Strokes 0/`0x28FFFFFF` top, 0/`0x14FFFFFF` bottom; shadow
  /// `0x30000000`/`0x04FFFFFF`, radius (12/3)dp, dy (1/3)dp; widths 0.4dp
  /// (lines 280-284). [tier] is unused.
  static GlassSurfaceStyle shadow(
    TelegramResources resources, {
    GlassTier tier = GlassTier.liquid,
  }) {
    return GlassSurfaceStyleBuilder(resources)
        .setStrokeColorTop(0, 0x28FFFFFF)
        .setStrokeColorBottom(0, 0x14FFFFFF)
        .setShadowColor(0x30000000, 0x04FFFFFF)
        .setShadowLayer(12 / 3, 0, 1 / 3)
        .setStrokeWidth(0.4, 0.4)
        .build();
  }
}
