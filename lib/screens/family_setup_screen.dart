import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/database_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class FamilySetupScreen extends StatefulWidget {
  const FamilySetupScreen({super.key});

  @override
  State<FamilySetupScreen> createState() => _FamilySetupScreenState();
}

class _FamilySetupScreenState extends State<FamilySetupScreen> {

  void _showCreateFamilyDialog() {
    final l10n = AppLocalizations.of(context)!;
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(l10n.createFamilyTitle),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: l10n.familyNameLabel,
                      hintText: l10n.familyNameHint,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? l10n.familyNameLabel : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: descController,
                    decoration: InputDecoration(
                      labelText: l10n.familyDescLabel,
                      hintText: l10n.familyDescHint,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.btnCancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final db = dialogContext.read<DatabaseService>();
                  final navigator = Navigator.of(context);
                  final dialogNav = Navigator.of(dialogContext);

                  await db.createFamily(
                    nameController.text.trim(),
                    descController.text.trim().isEmpty ? null : descController.text.trim(),
                  );
                  
                  dialogNav.pop();
                  navigator.pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                    (route) => false,
                  );
                }
              },
              child: Text(l10n.btnSaveFamily),
            ),
          ],
        );
      },
    );
  }

  void _showJoinFamilyDialog() {
    final l10n = AppLocalizations.of(context)!;
    final codeController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(l10n.btnJoinFamily),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: l10n.familyCodeLabel,
                    hintText: l10n.familyCodeHint,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? l10n.familyCodeLabel : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.btnCancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final db = dialogContext.read<DatabaseService>();
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);
                  final dialogNav = Navigator.of(dialogContext);

                  final success = await db.joinFamily(codeController.text.trim());
                  if (success) {
                    dialogNav.pop();
                    navigator.pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                      (route) => false,
                    );
                  } else {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(l10n.invalidFamilyCode),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: Text(l10n.btnJoin),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final db = context.watch<DatabaseService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.familySetupTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: l10n.menuLogout,
            onPressed: () {
              db.logout();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.familySetupSubtitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.grey[700],
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              // Botón 1: Crear Familia
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                ),
                child: InkWell(
                  onTap: _showCreateFamilyDialog,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        Icon(
                          Icons.group_add_rounded,
                          size: 56,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.btnCreateFamily,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.btnCreateFamilyDesc,
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Botón 2: Unirse a Familia
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: Colors.teal.withValues(alpha: 0.3)),
                ),
                child: InkWell(
                  onTap: _showJoinFamilyDialog,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.vpn_key_rounded,
                          size: 56,
                          color: Colors.teal,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.btnJoinFamily,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.btnJoinFamilyDesc,
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
