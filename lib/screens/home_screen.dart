import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/shopping_list_model.dart';
import '../services/database_service.dart';
import '../services/locale_provider.dart';
import 'about_privacy_screen.dart';
import 'family_members_screen.dart';
import 'list_detail_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  void _refreshData() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<DatabaseService>().fetchFamilyData();
      }
    });
  }

  void _showCreateListDialog() {
    final l10n = AppLocalizations.of(context)!;
    final listNameController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(l10n.newListTitle),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: listNameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.listNameLabel,
                hintText: l10n.listNameHint,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? l10n.listNameLabel : null,
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
                  final dialogNav = Navigator.of(dialogContext);
                  final listName = listNameController.text.trim();

                  try {
                    await db.createNewList(listName);
                    dialogNav.pop();
                    _refreshData();
                  } catch (e) {
                    if (e.toString().contains("LIST_ALREADY_EXISTS")) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(l10n.listAlreadyExistsErr),
                          backgroundColor: Colors.orange[900],
                        ),
                      );
                    } else {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(e.toString()),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              child: Text(l10n.btnCreateList),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _confirmDeleteList(ShoppingListModel list) async {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<DatabaseService>();

    if (db.hasPendingItems(list.idListaCompra)) {
      final res = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(l10n.confirmDeleteTitle),
            content: Text(l10n.confirmDeleteMsg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.btnCancel),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l10n.btnDelete, style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      );
      return res ?? false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final db = context.watch<DatabaseService>();
    final family = db.currentFamily;
    final user = db.currentUser;
    final shoppingLists = db.getActiveShoppingLists();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeTitle),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: "Sincronizar",
            onPressed: () => db.fetchFamilyData(),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(color: theme.colorScheme.primary),
              accountName: Text(user?.nbCompleto ?? 'Usuario'),
              accountEmail: Text(user?.nbEmail ?? ''),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white,
                child: Text(
                  user?.nbCompleto.isNotEmpty == true ? user!.nbCompleto[0].toUpperCase() : 'U',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.people_rounded),
              title: Text(l10n.menuFamilyMembers),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FamilyMembersScreen()),
                );
                _refreshData();
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(l10n.menuAbout),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AboutPrivacyScreen()),
                );
              },
            ),
            const Divider(),
            Consumer<LocaleProvider>(
              builder: (context, localeProvider, child) {
                final currentCode = localeProvider.locale == null ? 'system' : localeProvider.locale!.languageCode;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.language_rounded, color: Colors.grey),
                          const SizedBox(width: 12),
                          Text(l10n.menuLanguage, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      DropdownButton<String>(
                        isExpanded: true,
                        value: currentCode,
                        underline: const SizedBox(),
                        items: [
                          DropdownMenuItem(value: 'system', child: Text(l10n.systemDefault)),
                          DropdownMenuItem(value: 'es', child: Text(l10n.spanish)),
                          DropdownMenuItem(value: 'en', child: Text(l10n.english)),
                        ],
                        onChanged: (val) {
                          if (val == 'system') {
                            localeProvider.setLocale(null);
                          } else if (val != null) {
                            localeProvider.setLocale(Locale(val));
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: Colors.red),
              title: Text(l10n.menuLogout, style: const TextStyle(color: Colors.red)),
              onTap: () {
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
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => db.fetchFamilyData(),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    Text(
                      family?.nbFamilia ?? "Familia",
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (family != null)
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: family.clFamilia));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.copiedCode)),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "${l10n.familyCodeBadge} ${family.clFamilia}",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.copy_rounded, size: 16, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.homeTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_rounded, size: 36, color: Colors.blue),
                      tooltip: l10n.newListTitle,
                      onPressed: _showCreateListDialog,
                    ),
                  ],
                ),
              ),

              Expanded(
                child: shoppingLists.isEmpty
                    ? Center(child: Text(l10n.newListTitle))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        itemCount: shoppingLists.length,
                        itemBuilder: (context, index) {
                          final list = shoppingLists[index];

                          final cardChild = Card(
                            elevation: list.isDefault ? 3 : 1,
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: list.isDefault
                                  ? BorderSide(color: theme.colorScheme.primary, width: 2)
                                  : BorderSide(color: Colors.grey[300]!),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: list.isDefault
                                      ? theme.colorScheme.primary.withValues(alpha: 0.1)
                                      : Colors.grey[100],
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  list.isDefault ? Icons.star_rounded : Icons.shopping_bag_rounded,
                                  color: list.isDefault ? theme.colorScheme.primary : Colors.grey[700],
                                ),
                              ),
                              title: Text(
                                list.nbLista,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: list.isDefault ? theme.colorScheme.primary : Colors.black87,
                                ),
                              ),
                              subtitle: list.isDefault
                                  ? const Text("Lista Principal Fija", style: TextStyle(fontSize: 12, color: Colors.grey))
                                  : Text(l10n.swipeToDeleteHint, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              trailing: const Icon(Icons.chevron_right_rounded, size: 28),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ListDetailScreen(shoppingList: list),
                                  ),
                                );
                                _refreshData();
                              },
                            ),
                          );

                          if (list.isDefault) {
                            return cardChild;
                          }

                          return Dismissible(
                            key: Key(list.idListaCompra),
                            direction: DismissDirection.startToEnd,
                            confirmDismiss: (_) => _confirmDeleteList(list),
                            onDismissed: (_) {
                              db.softDeleteShoppingList(list.idListaCompra);
                            },
                            background: Container(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 24),
                              child: const Row(
                                children: [
                                  Icon(Icons.delete_rounded, color: Colors.white, size: 28),
                                  SizedBox(width: 8),
                                  Text(
                                    "Eliminar Lista",
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            child: cardChild,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
