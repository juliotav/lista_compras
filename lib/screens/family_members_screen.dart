import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/database_service.dart';

class FamilyMembersScreen extends StatefulWidget {
  const FamilyMembersScreen({super.key});

  @override
  State<FamilyMembersScreen> createState() => _FamilyMembersScreenState();
}

class _FamilyMembersScreenState extends State<FamilyMembersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DatabaseService>().fetchFamilyData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final db = context.watch<DatabaseService>();
    final family = db.currentFamily;
    final currentUser = db.currentUser;
    final members = db.getFamilyMembers();

    final isCreator = family != null && currentUser != null && family.idCreador == currentUser.idUsuario;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.membersTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: "Sincronizar",
            onPressed: () => db.fetchFamilyData(),
          ),
        ],
      ),
      body: family == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => db.fetchFamilyData(),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                    child: Column(
                      children: [
                        Text(
                          family.nbFamilia,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "${l10n.familyCodeBadge} ${family.clFamilia}",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: members.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: members.length,
                            separatorBuilder: (context, index) => const Divider(),
                            itemBuilder: (context, index) {
                              final member = members[index];
                              final isThisMemberCreator = member.idUsuario == family.idCreador;
                              final isMe = member.idUsuario == currentUser?.idUsuario;

                              return ListTile(
                                leading: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: isThisMemberCreator ? Colors.amber[700] : Colors.deepPurple[400],
                                      child: Text(
                                        member.nbCompleto.isNotEmpty ? member.nbCompleto[0].toUpperCase() : 'U',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                    ),
                                    if (isThisMemberCreator)
                                      Positioned(
                                        right: -2,
                                        bottom: -2,
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            color: Colors.amber[800],
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white, width: 1.5),
                                          ),
                                          child: const Icon(
                                            Icons.star_rounded,
                                            color: Colors.white,
                                            size: 10,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                title: Text(
                                  "${member.nbCompleto}${isMe ? ' (Tú)' : ''}",
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                subtitle: Text(
                                  "${member.nbEmail}${isThisMemberCreator ? ' • ${l10n.creatorTag}' : ''}",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isThisMemberCreator ? Colors.amber[900] : Colors.grey[600],
                                    fontWeight: isThisMemberCreator ? FontWeight.bold : FontWeight.normal,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                trailing: isCreator && !isThisMemberCreator
                                    ? IconButton(
                                        icon: const Icon(Icons.person_remove_rounded, color: Colors.red),
                                        tooltip: l10n.removeMember,
                                        onPressed: () {
                                          showDialog(
                                            context: context,
                                            builder: (dialogContext) {
                                              return AlertDialog(
                                                title: Text(l10n.removeMember),
                                                content: Text(l10n.confirmRemoveMember),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(dialogContext),
                                                    child: Text(l10n.btnCancel),
                                                  ),
                                                  ElevatedButton(
                                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                                    onPressed: () {
                                                      db.removeFamilyMember(member.idUsuario);
                                                      Navigator.pop(dialogContext);
                                                    },
                                                    child: Text(l10n.btnDelete, style: const TextStyle(color: Colors.white)),
                                                  ),
                                                ],
                                              );
                                            },
                                          );
                                        },
                                      )
                                    : null,
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.exit_to_app_rounded),
                      label: Text(l10n.leaveFamily, style: const TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (dialogContext) {
                            return AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              title: Text(l10n.confirmLeaveFamilyTitle),
                              content: Text(l10n.confirmLeaveFamilyMsg),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialogContext),
                                  child: Text(l10n.btnCancel),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                  onPressed: () async {
                                    Navigator.pop(dialogContext);
                                    final screenNav = Navigator.of(context);
                                    final messenger = ScaffoldMessenger.of(context);

                                    await db.leaveFamily(family.idFamilia);

                                    messenger.showSnackBar(
                                      SnackBar(content: Text(l10n.leftFamilySuccess)),
                                    );

                                    screenNav.pop();
                                  },
                                  child: Text(l10n.leaveFamily, style: const TextStyle(color: Colors.white)),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
