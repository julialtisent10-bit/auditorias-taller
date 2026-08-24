import 'package:flutter/material.dart';

class AppTheme {
  static const semilla = Color(0xFF0E4F8B);

  static ThemeData claro() => _construir(Brightness.light);
  static ThemeData oscuro() => _construir(Brightness.dark);

  static ThemeData _construir(Brightness brillo) {
    final esquema = ColorScheme.fromSeed(seedColor: semilla, brightness: brillo);

    return ThemeData(
      useMaterial3: true,
      // Redundante con el esquema, pero explícito: deja claro de qué modo es
      // este tema sin tener que ir a mirar de dónde sale `esquema`.
      brightness: brillo,
      colorScheme: esquema,
      // Densidad estándar a propósito: la app se usa de pie, con guantes y
      // con el móvil a un palmo. Reducir la densidad haría los objetivos
      // táctiles demasiado pequeños.
      visualDensity: VisualDensity.standard,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: esquema.outlineVariant),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      chipTheme: const ChipThemeData(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
    );
  }
}
