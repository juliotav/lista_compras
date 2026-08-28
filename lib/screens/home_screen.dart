import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/shopping_list_model.dart';
import '../services/database_service.dart';
import '../services/locale_provider.dart';
import '../services/theme_provider.dart';
import 'about_privacy_screen.dart';
import 'family_members_screen.dart';
import 'family_setup_screen.dart';
import 'list_detail_screen.dart';
import 'login_screen.dart';
import '../widgets/ad_banner_widget.dart';
import '../services/ad_interstitial_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    AdInterstitialService.preloadAd();
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
              textCapitalization: TextCapitalization.sentences,
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

    final userFamilies = db.userFamilies;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeTitle),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n.syncTooltip,
            onPressed: () => db.fetchFamilyData(),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF261843)
                    : Colors.deepPurple,
              ),
              accountName: Text(
                user?.nbCompleto ?? l10n.defaultUser,
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
              accountEmail: Text(
                user?.nbEmail ?? '',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
              ),
              currentAccountPicture: CircleAvatar(
                backgroundColor: theme.colorScheme.primary,
                child: Text(
                  user?.nbCompleto.isNotEmpty == true ? user!.nbCompleto[0].toUpperCase() : 'U',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E1035) : Colors.white,
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.family_restroom_rounded),
              title: Text(l10n.addOrJoinFamily),
              onTap: () {
                Navigator.pop(context);
                AdInterstitialService.showAdIfAllowedThenNavigate(
                  context: context,
                  onNavigate: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const FamilySetupScreen()),
                    );
                    _refreshData();
                  },
                );
              },
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
            Consumer<ThemeProvider>(
              builder: (context, themeProvider, child) {
                String currentTheme;
                if (themeProvider.themeMode == ThemeMode.light) {
                  currentTheme = 'light';
                } else if (themeProvider.themeMode == ThemeMode.dark) {
                  currentTheme = 'dark';
                } else {
                  currentTheme = 'system';
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.brightness_6_rounded, color: Colors.grey),
                          SizedBox(width: 12),
                          Text("Tema visual", style: TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      DropdownButton<String>(
                        isExpanded: true,
                        value: currentTheme,
                        underline: const SizedBox(),
                        items: [
                          DropdownMenuItem(value: 'system', child: Text(l10n.systemDefault)),
                          const DropdownMenuItem(value: 'light', child: Text("Modo Claro")),
                          const DropdownMenuItem(value: 'dark', child: Text("Modo Oscuro")),
                        ],
                        onChanged: (val) {
                          if (val == 'light') {
                            themeProvider.setThemeMode(ThemeMode.light);
                          } else if (val == 'dark') {
                            themeProvider.setThemeMode(ThemeMode.dark);
                          } else {
                            themeProvider.setThemeMode(ThemeMode.system);
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF1E1035)
                      : theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    if (userFamilies.isNotEmpty)
                      PopupMenuButton<String>(
                        tooltip: l10n.selectFamily,
                        offset: const Offset(0, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 6,
                        onSelected: (String val) async {
                          if (val == '__add_new_family__') {
                            AdInterstitialService.showAdIfAllowedThenNavigate(
                              context: context,
                              onNavigate: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const FamilySetupScreen()),
                                );
                                _refreshData();
                              },
                            );
                          } else {
                            await db.switchFamily(val);
                          }
                        },
                        itemBuilder: (context) {
                          final items = <PopupMenuEntry<String>>[];
                          for (final fam in userFamilies) {
                            final isSelected = fam.idFamilia == family?.idFamilia;
                            items.add(
                              PopupMenuItem<String>(
                                value: fam.idFamilia,
                                child: Row(
                                  children: [
                                    Icon(
                                      isSelected ? Icons.check_circle_rounded : Icons.family_restroom_rounded,
                                      color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        fam.nbFamilia,
                                        style: TextStyle(
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                          color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          items.add(const PopupMenuDivider());
                          items.add(
                            PopupMenuItem<String>(
                              value: '__add_new_family__',
                              child: Row(
                                children: [
                                  Icon(Icons.add_circle_outline_rounded, color: theme.colorScheme.primary, size: 20),
                                  const SizedBox(width: 12),
                                  Text(
                                    l10n.addOrJoinFamily,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                          return items;
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: theme.cardColor,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                            border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.home_work_rounded, color: theme.colorScheme.primary, size: 22),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  family?.nbFamilia ?? l10n.defaultFamily,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(Icons.keyboard_arrow_down_rounded, color: theme.colorScheme.primary),
                            ],
                          ),
                        ),
                      )
                    else
                      ElevatedButton.icon(
                        icon: const Icon(Icons.group_add_rounded),
                        label: Text(l10n.addOrJoinFamily),
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () {
                          AdInterstitialService.showAdIfAllowedThenNavigate(
                            context: context,
                            onNavigate: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const FamilySetupScreen()),
                              );
                              _refreshData();
                            },
                          );
                        },
                      ),
                    const SizedBox(height: 10),
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
                            color: theme.cardColor,
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
                                  : BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: list.isDefault
                                      ? theme.colorScheme.primary.withValues(alpha: 0.15)
                                      : theme.colorScheme.onSurface.withValues(alpha: 0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  list.isDefault ? Icons.star_rounded : Icons.shopping_bag_rounded,
                                  color: list.isDefault ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                ),
                              ),
                              title: Text(
                                list.nbLista,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: list.isDefault ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                                ),
                              ),
                              subtitle: list.isDefault
                                  ? Text(l10n.primaryFixedListTag, style: const TextStyle(fontSize: 12, color: Colors.grey))
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
                              child: Row(
                                children: [
                                  const Icon(Icons.delete_rounded, color: Colors.white, size: 28),
                                  const SizedBox(width: 8),
                                  Text(
                                    l10n.deleteListAction,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
      bottomNavigationBar: const SafeArea(
        child: AdBannerWidget(),
      ),
    );
  }
}
