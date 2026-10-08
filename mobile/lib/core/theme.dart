import 'package:flutter/material.dart';

/// MK Market design tokens. One place for colours, radii and component styles so the three
/// role modules look like one app (A13).
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.canvas,
  });

  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color info;
  final Color infoContainer;
  final Color onInfoContainer;

  /// Page background behind cards.
  final Color canvas;

  static const light = AppColors(
    success: Color(0xFF14803C),
    successContainer: Color(0xFFDDF5E5),
    onSuccessContainer: Color(0xFF0B4F25),
    warning: Color(0xFFB45309),
    warningContainer: Color(0xFFFEF0D7),
    onWarningContainer: Color(0xFF7A3A06),
    info: Color(0xFF1D5FD1),
    infoContainer: Color(0xFFE2ECFD),
    onInfoContainer: Color(0xFF123F8C),
    canvas: Color(0xFFF4F6F5),
  );

  static const dark = AppColors(
    success: Color(0xFF5CD68A),
    successContainer: Color(0xFF103A22),
    onSuccessContainer: Color(0xFFBDF2CF),
    warning: Color(0xFFF5B25C),
    warningContainer: Color(0xFF45290A),
    onWarningContainer: Color(0xFFFFDDB0),
    info: Color(0xFF8AB4FF),
    infoContainer: Color(0xFF15305E),
    onInfoContainer: Color(0xFFD6E3FF),
    canvas: Color(0xFF0F1412),
  );

  static AppColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppColors>() ?? (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) => t < 0.5 || other == null ? this : other;
}

class AppTheme {
  static const brand = Color(0xFF0E8A4A);
  static const radius = 16.0;

  static ThemeData light() => _build(Brightness.light, AppColors.light);
  static ThemeData dark() => _build(Brightness.dark, AppColors.dark);

  static ThemeData _build(Brightness brightness, AppColors colors) {
    final isLight = brightness == Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: brightness,
      primary: isLight ? brand : const Color(0xFF6DDC9C),
      surface: isLight ? Colors.white : const Color(0xFF171D1A),
    );
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
    final text = base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.2),
    );
    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    const buttonSize = Size(64, 52);

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: colors.canvas,
      extensions: [colors],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.canvas,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: rounded.copyWith(side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: buttonSize, shape: buttonShape, textStyle: text.labelLarge),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: text.labelLarge,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(textStyle: text.labelLarge)),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      tabBarTheme: TabBarThemeData(
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w500),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: scheme.outlineVariant.withValues(alpha: 0.5),
        tabAlignment: TabAlignment.start,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      dialogTheme: DialogThemeData(
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.6), space: 1),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
    );
  }
}
