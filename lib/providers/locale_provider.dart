import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class LocaleProvider extends ChangeNotifier {
  Locale? _locale; // null = system default

  LocaleProvider() {
    _loadLocale();
  }

  Locale? get locale => _locale;

  Future<void> _loadLocale() async {
    final savedLocale = await SettingsService.getLocale();
    if (savedLocale != null) {
      _locale = Locale(savedLocale);
    }
    notifyListeners();
  }

  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    await SettingsService.saveLocale(locale?.languageCode);
    notifyListeners();
  }

  /// Returns the display name for a locale
  static String getDisplayName(String? languageCode, BuildContext context) {
    switch (languageCode) {
      case 'en':
        return 'English';
      case 'de':
        return 'Deutsch';
      case null:
        return 'System';
      default:
        return languageCode;
    }
  }
}
