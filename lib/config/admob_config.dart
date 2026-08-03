import 'dart:io';
import 'package:flutter/foundation.dart';

class AdMobConfig {
  /// Entorno de ejecución: 'dev', 'qa', 'pr'
  static const String environment = String.fromEnvironment(
    'ENV',
    defaultValue: 'dev',
  );

  /// Banner Test Unit IDs oficiales de Google AdMob
  static const String _testBannerIdAndroid =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _testBannerIdIOS =
      'ca-app-pub-3940256099942544/2934735716';

  /// Banner Unit IDs de producción pasados vía --dart-define o .env
  static const String _prodBannerIdAndroid = String.fromEnvironment(
    'ADMOB_BANNER_ID_ANDROID_PR',
  );
  static const String _prodBannerIdIOS = String.fromEnvironment(
    'ADMOB_BANNER_ID_IOS_PR',
  );

  /// Retorna true si estamos en entorno de producción
  static bool get isProduction => environment.trim().toLowerCase() == 'pr';

  /// Retorna el Ad Unit ID correspondiente según el entorno (dev/qa/pr) y la plataforma
  static String get bannerAdUnitId {
    if (kIsWeb) {
      return ''; // AdMob nativo no soporta Flutter Web directamente
    }

    if (isProduction) {
      if (Platform.isAndroid) {
        if (_prodBannerIdAndroid.isNotEmpty) {
          return _prodBannerIdAndroid;
        }
        debugPrint(
          '[ADMOB] AVISO: ENV=pr pero ADMOB_BANNER_ID_ANDROID_PR no está configurado. Usando Test ID.',
        );
        return _testBannerIdAndroid;
      } else if (Platform.isIOS) {
        if (_prodBannerIdIOS.isNotEmpty) {
          return _prodBannerIdIOS;
        }
        return _testBannerIdIOS;
      }
    }

    // Para entornos 'dev' y 'qa'
    if (Platform.isAndroid) {
      return _testBannerIdAndroid;
    } else if (Platform.isIOS) {
      return _testBannerIdIOS;
    }

    return '';
  }
}
