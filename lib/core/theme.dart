import 'package:flutter/material.dart';

/// SDMS design v2 - "A · Western Clean" in the web's green.
/// Same palette as the web login (index.css): green-800 / 600 / 700, gold accent.
class AppColors {
  // brand
  static const Color primary = Color(0xFF198754); // buttons, links, focus
  static const Color primaryDark = Color(0xFF0F5132); // headers, selected tab, hero
  static const Color primaryDeep = Color(0xFF0A3D26);
  static const Color pressed = Color(0xFF146C43);
  static const Color accent = Color(0xFF20C997);
  static const Color gold = Color(0xFFD4AF37);
  static const Color soft = Color(0xFFE8F3EC);

  // status / charts
  static const Color danger = Color(0xFFDC3545);
  static const Color dangerSoft = Color(0xFFFDECEE);
  static const Color warn = Color(0xFFE8890C);
  static const Color info = Color(0xFF2A78D6);
  static const Color done = Color(0xFF20A878);
  static const Color muted = Color(0xFF6C757D);
  static const Color other = Color(0xFFCED4DA);

  // light surfaces
  static const Color lightBg = Color(0xFFF6F8FA);
  static const Color lightCard = Colors.white;
  static const Color lightBorder = Color(0xFFE9ECEF);
  static const Color lightInk = Color(0xFF1A1D21);

  // dark surfaces
  static const Color darkBg = Color(0xFF0B1510);
  static const Color darkCard = Color(0xFF121F18);
  static const Color darkBorder = Color(0xFF22372B);
  static const Color darkAccent = Color(0xFF5FE0B8);
  static const Color darkInk = Color(0xFFE6EFEA);

  static bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

  /// card / header surface for the current theme
  static Color card(BuildContext c) => isDark(c) ? darkCard : lightCard;

  /// page background for the current theme
  static Color bg(BuildContext c) => isDark(c) ? darkBg : lightBg;

  /// hairline border for the current theme
  static Color border(BuildContext c) => isDark(c) ? darkBorder : lightBorder;

  /// soft green tint behind icons / info boxes
  static Color softOf(BuildContext c) => isDark(c) ? const Color(0xFF1B3A2C) : soft;

  /// strong brand colour for text on the current surface
  static Color strong(BuildContext c) => isDark(c) ? darkAccent : primaryDark;

  /// brand colour readable on the current surface (dark mode uses the mint accent)
  static Color brand(BuildContext c) => isDark(c) ? darkAccent : primary;
}

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;

    final scheme = (dark
            ? const ColorScheme.dark(
                primary: AppColors.darkAccent,
                onPrimary: Color(0xFF06281C),
                primaryContainer: Color(0xFF1B3A2C),
                onPrimaryContainer: Color(0xFFCFF5E6),
                secondary: AppColors.gold,
                onSecondary: Color(0xFF2A2100),
                surface: AppColors.darkCard,
                onSurface: AppColors.darkInk,
                onSurfaceVariant: Color(0xFF9DB1A6),
                outline: Color(0xFF3A5546),
                outlineVariant: AppColors.darkBorder,
                error: Color(0xFFFF8A94),
              )
            : const ColorScheme.light(
                primary: AppColors.primary,
                onPrimary: Colors.white,
                primaryContainer: AppColors.soft,
                onPrimaryContainer: AppColors.primaryDark,
                secondary: AppColors.gold,
                onSecondary: Color(0xFF2A2100),
                surface: Colors.white,
                onSurface: AppColors.lightInk,
                onSurfaceVariant: AppColors.muted,
                outline: Color(0xFFCED4DA),
                outlineVariant: AppColors.lightBorder,
                error: AppColors.danger,
              ))
        .copyWith(
      surfaceContainerLowest: dark ? AppColors.darkBg : Colors.white,
      surfaceContainerLow: dark ? AppColors.darkCard : const Color(0xFFF8FAFB),
      surfaceContainer: dark ? AppColors.darkCard : const Color(0xFFF1F4F6),
      surfaceContainerHigh: dark ? const Color(0xFF182A20) : const Color(0xFFECF0F2),
      surfaceContainerHighest: dark ? const Color(0xFF1E3328) : const Color(0xFFE9ECEF),
    );

    final base = ThemeData(brightness: brightness, colorScheme: scheme, useMaterial3: true);
    // system fonts: Android and iOS both ship a Khmer font, nothing to download
    final text = base.textTheme;
    final bg = dark ? AppColors.darkBg : AppColors.lightBg;
    final card = dark ? AppColors.darkCard : AppColors.lightCard;
    final border = dark ? AppColors.darkBorder : AppColors.lightBorder;
    final fieldBorder = dark ? const Color(0xFF2E4A3B) : const Color(0xFFCED4DA);

    OutlineInputBorder outline(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: bg,
      appBarTheme: AppBarTheme(
        backgroundColor: card,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: border)),
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: outline(fieldBorder),
        enabledBorder: outline(fieldBorder),
        focusedBorder: outline(scheme.primary, 1.6),
        errorBorder: outline(AppColors.danger),
        focusedErrorBorder: outline(AppColors.danger, 1.6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: BorderSide(color: fieldBorder),
          foregroundColor: dark ? AppColors.darkAccent : AppColors.primaryDark,
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: dark ? AppColors.darkAccent : AppColors.primary,
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: dark ? AppColors.darkAccent : AppColors.primary,
        foregroundColor: dark ? const Color(0xFF06281C) : Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: dark ? const Color(0xFF1B3A2C) : AppColors.soft,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        iconTheme: WidgetStateProperty.resolveWith((s) {
          final on = s.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: on ? (dark ? AppColors.darkAccent : AppColors.primaryDark) : AppColors.muted,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((s) {
          final on = s.contains(WidgetState.selected);
          return text.labelSmall?.copyWith(
            fontWeight: on ? FontWeight.w700 : FontWeight.w500,
            color: on ? (dark ? AppColors.darkAccent : AppColors.primaryDark) : AppColors.muted,
          );
        }),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide(color: border),
        labelStyle: text.labelMedium,
        selectedColor: dark ? const Color(0xFF1B3A2C) : AppColors.soft,
      ),
      dividerTheme: DividerThemeData(color: border, space: 1, thickness: 1),
      listTileTheme: const ListTileThemeData(iconColor: AppColors.muted),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? (dark ? const Color(0xFF06281C) : Colors.white) : null),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? scheme.primary : null),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          side: BorderSide(color: fieldBorder),
          selectedBackgroundColor: dark ? const Color(0xFF1B3A2C) : AppColors.soft,
          selectedForegroundColor: dark ? AppColors.darkAccent : AppColors.primaryDark,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}
