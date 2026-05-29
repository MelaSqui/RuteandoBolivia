import 'package:flutter/material.dart';

class ThemeService extends ValueNotifier<ThemeMode> {
  ThemeService() : super(ThemeMode.system);

  void setThemeMode(ThemeMode mode) {
    value = mode;
  }

  void toggleTheme() {
    if (value == ThemeMode.light) {
      value = ThemeMode.dark;
    } else if (value == ThemeMode.dark) {
      value = ThemeMode.light;
    } else {
      // system -> light
      value = ThemeMode.light;
    }
  }
}

final themeService = ThemeService();
