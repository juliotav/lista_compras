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
import '../services/coach_mark_service.dart';
import '../services/connectivity_service.dart';
import '../widgets/coach_mark_overlay.dart';
import '../widgets/sync_indicator_widget.dart';
import '../widgets/family_qr_dialog.dart';
import '../widgets/logout_confirm_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey _defaultListKey = GlobalKey();
  final GlobalKey _addListKey = GlobalKey();
  final GlobalKey _familyCodeKey = GlobalKey();
  final GlobalKey _familyQrKey = GlobalKey();
  final GlobalKey _familyDropdownKey = GlobalKey();
  final GlobalKey _refreshListsKey = GlobalKey();
  final GlobalKey _drawerMenuKey = GlobalKey();
  bool _coachMarkChecked = false;

  @override
  void initState() {
    super.initState();
    AdInterstitialService.preloadAd();
    _refreshData(checkCoachMark: true);
  }

  void _refreshData({bool checkCoachMark = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        final db = context.read<DatabaseService>();
        await db.loadLocalDataOnly();
        final fetchFuture = db.fetchFamilyData();
        if (checkCoachMark && !_coachMarkChecked) {
          _coachMarkChecked = true;
          await _maybeShowInitialCoachMark(fetchFuture);
        }
      }
    });
  }

  Future<void> _maybeShowInitialCoachMark(Future<void> fetchFuture) async {
    if (!mounted) return;
    final db = context.read<DatabaseService>();
    final userId = db.currentUser?.idUsuario;
    if (userId == null) return;

    final hasSeen = await CoachMarkService.hasSeenTour(
      CoachMarkTour.home,
      userId,
    );
    if (hasSeen || !mounted) return;

    // Si aún no hay listas locales (ej. primer inicio en otro dispositivo), espera brevemente la descarga
    if (db.getActiveShoppingLists().isEmpty) {
      await fetchFuture.timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      );
    }

    await Future.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    await _showHomeCoachMark(markAsSeen: true);
  }

  Future<void> _showHomeCoachMark({required bool markAsSeen}) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final userId = context.read<DatabaseService>().currentUser?.idUsuario;

    final steps = <CoachMarkStep>[
      CoachMarkStep(
        targetKey: _defaultListKey,
        title: l10n.coachHomeDefaultListTitle,
        description: l10n.coachHomeDefaultListDesc,
        borderRadius: 16,
      ),
      CoachMarkStep(
        targetKey: _addListKey,
        title: l10n.coachHomeAddListTitle,
        description: l10n.coachHomeAddListDesc,
        isCircle: true,
        highlightPadding: const EdgeInsets.all(4),
      ),
      CoachMarkStep(
        targetKey: _familyCodeKey,
        title: l10n.coachHomeFamilyCodeTitle,
        description: l10n.coachHomeFamilyCodeDesc,
        borderRadius: 12,
      ),
      CoachMarkStep(
        targetKey: _familyQrKey,
        title: l10n.coachHomeFamilyQrTitle,
        description: l10n.coachHomeFamilyQrDesc,
        borderRadius: 12,
      ),
      CoachMarkStep(
        targetKey: _familyDropdownKey,
        title: l10n.coachHomeFamilyDropdownTitle,
        description: l10n.coachHomeFamilyDropdownDesc,
        borderRadius: 20,
      ),
      CoachMarkStep(
        targetKey: _refreshListsKey,
        title: l10n.coachHomeRefreshTitle,
        description: l10n.coachHomeRefreshDesc,
        isCircle: true,
        highlightPadding: const EdgeInsets.all(4),
      ),
      CoachMarkStep(
        targetKey: _drawerMenuKey,
        title: l10n.coachHomeMenuTitle,
        description: l10n.coachHomeMenuDesc,
        isCircle: true,
        highlightPadding: const EdgeInsets.all(4),
      ),
    ];

    await CoachMarkController.show(
      context: context,
      steps: steps,
      onComplete: markAsSeen
          ? () => CoachMarkService.markTourSeen(CoachMarkTour.home, userId)
          : null,
    );
  }

  void _showCoachMarkGuideSheet() {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final db = context.read<DatabaseService>();
    final userId = db.currentUser?.idUsuario;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.help_outline_rounded,
                      color: theme.colorScheme.primary,
                      size: 26,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.coachGuideSheetTitle,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.coachGuideSheetSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor:
                        theme.colorScheme.primary.withValues(alpha: 0.12),
                    child: Icon(
                      Icons.family_restroom_rounded,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  title: Text(
                    l10n.coachGuideOptionFamilySetup,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(l10n.coachGuideOptionFamilySetupDesc),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const FamilySetupScreen(startCoachMark: true),
                      ),
                    );
                    _refreshData();
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Colors.teal.withValues(alpha: 0.12),
                    child: const Icon(
                      Icons.qr_code_scanner_rounded,
                      color: Colors.teal,
                    ),
                  ),
                  title: Text(
                    l10n.coachGuideOptionJoinFamily,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(l10n.coachGuideOptionJoinFamilyDesc),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FamilySetupScreen(
                          openJoinDialogWithCoachMark: true,
                        ),
                      ),
                    );
                    _refreshData();
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Colors.indigo.withValues(alpha: 0.12),
                    child: const Icon(
                      Icons.shopping_cart_rounded,
                      color: Colors.indigo,
                    ),
                  ),
                  title: Text(
                    l10n.coachGuideOptionHome,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(l10n.coachGuideOptionHomeDesc),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await Future.delayed(const Duration(milliseconds: 280));
                    if (mounted) {
                      await _showHomeCoachMark(markAsSeen: false);
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Colors.amber.withValues(alpha: 0.16),
                    child: Icon(
                      Icons.checklist_rounded,
                      color: Colors.amber[800],
                    ),
                  ),
                  title: Text(
                    l10n.coachGuideOptionListDetail,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(l10n.coachGuideOptionListDetailDesc),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final activeLists = db.getActiveShoppingLists();
                    if (activeLists.isEmpty) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.coachGuideNoListAvailable)),
                        );
                      }
                      return;
                    }
                    final targetList = activeLists.firstWhere(
                      (l) => l.isDefault,
                      orElse: () => activeLists.first,
                    );
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ListDetailScreen(
                          shoppingList: targetList,
                          startCoachMark: true,
                        ),
                      ),
                    );
                    _refreshData();
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Colors.green.withValues(alpha: 0.14),
                    child: Icon(
                      Icons.restore_rounded,
                      color: Colors.green[700],
                    ),
                  ),
                  title: Text(
                    l10n.coachGuideOptionPurchasedActions,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(l10n.coachGuideOptionPurchasedActionsDesc),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final activeLists = db.getActiveShoppingLists();
                    final listsWithPurchased = activeLists
                        .where(
                          (l) => db
                              .getCompletedItems(l.idListaCompra)
                              .isNotEmpty,
                        )
                        .toList();
                    if (listsWithPurchased.isEmpty) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              l10n.coachGuideNoPurchasedListAvailable,
                            ),
                            backgroundColor: Colors.orange[800],
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                      return;
                    }
                    final targetList = listsWithPurchased.firstWhere(
                      (l) => l.isDefault,
                      orElse: () => listsWithPurchased.first,
                    );
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ListDetailScreen(
                          shoppingList: targetList,
                          startPurchasedCoachMark: true,
                        ),
                      ),
                    );
                    _refreshData();
                  },
                ),
                const Divider(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.withValues(alpha: 0.12),
                    child: Icon(
                      Icons.restart_alt_rounded,
                      color: Colors.orange[800],
                    ),
                  ),
                  title: Text(
                    l10n.coachGuideOptionResetAll,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(l10n.coachGuideOptionResetAllDesc),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await CoachMarkService.resetAllTours(userId);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.coachGuideResetSuccess),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                    await Future.delayed(const Duration(milliseconds: 350));
                    if (mounted) {
                      await _showHomeCoachMark(markAsSeen: true);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCreateListDialog() {
    final l10n = AppLocalizations.of(context)!;
    final listNameController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? l10n.listNameLabel : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.btnCancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
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
                child: Text(
                  l10n.btnDelete,
                  style: const TextStyle(color: Colors.white),
                ),
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

    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final shoppingLists = db.getActiveShoppingLists();
    final defaultListIdx = shoppingLists.indexWhere((l) => l.isDefault);
    final coachListTargetIndex = defaultListIdx != -1 ? defaultListIdx : 0;

    final userFamilies = db.userFamilies;

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            key: _drawerMenuKey,
            icon: const Icon(Icons.menu),
            tooltip: MaterialLocalizations.of(ctx).openAppDrawerTooltip,
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Text(l10n.homeTitle),
        centerTitle: true,
        actions: [
          const SyncIndicatorWidget(),
          IconButton(
            key: _refreshListsKey,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n.syncTooltip,
            onPressed: () async {
              if (db.isOffline) {
                final restored = await ConnectivityService()
                    .checkConnectivity();
                if (!restored && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(
                            Icons.cloud_off_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.offlineTooltip,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: Colors.orange.shade800,
                      duration: const Duration(seconds: 3),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
              }
              await db.fetchFamilyData();
            },
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
                user.nbCompleto.isNotEmpty ? user.nbCompleto : l10n.defaultUser,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              accountEmail: Text(
                user.nbEmail,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
              ),
              currentAccountPicture: CircleAvatar(
                backgroundColor: theme.colorScheme.primary,
                child: Text(
                  user.nbCompleto.isNotEmpty
                      ? user.nbCompleto[0].toUpperCase()
                      : 'U',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF1E1035)
                        : Colors.white,
                  ),
                ),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: const Icon(Icons.family_restroom_rounded),
                title: Text(l10n.addOrJoinFamily),
                onTap: () {
                  Navigator.pop(context);
                  AdInterstitialService.showAdIfAllowedThenNavigate(
                    context: context,
                    onNavigate: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FamilySetupScreen(),
                        ),
                      );
                      _refreshData();
                    },
                  );
                },
              ),
            ),
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: const Icon(Icons.people_rounded),
                title: Text(l10n.menuFamilyMembers),
                onTap: () async {
                  Navigator.pop(context);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FamilyMembersScreen(),
                    ),
                  );
                  _refreshData();
                },
              ),
            ),
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(l10n.menuAbout),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AboutPrivacyScreen(),
                    ),
                  );
                },
              ),
            ),
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: const Icon(Icons.help_outline_rounded),
                title: Text(l10n.menuCoachMarkGuide),
                onTap: () {
                  Navigator.pop(context);
                  _showCoachMarkGuideSheet();
                },
              ),
            ),
            const Divider(),
            Consumer<LocaleProvider>(
              builder: (context, localeProvider, child) {
                final currentCode = localeProvider.locale == null
                    ? 'system'
                    : localeProvider.locale!.languageCode;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.language_rounded,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            l10n.menuLanguage,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      DropdownButton<String>(
                        isExpanded: true,
                        value: currentCode,
                        underline: const SizedBox(),
                        items: [
                          DropdownMenuItem(
                            value: 'system',
                            child: Text(l10n.systemDefault),
                          ),
                          DropdownMenuItem(
                            value: 'es',
                            child: Text(l10n.spanish),
                          ),
                          DropdownMenuItem(
                            value: 'en',
                            child: Text(l10n.english),
                          ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.brightness_6_rounded,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            l10n.menuTheme,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      DropdownButton<String>(
                        isExpanded: true,
                        value: currentTheme,
                        underline: const SizedBox(),
                        items: [
                          DropdownMenuItem(
                            value: 'system',
                            child: Text(l10n.systemDefault),
                          ),
                          DropdownMenuItem(
                            value: 'light',
                            child: Text(l10n.themeLight),
                          ),
                          DropdownMenuItem(
                            value: 'dark',
                            child: Text(l10n.themeDark),
                          ),
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
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: const Icon(Icons.logout_rounded, color: Colors.red),
                title: Text(
                  l10n.menuLogout,
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  final confirmed = await showLogoutConfirmDialog(context);
                  if (!confirmed || !context.mounted) return;
                  await db.logout();
                  if (!context.mounted) return;
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                },
              ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF1E1035)
                      : theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.3,
                        ),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    if (userFamilies.isNotEmpty)
                      PopupMenuButton<String>(
                        tooltip: l10n.selectFamily,
                        offset: const Offset(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 6,
                        onSelected: (String val) async {
                          if (val == '__add_new_family__') {
                            AdInterstitialService.showAdIfAllowedThenNavigate(
                              context: context,
                              onNavigate: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const FamilySetupScreen(),
                                  ),
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
                            final isSelected =
                                fam.idFamilia == family?.idFamilia;
                            items.add(
                              PopupMenuItem<String>(
                                value: fam.idFamilia,
                                child: Row(
                                  children: [
                                    Icon(
                                      isSelected
                                          ? Icons.check_circle_rounded
                                          : Icons.family_restroom_rounded,
                                      color: isSelected
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface
                                                .withValues(alpha: 0.6),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        fam.nbFamilia,
                                        style: TextStyle(
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: isSelected
                                              ? theme.colorScheme.primary
                                              : theme.colorScheme.onSurface,
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
                                  Icon(
                                    Icons.add_circle_outline_rounded,
                                    color: theme.colorScheme.primary,
                                    size: 20,
                                  ),
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
                          key: _familyDropdownKey,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
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
                            border: Border.all(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.home_work_rounded,
                                color: theme.colorScheme.primary,
                                size: 22,
                              ),
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
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: theme.colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ElevatedButton.icon(
                        icon: const Icon(Icons.group_add_rounded),
                        label: Text(l10n.addOrJoinFamily),
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () {
                          AdInterstitialService.showAdIfAllowedThenNavigate(
                            context: context,
                            onNavigate: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const FamilySetupScreen(),
                                ),
                              );
                              _refreshData();
                            },
                          );
                        },
                      ),
                    const SizedBox(height: 10),
                    if (family != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(text: family.clFamilia),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(l10n.copiedCode)),
                              );
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              key: _familyCodeKey,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: theme.cardColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "${l10n.familyCodeBadge} ${family.clFamilia}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.copy_rounded,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: l10n.showQrCodeTooltip,
                            child: InkWell(
                              onTap: () => showFamilyQrDialog(context, family),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                key: _familyQrKey,
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: theme.cardColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                                ),
                                child: Icon(
                                  Icons.qr_code_2_rounded,
                                  size: 20,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 8.0,
                ),
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
                      key: _addListKey,
                      icon: const Icon(
                        Icons.add_circle_rounded,
                        size: 36,
                        color: Colors.blue,
                      ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        itemCount: shoppingLists.length,
                        itemBuilder: (context, index) {
                          final list = shoppingLists[index];
                          final pendingCount = db.getPendingItemsCount(
                            list.idListaCompra,
                          );
                          final isDark = theme.brightness == Brightness.dark;

                          final cardChild = Card(
                            key: index == coachListTargetIndex
                                ? _defaultListKey
                                : null,
                            elevation: list.isDefault ? 3 : 1,
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: list.isDefault
                                  ? BorderSide(
                                      color: theme.colorScheme.primary,
                                      width: 2,
                                    )
                                  : BorderSide(
                                      color: theme.dividerColor.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ListDetailScreen(shoppingList: list),
                                  ),
                                );
                                _refreshData();
                              },
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  10,
                                  12,
                                  12,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: list.isDefault
                                            ? theme.colorScheme.primary
                                                  .withValues(alpha: 0.15)
                                            : theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.08),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        list.isDefault
                                            ? Icons.star_rounded
                                            : Icons.shopping_bag_rounded,
                                        color: list.isDefault
                                            ? theme.colorScheme.primary
                                            : theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.7),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 2,
                                                      ),
                                                  child: Text(
                                                    list.nbLista,
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 18,
                                                      color: list.isDefault
                                                          ? theme
                                                                .colorScheme
                                                                .primary
                                                          : theme
                                                                .colorScheme
                                                                .onSurface,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: pendingCount > 0
                                                      ? theme
                                                            .colorScheme
                                                            .primary
                                                            .withValues(
                                                              alpha: isDark
                                                                  ? 0.12
                                                                  : 0.06,
                                                            )
                                                      : theme
                                                            .colorScheme
                                                            .onSurface
                                                            .withValues(
                                                              alpha: 0.04,
                                                            ),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  border: Border.all(
                                                    width: 0.8,
                                                    color: pendingCount > 0
                                                        ? theme
                                                              .colorScheme
                                                              .primary
                                                              .withValues(
                                                                alpha: isDark
                                                                    ? 0.20
                                                                    : 0.16,
                                                              )
                                                        : theme.dividerColor
                                                              .withValues(
                                                                alpha: 0.18,
                                                              ),
                                                  ),
                                                ),
                                                child: Text(
                                                  l10n.pendingItemsBadge(
                                                    pendingCount,
                                                  ),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w500,
                                                    color: pendingCount > 0
                                                        ? theme
                                                              .colorScheme
                                                              .primary
                                                              .withValues(
                                                                alpha: isDark
                                                                    ? 0.80
                                                                    : 0.72,
                                                              )
                                                        : theme
                                                              .colorScheme
                                                              .onSurface
                                                              .withValues(
                                                                alpha: 0.45,
                                                              ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: list.isDefault
                                                    ? Text(
                                                        l10n.primaryFixedListTag,
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.grey,
                                                        ),
                                                      )
                                                    : Text(
                                                        l10n.swipeToDeleteHint,
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.grey,
                                                        ),
                                                      ),
                                              ),
                                              Icon(
                                                Icons.chevron_right_rounded,
                                                size: 24,
                                                color: theme
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.6),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
                                  const Icon(
                                    Icons.delete_rounded,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    l10n.deleteListAction,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
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
      bottomNavigationBar: const SafeArea(child: AdBannerWidget()),
    );
  }
}
