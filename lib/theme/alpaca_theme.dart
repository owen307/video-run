import 'package:flutter/material.dart';

class AlpacaColors {
  const AlpacaColors._();

  static const ink = Color(0xFF10120E);
  static const panel = Color(0xFF1A1E16);
  static const panelRaised = Color(0xFF252A1E);
  static const line = Color(0xFF3A4030);
  static const text = Color(0xFFF3F0E6);
  static const muted = Color(0xFFA39E8C);
  static const program = Color(0xFFFF4B3E);
  static const programDeep = Color(0xFF3A1814);
  static const preview = Color(0xFFD6F25C);
  static const previewDeep = Color(0xFF232C12);
  static const brass = Color(0xFFE2B15A);
  static const mock = Color(0xFFFFB020);
  static const live = Color(0xFF8EE0AE);
  static const down = Color(0xFFFF7A6E);
}

class AlpacaText {
  const AlpacaText._();

  static const tally = TextStyle(
    fontFamily: 'BarlowCondensed',
    fontWeight: FontWeight.w700,
    fontSize: 48,
    height: 0.9,
    letterSpacing: 0.4,
    color: AlpacaColors.text,
  );

  static const bus = TextStyle(
    fontFamily: 'BarlowCondensed',
    fontWeight: FontWeight.w600,
    fontSize: 14,
    letterSpacing: 1.8,
    color: AlpacaColors.muted,
  );

  static const action = TextStyle(
    fontFamily: 'BarlowCondensed',
    fontWeight: FontWeight.w700,
    fontSize: 32,
    letterSpacing: 1.4,
    height: 1,
  );

  static const mono = TextStyle(
    fontFamily: 'IBMPlexMono',
    fontSize: 12.5,
    height: 1.35,
    color: AlpacaColors.muted,
  );
}

class AlpacaTheme {
  const AlpacaTheme._();

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Barlow',
      scaffoldBackgroundColor: AlpacaColors.ink,
      splashFactory: InkRipple.splashFactory,
    );
    return base.copyWith(
      colorScheme: const ColorScheme.dark(
        surface: AlpacaColors.panel,
        primary: AlpacaColors.brass,
        onPrimary: Color(0xFF1A1408),
        secondary: AlpacaColors.preview,
        onSecondary: Color(0xFF172000),
        error: AlpacaColors.program,
        onSurface: AlpacaColors.text,
      ),
      textTheme: base.textTheme.apply(
        fontFamily: 'Barlow',
        bodyColor: AlpacaColors.text,
        displayColor: AlpacaColors.text,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AlpacaColors.panelRaised,
        labelStyle: const TextStyle(color: AlpacaColors.muted),
        hintStyle: const TextStyle(color: AlpacaColors.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AlpacaColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AlpacaColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AlpacaColors.brass, width: 1.4),
        ),
      ),
      dividerColor: AlpacaColors.line,
    );
  }
}
