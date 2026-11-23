import 'package:flutter/material.dart';

import '../core/protocol.dart';

/// Design tokens: one seed colour, an 8-pt spacing scale and fixed radii,
/// so every screen lines up.
class Tokens {
  Tokens._();

  static const Color seed = Color(0xFF00A86B); // electric green
  static const double s1 = 4, s2 = 8, s3 = 12, s4 = 16, s5 = 24, s6 = 32;
  static const double radius = 20;
  static const double minTouch = 48; // Material minimum tap target
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: Tokens.seed, brightness: brightness);
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
  return base.copyWith(
    visualDensity: VisualDensity.standard,
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Colour for each severity, readable in light and dark themes.
Color severityColor(ColorScheme scheme, Severity s) {
  switch (s) {
    case Severity.good:
      return scheme.primary;
    case Severity.info:
      return scheme.tertiary;
    case Severity.warning:
      return scheme.brightness == Brightness.dark
          ? const Color(0xFFFFC857)
          : const Color(0xFFB26A00);
    case Severity.danger:
      return scheme.error;
  }
}

IconData severityIcon(Severity s) {
  switch (s) {
    case Severity.good:
      return Icons.check_circle_rounded;
    case Severity.info:
      return Icons.info_rounded;
    case Severity.warning:
      return Icons.warning_amber_rounded;
    case Severity.danger:
      return Icons.error_rounded;
  }
}

/// Battery colour from percent.
Color batteryColor(ColorScheme scheme, int percent) {
  if (percent <= 15) return severityColor(scheme, Severity.danger);
  if (percent <= 35) return severityColor(scheme, Severity.warning);
  return scheme.primary;
}
