import 'package:flutter/material.dart';

import '../platform/gtk_font_service.dart';
import 'busycards_yaru_theme.dart';

ThemeData buildBusyCardsTheme({
  required Brightness brightness,
  required Color accentColor,
  String? gtkFontFamily,
  double? gtkFontSize,
  GtkThemeColors? gtkThemeColors,
  bool highContrast = false,
}) {
  final effectiveAccentColor = highContrast
      ? brightness == Brightness.dark
            ? Colors.white
            : Colors.black
      : accentColor;
  return BusyCardsYaruTheme.build(
    brightness: brightness,
    accentColor: effectiveAccentColor,
    gtkFontFamily: gtkFontFamily,
    gtkFontSize: gtkFontSize,
    gtkThemeColors: gtkThemeColors,
    highContrast: highContrast,
  );
}
