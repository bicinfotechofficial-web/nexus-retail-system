import 'package:flutter/material.dart';

/// Caramel Cottage colours: warm caramel on cream, with large tap targets
/// for one-handed use at the counter.
abstract final class PosTheme {
  static const Color caramel = Color(0xFFB0662A);
  static const Color cream = Color(0xFFFFF8EC);
  static const Color cocoa = Color(0xFF4A2C1A);

  /// Minimum height of buttons and list rows.
  static const double tapTarget = 56;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: caramel,
      primary: caramel,
      surface: cream,
    );
    const buttonSize = Size(64, tapTarget);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: cream,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarTheme(
        backgroundColor: caramel,
        foregroundColor: Colors.white,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: buttonSize),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      listTileTheme: const ListTileThemeData(minTileHeight: tapTarget),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: false,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
