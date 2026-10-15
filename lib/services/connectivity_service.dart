import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Servicio singleton que monitorea el estado de conectividad a internet en tiempo real.
/// Notifica a la aplicación cuando se pierde la conexión o cuando se restablece.
class ConnectivityService extends ChangeNotifier {
  static ConnectivityService? _instance;
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _isOnline = true;
  bool get isOnline => _isOnline;
  bool get isOffline => !_isOnline;

  bool _isChecking = false;
  Timer? _debounceTimer;

  ConnectivityService._internal() {
    _init();
  }

  factory ConnectivityService() {
    _instance ??= ConnectivityService._internal();
    return _instance!;
  }

  void _init() {
    // Escucha eventos del sistema operativo (WiFi apagado, Modo Avión, datos móviles desconectados, etc.)
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _onConnectivityResultsChanged(results);
    });

    // Verificación inicial inmediata
    unawaited(checkConnectivity());
  }

  void _onConnectivityResultsChanged(List<ConnectivityResult> results) {
    final hasInterface = results.any((r) => r != ConnectivityResult.none);
    if (!hasInterface) {
      _updateStatus(false);
      return;
    }

    // Si el dispositivo informa tener WiFi o Datos, aplicamos un pequeño debounce y comprobamos acceso real a internet
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      checkConnectivity();
    });
  }

  /// Verifica de forma activa y rápida si hay acceso real a internet
  Future<bool> checkConnectivity() async {
    if (_isChecking) return _isOnline;
    _isChecking = true;

    try {
      final results = await _connectivity.checkConnectivity();
      final hasInterface = results.any((r) => r != ConnectivityResult.none);

      if (!hasInterface) {
        _updateStatus(false);
        return false;
      }

      final hasInternet = await _checkReachability();
      _updateStatus(hasInternet);
      return hasInternet;
    } catch (e) {
      debugPrint("[CONNECTIVITY] Error comprobando conectividad: $e");
      return _isOnline;
    } finally {
      _isChecking = false;
    }
  }

  /// Prueba la resolución DNS y alcance de internet con tiempo de espera corto
  Future<bool> _checkReachability() async {
    if (kIsWeb) {
      return true;
    }

    try {
      final result = await InternetAddress.lookup('dns.google')
          .timeout(const Duration(milliseconds: 2500));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      try {
        final fallback = await InternetAddress.lookup('google.com')
            .timeout(const Duration(milliseconds: 2500));
        return fallback.isNotEmpty && fallback[0].rawAddress.isNotEmpty;
      } catch (_) {
        return false;
      }
    }
  }

  /// Permite a servicios de red (ej. MongoService) reportar una desconexión o fallo de socket
  void reportNetworkFailure() {
    unawaited(checkConnectivity());
  }

  void _updateStatus(bool online) {
    if (_isOnline != online) {
      _isOnline = online;
      debugPrint("[CONNECTIVITY] Estado de conexión cambiado: ${_isOnline ? 'ONLINE (Conectado)' : 'OFFLINE (Sin internet)'}");
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }
}
