import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  Locale? _locale;

  /// Retorna el Locale explícito del usuario o null para usar automáticamente el idioma del dispositivo
  Locale? get locale => _locale;

  LocaleProvider() {
    _loadSavedLocale();
  }

  Future<void> _loadSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final langCode = prefs.getString('language_code');
    if (langCode != null && langCode.isNotEmpty) {
      _locale = Locale(langCode);
      notifyListeners();
    }
  }

  /// Establece el idioma. Si se pasa null, se restaura la detección automática del sistema
  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove('language_code');
    } else {
      await prefs.setString('language_code', locale.languageCode);
    }
    notifyListeners();
  }
}
