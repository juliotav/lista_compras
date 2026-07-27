import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  Locale? _locale;

  /// Retorna el Locale explícito seleccionado manualmente por el usuario (o null si usa el predeterminado del sistema)
  Locale? get locale => _locale;

  /// Retorna el Locale efectivo: si el usuario no ha forzado un idioma, detecta automáticamente el idioma del dispositivo
  Locale get effectiveLocale {
    if (_locale != null) return _locale!;
    final deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;
    if (deviceLocale.languageCode.toLowerCase() == 'en') {
      return const Locale('en');
    }
    return const Locale('es');
  }

  LocaleProvider() {
    _loadSavedLocale();
  }

  Future<void> _loadSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final langCode = prefs.getString('language_code');
    if (langCode != null && langCode.isNotEmpty) {
      if (langCode == 'system') {
        _locale = null;
      } else {
        _locale = Locale(langCode);
      }
      notifyListeners();
    }
  }

  /// Establece el idioma. Si se pasa null o 'system', restaura la detección automática según el idioma del dispositivo
  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.setString('language_code', 'system');
    } else {
      await prefs.setString('language_code', locale.languageCode);
    }
    notifyListeners();
  }
}
