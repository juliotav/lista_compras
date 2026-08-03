import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/family_model.dart';
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
    final db = context.read<DatabaseService>();
    final userId = db.currentUser?.idUsuario;

    final createdCount = db.userFamilies.where((f) => f.idCreador == userId).length;
    if (createdCount >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.maxFamiliesReachedErr),
          backgroundColor: Colors.orange[800],
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

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
                  final navigator = Navigator.of(context);
                  final dialogNav = Navigator.of(dialogContext);

                  try {
                    await db.createFamily(
                      nameController.text.trim(),
                      descController.text.trim().isEmpty ? null : descController.text.trim(),
                    );
                    dialogNav.pop();
                    navigator.pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                      (route) => false,
                    );
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l10n.maxFamiliesReachedErr),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
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

  void _confirmDeleteFamily(BuildContext context, FamilyModel family) {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<DatabaseService>();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.deleteFamilyConfirmTitle(family.nbFamilia),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              l10n.deleteFamilyWarning,
              style: const TextStyle(fontSize: 13, height: 1.4, color: Colors.black87),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.btnCancel),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.delete_forever_rounded, size: 18),
              label: Text(l10n.btnDelete),
              onPressed: () async {
                final nav = Navigator.of(dialogContext);
                final messenger = ScaffoldMessenger.of(context);
                nav.pop();

                final success = await db.deleteFamily(family.idFamilia);
                if (success) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text("Familia '${family.nbFamilia}' eliminada permanentemente."),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
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
    final userId = db.currentUser?.idUsuario;

    final userFamilies = db.userFamilies;
    final createdCount = userFamilies.where((f) => f.idCreador == userId).length;
    final remainingCount = max(0, 5 - createdCount);

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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
          child: Column(
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
              const SizedBox(height: 20),

              // Banner con contador de limite de creación (Máximo 5 familias)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: remainingCount > 0 ? Colors.purple.withValues(alpha: 0.08) : Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: remainingCount > 0 ? Colors.deepPurple.withValues(alpha: 0.3) : Colors.orange,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          remainingCount > 0 ? Icons.info_outline_rounded : Icons.warning_amber_rounded,
                          color: remainingCount > 0 ? Colors.deepPurple : Colors.orange[900],
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.createdFamiliesCount(createdCount, 5, remainingCount),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: remainingCount > 0 ? Colors.deepPurple[800] : Colors.orange[900],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.unlimitedJoinInfo,
                      style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Botón 1: Crear Familia
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                ),
                child: InkWell(
                  onTap: _showCreateFamilyDialog,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        Icon(
                          Icons.group_add_rounded,
                          size: 48,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.btnCreateFamily,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
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

              const SizedBox(height: 16),

              // Botón 2: Unirse a Familia
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: Colors.teal.withValues(alpha: 0.3)),
                ),
                child: InkWell(
                  onTap: _showJoinFamilyDialog,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.vpn_key_rounded,
                          size: 48,
                          color: Colors.teal,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.btnJoinFamily,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                        const SizedBox(height: 4),
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

              // Lista simple de mis familias
              if (userFamilies.isNotEmpty) ...[
                const SizedBox(height: 32),
                Text(
                  l10n.myFamiliesHeader,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 12),

                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: userFamilies.length,
                  itemBuilder: (context, index) {
                    final fam = userFamilies[index];
                    final isCreator = fam.idCreador == userId;
                    final isActive = db.currentUser?.idFamilia == fam.idFamilia;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: isActive ? 3 : 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isActive ? Colors.deepPurple : Colors.grey[300]!,
                          width: isActive ? 2 : 1,
                        ),
                      ),
                      child: ListTile(
                        onTap: () async {
                          await db.switchFamily(fam.idFamilia);
                          if (context.mounted) {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (_) => const HomeScreen()),
                              (route) => false,
                            );
                          }
                        },
                        leading: CircleAvatar(
                          backgroundColor: isCreator
                              ? Colors.deepPurple.withValues(alpha: 0.15)
                              : Colors.teal.withValues(alpha: 0.15),
                          child: Icon(
                            isCreator ? Icons.star_rounded : Icons.group_rounded,
                            color: isCreator ? Colors.deepPurple : Colors.teal,
                          ),
                        ),
                        title: Text(
                          fam.nbFamilia,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          "Código: ${fam.clFamilia}",
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isCreator ? Colors.deepPurple.withValues(alpha: 0.1) : Colors.teal.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                isCreator ? l10n.creatorBadge : l10n.memberBadge,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isCreator ? Colors.deepPurple : Colors.teal,
                                ),
                              ),
                            ),

                            if (isCreator) ...[
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                                tooltip: l10n.deleteFamilyTitle,
                                onPressed: () => _confirmDeleteFamily(context, fam),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
