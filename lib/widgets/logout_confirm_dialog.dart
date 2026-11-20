import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// Muestra un diálogo de confirmación antes de cerrar sesión.
/// Retorna `true` si el usuario confirma, `false` en caso contrario.
Future<bool> showLogoutConfirmDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              Icons.logout_rounded,
              color: Colors.red[700],
              size: 26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.confirmLogoutTitle,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(l10n.confirmLogoutMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.btnCancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              l10n.menuLogout,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}
