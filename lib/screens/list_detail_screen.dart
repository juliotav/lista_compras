import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/list_detail_item_model.dart';
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

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

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim();
      });
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _addCustomItem(String itemName) async {
    final cleanName = itemName.trim();
    if (cleanName.isEmpty) return;

    final db = context.read<DatabaseService>();
    await db.addCustomItemToCatalogAndList(
      idListaCompra: widget.shoppingList.idListaCompra,
      nbArticulo: cleanName,
    );
    _searchController.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    db.fetchFamilyData();
  }

  void _showAddCustomItemDialog() {
    final l10n = AppLocalizations.of(context)!;
    final itemController = TextEditingController(text: _searchQuery);
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
                  final dialogNav = Navigator.of(dialogContext);
                  final text = itemController.text;
                  dialogNav.pop();
                  await _addCustomItem(text);
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

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(l10n.confirmFinishListTitle),
          content: Text(l10n.confirmFinishListMsg),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.btnCancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.btnFinish, style: const TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await db.finishAndCompleteEntireList(widget.shoppingList.idListaCompra);
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.listFinishedSuccess),
          backgroundColor: Colors.green,
        ),
      );
      navigator.pop();
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

    // Filtrar el catálogo al vuelo según el texto ingresado en el buscador
    final filteredCatalog = catalogItems.where((c) {
      final name = c.getLocalizedName(currentLang).toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    // Verificar si el texto escrito existe exactamente en el catálogo de esta familia
    final hasExactMatch = catalogItems.any(
      (c) => c.getLocalizedName(currentLang).toLowerCase() == _searchQuery.toLowerCase(),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.shoppingList.nbLista),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n.syncTooltip,
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
                            l10n.noPendingItemsMsg,
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
                            direction: DismissDirection.horizontal,
                            background: Container(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 20),
                              color: Colors.green,
                              child: Row(
                                children: [
                                  const Icon(Icons.check_rounded, color: Colors.white, size: 28),
                                  const SizedBox(width: 8),
                                  Text(
                                    l10n.statusPurchased,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            secondaryBackground: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              color: Colors.red,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    l10n.actionDelete,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 28),
                                ],
                              ),
                            ),
                            onDismissed: (direction) {
                              if (direction == DismissDirection.startToEnd) {
                                db.markItemAsCompleted(item.idDetalle);
                              } else if (direction == DismissDirection.endToStart) {
                                db.removeListDetailItem(item.idDetalle);
                              }
                            },
                            child: PendingItemTile(
                              item: item,
                              onSaveNote: (newNote) {
                                db.updateItemDetailNote(item.idDetalle, newNote);
                              },
                            ),
                          );
                        },
                      ),
              ),

              const SizedBox(height: 28),

              // --- SECCIÓN 2: BUSCADOR AL VUELO Y CATÁLOGO RÁPIDO ---
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

              // CAMPO DE BÚSQUEDA AL VUELO
              TextField(
                controller: _searchController,
                textInputAction: TextInputAction.done,
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    _addCustomItem(value);
                  }
                },
                decoration: InputDecoration(
                  hintText: l10n.searchOrTypeItemHint,
                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.deepPurple),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.deepPurple.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Container(
                constraints: const BoxConstraints(minHeight: 100),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    // Opción dinámica de agregar artículo personalizado cuando el usuario escribe algo no coincidente
                    if (_searchQuery.isNotEmpty && !hasExactMatch)
                      ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        tileColor: Colors.deepPurple.withValues(alpha: 0.08),
                        leading: const CircleAvatar(
                          backgroundColor: Colors.deepPurple,
                          radius: 14,
                          child: Icon(Icons.add_rounded, color: Colors.white, size: 18),
                        ),
                        title: Text(
                          l10n.addQueryToListOption(_searchQuery),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple,
                          ),
                        ),
                        subtitle: Text(
                          l10n.addQueryToListSubtitle,
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        onTap: () => _addCustomItem(_searchQuery),
                      ),

                    if (filteredCatalog.isEmpty && (_searchQuery.isEmpty || hasExactMatch))
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(child: Text(l10n.noCatalogItemsFound)),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredCatalog.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final catItem = filteredCatalog[index];
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
                              _searchController.clear();
                              FocusManager.instance.primaryFocus?.unfocus();
                              db.fetchFamilyData();
                            },
                          );
                        },
                      ),
                  ],
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
                        subtitle: item.dsDetalle != null && item.dsDetalle!.trim().isNotEmpty
                            ? Text(
                                item.dsDetalle!,
                                style: TextStyle(
                                  decoration: TextDecoration.lineThrough,
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              )
                            : null,
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

class PendingItemTile extends StatefulWidget {
  final ListDetailItemModel item;
  final Function(String) onSaveNote;

  const PendingItemTile({
    super.key,
    required this.item,
    required this.onSaveNote,
  });

  @override
  State<PendingItemTile> createState() => _PendingItemTileState();
}

class _PendingItemTileState extends State<PendingItemTile> {
  bool _isEditingNote = false;
  late TextEditingController _noteController;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.item.dsDetalle ?? "");
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        if (_isEditingNote) {
          setState(() {
            _isEditingNote = false;
          });
          widget.onSaveNote(_noteController.text);
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant PendingItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.dsDetalle != widget.item.dsDetalle && !_isEditingNote) {
      _noteController.text = widget.item.dsDetalle ?? "";
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _isEditingNote = true;
    });
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final noteText = widget.item.dsDetalle?.trim() ?? "";

    return InkWell(
      onTap: () {
        if (!_isEditingNote) {
          _startEditing();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.item.nbArticulo,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  const SizedBox(height: 4),

                  if (_isEditingNote) ...[
                    TextField(
                      controller: _noteController,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(fontSize: 13, color: Colors.black87),
                      decoration: InputDecoration(
                        hintText: l10n.addDetailHint,
                        hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.deepPurple, width: 1.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
                        ),
                      ),
                      onSubmitted: (val) {
                        setState(() {
                          _isEditingNote = false;
                        });
                        widget.onSaveNote(val);
                      },
                    ),
                  ] else ...[
                    GestureDetector(
                      onTap: _startEditing,
                      child: Text(
                        noteText.isNotEmpty ? noteText : l10n.tapToAddDetail,
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle: noteText.isEmpty ? FontStyle.italic : FontStyle.normal,
                          color: noteText.isNotEmpty ? Colors.deepPurple[700] : Colors.grey[500],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swipe_right_rounded, color: Colors.green, size: 16),
                SizedBox(width: 2),
                Icon(Icons.swipe_left_rounded, color: Colors.red, size: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
