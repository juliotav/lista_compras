import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/shopping_list_model.dart';
import '../services/database_service.dart';
import '../services/locale_provider.dart';

class ListDetailScreen extends StatefulWidget {
  final ShoppingListModel shoppingList;

  const ListDetailScreen({super.key, required this.shoppingList});

  @override
  State<ListDetailScreen> createState() => _ListDetailScreenState();
}

class _ListDetailScreenState extends State<ListDetailScreen> {
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<DatabaseService>().fetchFamilyData();
      }
    });

    // Auto-sincronización al vuelo cada 4 segundos mientras la pantalla está abierta
    _syncTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) {
        context.read<DatabaseService>().fetchFamilyData();
      }
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  void _showAddCustomItemDialog() {
    final l10n = AppLocalizations.of(context)!;
    final itemController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(l10n.addCustomItemTitle),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: itemController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.itemNameLabel,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? l10n.itemNameLabel : null,
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
                  final dialogNav = Navigator.of(dialogContext);
                  await db.addCustomItemToCatalogAndList(
                    idListaCompra: widget.shoppingList.idListaCompra,
                    nbArticulo: itemController.text.trim(),
                  );
                  dialogNav.pop();
                  db.fetchFamilyData();
                }
              },
              child: Text(l10n.btnAdd),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleFinishEntireList() async {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<DatabaseService>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final success = await db.markListAsCompleted(widget.shoppingList.idListaCompra);

    if (success) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.listFinishedSuccess),
          backgroundColor: Colors.green,
        ),
      );
      navigator.pop();
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.cannotFinishPendingItemsErr),
          backgroundColor: Colors.orange[900],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final db = context.watch<DatabaseService>();
    final localeProvider = context.watch<LocaleProvider>();
    final currentLang = localeProvider.locale?.languageCode ?? 'es';

    final pendingItems = db.getPendingItems(widget.shoppingList.idListaCompra);
    final completedItems = db.getCompletedItems(widget.shoppingList.idListaCompra);
    final catalogItems = db.getCatalogItems();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.shoppingList.nbLista),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: "Sincronizar",
            onPressed: () => db.fetchFamilyData(),
          ),
          IconButton(
            icon: const Icon(Icons.check_circle_outline_rounded, size: 28),
            tooltip: l10n.finishListTooltip,
            onPressed: _handleFinishEntireList,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => db.fetchFamilyData(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- SECCIÓN 1: ARTÍCULOS POR COMPRAR ---
              Row(
                children: [
                  const Icon(Icons.list_alt_rounded, color: Colors.deepPurple),
                  const SizedBox(width: 8),
                  Text(
                    l10n.pendingItemsHeader,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${pendingItems.length}",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Container(
                constraints: const BoxConstraints(minHeight: 120),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: pendingItems.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Text(
                            "No hay artículos pendientes. Toca un artículo abajo para agregarlo.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: pendingItems.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = pendingItems[index];
                          return Dismissible(
                            key: Key(item.idDetalle),
                            direction: DismissDirection.startToEnd,
                            background: Container(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 20),
                              color: Colors.green,
                              child: const Row(
                                children: [
                                  Icon(Icons.check_rounded, color: Colors.white, size: 28),
                                  SizedBox(width: 8),
                                  Text(
                                    "Comprado",
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            onDismissed: (_) {
                              db.markItemAsCompleted(item.idDetalle);
                            },
                            child: ListTile(
                              title: Text(
                                item.nbArticulo,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                              ),
                              trailing: const Icon(Icons.swipe_right_rounded, color: Colors.grey, size: 20),
                            ),
                          );
                        },
                      ),
              ),

              const SizedBox(height: 28),

              // --- SECCIÓN 2: LISTA DE ARTÍCULOS FAST-SELECT ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bolt_rounded, color: Colors.amber),
                      const SizedBox(width: 8),
                      Text(
                        l10n.fastSelectHeader,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber[900],
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.blue, size: 28),
                    tooltip: l10n.addCustomItemTitle,
                    onPressed: _showAddCustomItemDialog,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Container(
                constraints: const BoxConstraints(minHeight: 120),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: catalogItems.isEmpty
                    ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text("No hay catálogo disponible.")))
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: catalogItems.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final catItem = catalogItems[index];
                          final name = catItem.getLocalizedName(currentLang);

                          return ListTile(
                            dense: true,
                            title: Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                            ),
                            trailing: const Icon(Icons.add_rounded, color: Colors.blue),
                            onTap: () async {
                              await db.addItemToList(
                                idListaCompra: widget.shoppingList.idListaCompra,
                                idArticulo: catItem.idArticulo,
                                nbArticulo: name,
                              );
                              db.fetchFamilyData();
                            },
                          );
                        },
                      ),
              ),

              const SizedBox(height: 28),

              // --- SECCIÓN 3: ARTÍCULOS YA COMPRADOS ---
              if (completedItems.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      l10n.completedItemsHeader,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "${completedItems.length}",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green[800],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: completedItems.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = completedItems[index];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.check_box_rounded, color: Colors.green),
                        title: Text(
                          item.nbArticulo,
                          style: TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: Colors.grey[700],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
