/*
 * Vendored fixture: a miniature Theme.java exercising every shape that
 * gen_tokens.py Pass 1 / Pass 3 must handle. Not real Telegram code.
 */
package org.telegram.ui.ActionBar;

public class Theme {

    public static int colorsCount;

    public static final int key_wallpaperFileOffset = colorsCount++;
    public static final int key_dialogBackground = colorsCount++;
    // an interleaved comment between declarations must not shift ordinals
    public static final int key_windowBackgroundWhite = colorsCount++;
    public static final int key_windowBackgroundGray = colorsCount++;
    public static final int key_actionBarDefault = colorsCount++;
    public static final int key_actionBarDefaultArchived = colorsCount++;
    public static final int key_listSelector = colorsCount++;
    public static final int key_graySectionText = colorsCount++;
    public static final int key_windowBackgroundWhiteGrayText2 = colorsCount++;
    public static final int key_chat_inBubble = colorsCount++;
    public static final int key_chat_serviceBackground = colorsCount++;
    public static final int key_premiumStartSmallStarsColor = colorsCount++;
    public static final int key_telegram_color = colorsCount++;
    public static final int key_glass_tabSelected = colorsCount++;

    private static int[] defaultColors;
    private static SparseIntArray fallbackKeys = new SparseIntArray();

    static {
        defaultColors = ThemeColors.createDefaultColors();

        fallbackKeys.put(key_graySectionText, key_windowBackgroundWhiteGrayText2);
        fallbackKeys.put(key_chat_serviceBackground, key_chat_inBubble);
        fallbackKeys.put(key_glass_tabSelected, Theme.key_telegram_color);
        // duplicate put: SparseIntArray overwrites, so the last one wins
        fallbackKeys.put(key_chat_serviceBackground, key_dialogBackground);

        ThemeInfo themeInfo = new ThemeInfo();
        themeInfo.name = "Mini Blue";
        themeInfo.assetName = "mini_blue.attheme";
        themes.add(themeInfo);

        themeInfo = new ThemeInfo();
        themeInfo.name = "Mini Night";
        themeInfo.assetName = "mini_night.attheme";
        themes.add(themeInfo);

        themeInfo = new ThemeInfo();
        themeInfo.name = "Mini Wall";
        themeInfo.assetName = "mini_wall.attheme";
        themes.add(themeInfo);
    }

    public static int getColor(int key, boolean[] isDefault, boolean ignoreAnimation) {
        int color = currentColors.valueAt(0);
        if (key_windowBackgroundWhite == key || key_windowBackgroundGray == key || key_actionBarDefault == key || key_actionBarDefaultArchived == key) {
            color |= 0xff000000;
        }
        return color;
    }
}
