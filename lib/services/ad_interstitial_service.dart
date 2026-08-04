import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../config/admob_config.dart';

/// Servicio singleton para la gestión no invasiva de Anuncios Intersticiales (Interstitial Ads)
class AdInterstitialService {
  static InterstitialAd? _interstitialAd;
  static bool _isLoading = false;
  static int _clickCounter = 0;
  static DateTime? _lastShownTimestamp;

  /// Frecuencia: Muestra el anuncio 1 de cada 2 entradas (configurable)
  static const int _frequencyEveryNClicks = 2;

  /// Cooldown: Mínimo 2 minutos de diferencia entre un anuncio y otro
  static const Duration _cooldownDuration = Duration(minutes: 2);

  /// Precarga un Anuncio Intersticial en segundo plano
  static void preloadAd() {
    if (kIsWeb || _isLoading || _interstitialAd != null) return;

    final adUnitId = AdMobConfig.interstitialAdUnitId;
    if (adUnitId.isEmpty) return;

    _isLoading = true;
    debugPrint('[ADMOB LOG] Precargando anuncio intersticial en segundo plano...');

    InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('[ADMOB LOG] Anuncio intersticial precargado con éxito.');
          _interstitialAd = ad;
          _isLoading = false;
        },
        onAdFailedToLoad: (error) {
          debugPrint('[ADMOB LOG] Error al precargar anuncio intersticial: $error');
          _interstitialAd = null;
          _isLoading = false;
        },
      ),
    );
  }

  /// Muestra el anuncio intersticial si cumple con las reglas no invasivas de frecuencia y tiempo,
  /// e inmediatamente después ejecuta la navegación [onNavigate].
  static void showAdIfAllowedThenNavigate({
    required BuildContext context,
    required VoidCallback onNavigate,
  }) {
    _clickCounter++;
    final now = DateTime.now();

    final isFrequencyMet = (_clickCounter % _frequencyEveryNClicks == 0);
    final isCooldownMet = _lastShownTimestamp == null ||
        now.difference(_lastShownTimestamp!) >= _cooldownDuration;

    final canShowAd = isFrequencyMet && isCooldownMet && _interstitialAd != null;

    debugPrint(
      '[ADMOB LOG] Clic #$_clickCounter para pantalla de familias. '
      'Frecuencia: $isFrequencyMet, Cooldown: $isCooldownMet, Ad Listo: ${_interstitialAd != null} => ¿Mostrar?: $canShowAd',
    );

    if (canShowAd) {
      _lastShownTimestamp = now;

      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          debugPrint('[ADMOB LOG] Anuncio intersticial cerrado por el usuario.');
          ad.dispose();
          _interstitialAd = null;
          preloadAd(); // Precargar el siguiente de fondo
          onNavigate();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          debugPrint('[ADMOB LOG] Falló al mostrar anuncio intersticial: $error');
          ad.dispose();
          _interstitialAd = null;
          preloadAd();
          onNavigate();
        },
      );

      _interstitialAd!.show();
    } else {
      // Si no cumple el contador/cooldown o no cargó, navega de forma instantánea sin interrumpir
      onNavigate();
      if (_interstitialAd == null && !_isLoading) {
        preloadAd();
      }
    }
  }
}
