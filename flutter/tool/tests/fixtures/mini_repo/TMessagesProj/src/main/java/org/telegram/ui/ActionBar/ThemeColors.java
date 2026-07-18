/*
 * Vendored fixture: a miniature ThemeColors.java exercising every RHS shape
 * and comment style that gen_tokens.py Pass 2 / Pass 3 must handle.
 */
package org.telegram.ui.ActionBar;

import static org.telegram.ui.ActionBar.Theme.*;

public class ThemeColors {

    public static final int TELEGRAM_COLOR = 0xFF229AF0;        // -14509328
    public static final int TELEGRAM_COLOR_TEXT = 0xFF298ACF;   // -14054705
    public static final int DEFAULT_BLACK_TEXT = 0xFF1A1D21;   // -15065823

    public static int[] createDefaultColors() {
        int[] defaultColors = new int[Theme.colorsCount];

        defaultColors[key_wallpaperFileOffset] = 0;
        defaultColors[key_dialogBackground] = 0xffffffff;
        defaultColors[key_windowBackgroundWhite] = 0xffffffff; // trailing comment
        defaultColors[key_windowBackgroundGray] = 0xfff1f1f3;
        defaultColors[key_actionBarDefault] = DEFAULT_BLACK_TEXT;
        /* block comment on its own line */
        defaultColors[key_actionBarDefaultArchived] = -14513153;
        defaultColors[key_listSelector] = 0x121A1D21;
        defaultColors[key_graySectionText] = 0xff82868a;
        defaultColors[key_windowBackgroundWhiteGrayText2] = 0xff808384;
        defaultColors[key_chat_inBubble] = TELEGRAM_COLOR_TEXT;
        defaultColors[key_premiumStartSmallStarsColor] = ColorUtils.setAlphaComponent(Color.WHITE, 90);
        defaultColors[key_telegram_color] = TELEGRAM_COLOR;
        // duplicate assignment: Java array store semantics, last write wins
        defaultColors[key_graySectionText] = 0xff9A9C9E;
        defaultColors[key_glass_tabSelected] = 0xFF1A91E6;

        return defaultColors;
    }

    public static SparseArray<String> createColorKeysMap() {
        SparseArray<String> colorKeysMap = new SparseArray<>();
        colorKeysMap.put(key_wallpaperFileOffset, "wallpaperFileOffset");
        colorKeysMap.put(key_dialogBackground, "dialogBackground");
        colorKeysMap.put(key_windowBackgroundWhite, "windowBackgroundWhite");
        colorKeysMap.put(key_windowBackgroundGray, "windowBackgroundGray");
        colorKeysMap.put(key_actionBarDefault, "actionBarDefault");
        colorKeysMap.put(key_actionBarDefaultArchived, "actionBarDefaultArchived");
        colorKeysMap.put(key_listSelector, "listSelectorSDK21");
        colorKeysMap.put(key_graySectionText, "key_graySectionText");
        colorKeysMap.put(key_windowBackgroundWhiteGrayText2, "windowBackgroundWhiteGrayText2");
        colorKeysMap.put(key_chat_inBubble, "chat_inBubble");
        colorKeysMap.put(key_chat_serviceBackground, "chat_serviceBackground");
        colorKeysMap.put(key_telegram_color, "telegram_color");
        colorKeysMap.put(key_glass_tabSelected, "glass_tabSelected");
        return colorKeysMap;
    }
}
