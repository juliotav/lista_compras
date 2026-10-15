import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/database_service.dart';

/// Widget reutilizable que muestra un micro-chip en la parte superior (AppBar):
/// - Etiqueta "(Offline)" fija y continua mientras el usuario no tenga conexión a internet.
/// - Etiqueta "Sincronizando..." con rotación suave mientras se sincronizan los datos con la nube.
/// - Oculto con animación tenue cuando está conectado y al día.
class SyncIndicatorWidget extends StatefulWidget {
  const SyncIndicatorWidget({super.key});

  @override
  State<SyncIndicatorWidget> createState() => _SyncIndicatorWidgetState();
}

class _SyncIndicatorWidgetState extends State<SyncIndicatorWidget> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DatabaseService>();
    final isOffline = db.isOffline;
    final isSyncing = db.isBackgroundSyncing && !isOffline;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (isSyncing) {
      if (!_animationController.isAnimating) {
        _animationController.repeat();
      }
    } else {
      if (_animationController.isAnimating) {
        _animationController.stop();
      }
    }

    final syncingText = l10n?.syncingStatus ?? 'Sincronizando...';
    final offlineText = l10n?.offlineStatus ?? '(Offline)';
    final offlineTooltip = l10n?.offlineTooltip ??
        'Modo sin conexión. Tus cambios se guardan localmente y se sincronizarán al reconectarte.';

    Widget currentBadge;

    if (isOffline) {
      // 1. Estado OFFLINE: Se muestra SIEMPRE mientras el usuario no tenga internet
      currentBadge = Tooltip(
        key: const ValueKey('badge_offline'),
        message: offlineTooltip,
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.amber.shade900.withValues(alpha: 0.28)
                : const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.amber.shade700.withValues(alpha: 0.55)
                  : Colors.amber.shade700.withValues(alpha: 0.45),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 13,
                color: isDark ? Colors.amber.shade300 : Colors.amber.shade900,
              ),
              const SizedBox(width: 5),
              Text(
                offlineText,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      );
    } else if (isSyncing) {
      // 2. Estado SINCRONIZANDO: Micro-chip con ícono giratorio
      currentBadge = Container(
        key: const ValueKey('badge_syncing'),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotationTransition(
              turns: _animationController,
              child: Icon(
                Icons.sync_rounded,
                size: 14,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              syncingText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      );
    } else {
      // 3. Estado CONECTADO Y AL DÍA: Oculto
      currentBadge = const SizedBox.shrink(key: ValueKey('badge_empty'));
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: currentBadge,
    );
  }
}
