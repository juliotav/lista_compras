import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pantallas o flujos que cuentan con guía interactiva (Coach Mark).
enum CoachMarkTour {
  familySetup,
  joinFamily,
  home,
  listDetail,
  purchasedItemsActions,
}

/// Servicio encargado de persistir por usuario qué guías interactivas ya fueron vistas.
/// Usa SharedPreferences (separado de SQLite para no perderse al limpiar caché local).
class CoachMarkService {
  static const String _keyPrefix = 'coach_mark_v1_';

  /// Evita que dos recorridos se superpongan simultáneamente.
  static bool _isTourActive = false;

  static bool get isTourActive => _isTourActive;

  static void setTourActive(bool active) {
    _isTourActive = active;
  }

  static String _prefKey(CoachMarkTour tour, String userId) =>
      '$_keyPrefix${tour.name}_$userId';

  /// Retorna `true` si el usuario ya completó u omitió este recorrido.
  static Future<bool> hasSeenTour(CoachMarkTour tour, String? userId) async {
    if (userId == null || userId.isEmpty) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefKey(tour, userId)) ?? false;
    } catch (e) {
      debugPrint('[COACH_MARK LOG] Error leyendo estado de ${tour.name}: $e');
      return true;
    }
  }

  /// Marca el recorrido como visto para el usuario indicado.
  static Future<void> markTourSeen(CoachMarkTour tour, String? userId) async {
    if (userId == null || userId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey(tour, userId), true);
      debugPrint(
        '[COACH_MARK LOG] Recorrido ${tour.name} marcado como visto para $userId.',
      );
    } catch (e) {
      debugPrint('[COACH_MARK LOG] Error guardando estado de ${tour.name}: $e');
    }
  }

  /// Reinicia un recorrido específico para que vuelva a mostrarse automáticamente.
  static Future<void> resetTour(CoachMarkTour tour, String? userId) async {
    if (userId == null || userId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey(tour, userId));
      debugPrint(
        '[COACH_MARK LOG] Recorrido ${tour.name} reiniciado para $userId.',
      );
    } catch (e) {
      debugPrint('[COACH_MARK LOG] Error reiniciando ${tour.name}: $e');
    }
  }

  /// Reinicia todos los recorridos del usuario para que vuelvan a mostrarse automáticamente.
  static Future<void> resetAllTours(String? userId) async {
    if (userId == null || userId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final tour in CoachMarkTour.values) {
        await prefs.remove(_prefKey(tour, userId));
      }
      debugPrint(
        '[COACH_MARK LOG] Todos los recorridos reiniciados para $userId.',
      );
    } catch (e) {
      debugPrint('[COACH_MARK LOG] Error reiniciando recorridos: $e');
    }
  }
}
