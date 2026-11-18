import 'package:flutter/material.dart';

/// Travel Map design system V1 -- "Premium Forest".
///
/// Every colour, radius and spacing used by shared components comes from this
/// file. A future theme (V2: other palettes, account/device preference) only
/// needs another [AppPalette]; widgets read [AppColors] / the [ThemeData]
/// built from it and never hard-code a colour.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class AppRadii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 18;
  static const double sheet = 20;
  static const double pill = 999;
}

abstract final class AppSizes {
  static const double icon = 24;
  static const double buttonHeight = 48;
  static const double touchTarget = 48;
  static const double contentMaxWidth = 720;
}

/// One complete colour palette. [AppPalette.premiumForest] is the only theme
/// in V1.
@immutable
class AppPalette {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.elevated,
    required this.accent,
    required this.onAccent,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
  });

  /// Screen background, navigation and app bars.
  final Color background;

  /// Cards and list tiles (one step above the background).
  final Color surface;

  /// Bottom sheets, dialogs, menus (the highest surface).
  final Color elevated;

  /// The single restrained accent (primary actions, selected state).
  final Color accent;
  final Color onAccent;
  final Color textPrimary;
  final Color textSecondary;

  /// Hairline borders and dividers.
  final Color border;

  static const premiumForest = AppPalette(
    background: Color(0xFF0B1F1B),
    surface: Color(0xFF12302A),
    elevated: Color(0xFF17372F),
    accent: Color(0xFFC6A66A),
    onAccent: Color(0xFF1A1407),
    textPrimary: Color(0xFFF4F0E7),
    textSecondary: Color(0xFF8B9B94),
    border: Color(0xFF28463E),
  );
}

/// The active palette as constants, for widgets that need a colour outside
/// the [ThemeData] (map overlays, painted artwork). V1: one fixed palette.
abstract final class AppColors {
  static const _p = AppPalette.premiumForest;

  static const background = Color(0xFF0B1F1B);
  static const surface = Color(0xFF12302A);
  static const elevated = Color(0xFF17372F);
  static const accent = Color(0xFFC6A66A);
  static const onAccent = Color(0xFF1A1407);
  static const textPrimary = Color(0xFFF4F0E7);
  static const textSecondary = Color(0xFF8B9B94);
  static const border = Color(0xFF28463E);

  /// A dimmed accent for subtle tints (selected backgrounds, indicators).
  static Color accentTint([double alpha = 0.16]) =>
      _p.accent.withValues(alpha: alpha);
}

/// Which Google Maps style a map uses. Independent of [AppPalette]: the UI
/// theme and the map's colours are configured separately.
enum AppMapStyleKind {
  dark('assets/map_styles/travel_dark_map.json'),
  light('assets/map_styles/travel_light_map.json');

  const AppMapStyleKind(this.asset);
  final String asset;
}

/// The map style in use. V1 ships one fixed choice (no picker); changing
/// [kind] (later: from a preference) restyles every map without touching
/// any widget or the UI theme.
abstract final class AppMapStyle {
  static const kind = AppMapStyleKind.dark;
  static const darkAsset = 'assets/map_styles/travel_dark_map.json';

  /// The asset every map loads.
  static String get assetPath => kind.asset;
}

ThemeData buildAppTheme([AppPalette palette = AppPalette.premiumForest]) {
  final colors = ColorScheme.fromSeed(
    seedColor: palette.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: palette.accent,
    onPrimary: palette.onAccent,
    secondary: palette.accent,
    onSecondary: palette.onAccent,
    surface: palette.background,
    onSurface: palette.textPrimary,
    onSurfaceVariant: palette.textSecondary,
    surfaceContainerLowest: palette.background,
    surfaceContainerLow: palette.surface,
    surfaceContainer: palette.surface,
    surfaceContainerHigh: palette.elevated,
    surfaceContainerHighest: palette.elevated,
    outline: palette.textSecondary,
    outlineVariant: palette.border,
  );
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadii.md),
    borderSide: BorderSide(color: palette.border),
  );
  final shape12 = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadii.md),
  );
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: palette.background,
    colorScheme: colors,
    canvasColor: palette.background,
    fontFamily: 'Roboto',
    textTheme: TextTheme(
      headlineMedium: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary),
      headlineSmall: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary),
      titleLarge: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary),
      titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary),
      titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary),
      bodyLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: palette.textPrimary),
      bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: palette.textPrimary),
      bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: palette.textSecondary),
      labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary),
      labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: palette.textSecondary),
      labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          color: palette.textSecondary),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: palette.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
      ),
    ),
    iconTheme: IconThemeData(color: palette.textPrimary),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size.square(40),
        maximumSize: const Size.square(40),
        iconSize: 21,
        padding: const EdgeInsets.all(8),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: BorderSide(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: palette.textSecondary,
      textColor: palette.textPrimary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surface,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: palette.accent, width: 1.5),
      ),
      hintStyle: TextStyle(color: palette.textSecondary),
      labelStyle: TextStyle(color: palette.textSecondary),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, AppSizes.buttonHeight),
        backgroundColor: palette.accent,
        foregroundColor: palette.onAccent,
        disabledBackgroundColor: palette.textSecondary.withValues(alpha: 0.18),
        disabledForegroundColor: palette.textSecondary,
        shape: shape12,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, AppSizes.buttonHeight),
        foregroundColor: palette.textPrimary,
        side: BorderSide(color: palette.border),
        shape: shape12,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: palette.accent),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: palette.accent,
      foregroundColor: palette.onAccent,
      elevation: 2,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: palette.surface,
      selectedColor: palette.accent.withValues(alpha: 0.22),
      side: BorderSide(color: palette.border),
      shape: shape12,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: palette.textPrimary),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        foregroundColor: palette.textPrimary,
        selectedForegroundColor: palette.onAccent,
        selectedBackgroundColor: palette.accent,
        side: BorderSide(color: palette.border),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: palette.accent,
      inactiveTrackColor: palette.border,
      thumbColor: palette.accent,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: palette.accent,
      linearTrackColor: palette.border,
    ),
    dividerTheme: DividerThemeData(
      color: palette.border,
      thickness: 1,
      space: 1,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.elevated,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: palette.elevated,
      showDragHandle: false,
      dragHandleColor: palette.textSecondary.withValues(alpha: 0.5),
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.elevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: palette.elevated,
      surfaceTintColor: Colors.transparent,
      shape: shape12,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.elevated,
      contentTextStyle: TextStyle(color: palette.textPrimary),
      actionTextColor: palette.accent,
      behavior: SnackBarBehavior.floating,
      shape: shape12,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.background,
      surfaceTintColor: Colors.transparent,
      indicatorColor: palette.accent.withValues(alpha: 0.14),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 10,
            height: 1,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? palette.accent
                : palette.textSecondary,
          )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            size: 20,
            color: states.contains(WidgetState.selected)
                ? palette.accent
                : palette.textSecondary,
          )),
      height: 64,
    ),
  );
}

class AppContent extends StatelessWidget {
  const AppContent({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
          child: child,
        ),
      );
}
