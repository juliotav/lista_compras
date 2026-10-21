import 'dart:async';
import 'package:flutter/material.dart';

/// Utilidad genérica para mostrar notificaciones flotantes con opción de "Deshacer" (Undo).
/// Permite revertir cualquier acción de usuario en cualquier pantalla de forma consistente y desacoplada.
class UndoHelper {
  static Timer? _activeTimer;
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _activeController;

  /// Muestra un SnackBar flotante con una acción de deshacer que ejecuta [onUndo] al presionarlo.
  /// Desaparece automáticamente a los [duration] (5 segundos por defecto), incluso si el SO tiene
  /// configuraciones de accesibilidad activas que impidan el auto-dismiss nativo de Flutter.
  ///
  /// Acepta un [messenger] opcional para cuando el widget que disparó la acción se desmonte
  /// (por ejemplo, el último elemento de una lista que pasa a estar vacía).
  static void show({
    BuildContext? context,
    ScaffoldMessengerState? messenger,
    required String message,
    required Future<void> Function() onUndo,
    String actionLabel = 'Deshacer',
    Duration duration = const Duration(seconds: 5),
  }) {
    assert(context != null || messenger != null, 'Debe proporcionarse context o messenger');
    final effectiveMessenger = messenger ?? (context != null && context.mounted ? ScaffoldMessenger.maybeOf(context) : null);
    if (effectiveMessenger == null || !effectiveMessenger.mounted) return;

    final themeContext = (context != null && context.mounted) ? context : effectiveMessenger.context;
    final theme = Theme.of(themeContext);

    // Cancelar cualquier timer previo y limpiar inmediatamente cualquier SnackBar anterior
    _activeTimer?.cancel();
    _activeTimer = null;
    effectiveMessenger.clearSnackBars();

    final controller = effectiveMessenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
        duration: duration,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        elevation: 6,
        action: SnackBarAction(
          label: actionLabel,
          textColor: theme.brightness == Brightness.dark
              ? Colors.amberAccent
              : const Color(0xFFFFD54F),
          onPressed: () async {
            _activeTimer?.cancel();
            _activeTimer = null;
            if (effectiveMessenger.mounted) {
              effectiveMessenger.hideCurrentSnackBar();
            }
            await onUndo();
          },
        ),
      ),
    );

    _activeController = controller;

    // Forzar cierre tras cumplirse la duración requerida (5 segundos)
    _activeTimer = Timer(duration, () {
      if (_activeController == controller) {
        try {
          controller.close();
        } catch (_) {}
        _activeTimer = null;
        _activeController = null;
      }
    });

    controller.closed.then((_) {
      if (_activeController == controller) {
        _activeTimer?.cancel();
        _activeTimer = null;
        _activeController = null;
      }
    });
  }

  /// Permite cerrar manualmente el SnackBar activo y cancelar su temporizador si fuera necesario.
  static void dismiss({BuildContext? context, ScaffoldMessengerState? messenger}) {
    _activeTimer?.cancel();
    _activeTimer = null;
    _activeController = null;
    if (messenger != null && messenger.mounted) {
      messenger.clearSnackBars();
    } else if (context != null && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    }
  }
}
