import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/item_catalog_model.dart';
import '../models/list_detail_item_model.dart';
import '../models/shopping_list_model.dart';
import '../services/database_service.dart';
import '../services/locale_provider.dart';
import '../services/push_notification_service.dart';
import '../widgets/ad_banner_widget.dart';
import '../widgets/sync_indicator_widget.dart';

enum PendingItemsSortOption {
  manual,
  alphabeticalAsc,
  alphabeticalDesc,
}

class ListDetailScreen extends StatefulWidget {
  final ShoppingListModel shoppingList;

  const ListDetailScreen({super.key, required this.shoppingList});

  @override
  State<ListDetailScreen> createState() => _ListDetailScreenState();
}

class _ListDetailScreenState extends State<ListDetailScreen> with WidgetsBindingObserver {
  Timer? _syncTimer;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = "";
  bool _isDraggingReorder = false;

  PendingItemsSortOption _pendingSortOption = PendingItemsSortOption.manual;
  bool _showPendingFilter = false;
  final TextEditingController _pendingFilterController = TextEditingController();
  String _pendingFilterQuery = "";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<DatabaseService>().fetchFamilyData();
        unawaited(PushNotificationService.clearBadge());
      }
    });

    _startSyncTimer();

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim();
      });
    });

    _pendingFilterController.addListener(() {
      setState(() {
        _pendingFilterQuery = _pendingFilterController.text.trim();
      });
    });
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 6), (_) async {
      if (mounted) {
        // Omitir sincronización periódica si el usuario está buscando, filtrando o arrastrando elementos
        if (_showPendingFilter || _pendingFilterQuery.isNotEmpty || _searchQuery.isNotEmpty || _isDraggingReorder) {
          return;
        }
        final db = context.read<DatabaseService>();
        if (db.isFetchingFamilyData) return;
        await db.fetchFamilyData(isSilentPeriodic: true);
      }
    });
  }

  Future<void> _runWithPausedSyncTimer(Future<void> Function() action) async {
    _stopSyncTimer();
    try {
      await action();
      if (mounted) {
        await context.read<DatabaseService>().syncNow();
      }
    } catch (e) {
      debugPrint("[LIST_DETAIL LOG] Error en acción manual con timer pausado: $e");
    } finally {
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          _startSyncTimer();
        }
      }
    }
  }

  void _stopSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      debugPrint("[LIST_DETAIL LOG] App reanudada desde segundo plano. Cargando SQLite de inmediato...");
      unawaited(PushNotificationService.clearBadge());
      final db = context.read<DatabaseService>();
      db.loadLocalDataOnly();
      db.onAppResume();
      _startSyncTimer();
    } else if ((state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) && mounted) {
      debugPrint("[LIST_DETAIL LOG] App en segundo plano. Deteniendo timer de sincronización...");
      _stopSyncTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopSyncTimer();
    _searchController.dispose();
    _pendingFilterController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _isDefaultSeedCatalogItem(ItemCatalogModel item) {
    const defaultSeedNames = {
      'carne', 'meat',
      'leche', 'milk',
      'cereal',
      'queso', 'cheese',
      'pan', 'bread',
      'huevos', 'eggs',
      'frutas', 'fruits',
      'verduras', 'vegetables',
    };
    final esName = item.nbArticuloEs.trim().toLowerCase();
    final enName = item.nbArticuloEn.trim().toLowerCase();
    return defaultSeedNames.contains(esName) || defaultSeedNames.contains(enName);
  }

  void _showEditCatalogItemDialog(ItemCatalogModel catItem) {
    final l10n = AppLocalizations.of(context)!;
    final localeProvider = context.read<LocaleProvider>();
    final currentLang = localeProvider.locale?.languageCode ?? 'es';

    if (_isDefaultSeedCatalogItem(catItem)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.cannotEditDefaultCatalogItem),
          backgroundColor: Colors.orange[800],
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final currentName = catItem.getLocalizedName(currentLang);
    final textController = TextEditingController(text: currentName);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(l10n.editCatalogItemTitle),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: textController,
              textCapitalization: TextCapitalization.sentences,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.itemNameLabel,
                hintText: l10n.editCatalogItemHint,
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
                  final newText = textController.text.trim();
                  dialogNav.pop();

                  _runWithPausedSyncTimer(() async {
                    final db = context.read<DatabaseService>();
                    await db.updateCatalogItemName(
                      idArticulo: catItem.idArticulo,
                      newName: newText,
                    );
                  });
                }
              },
              child: Text(l10n.btnAdd),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addCustomItem(String itemName) async {
    await _runWithPausedSyncTimer(() async {
      final cleanName = itemName.trim();
      if (cleanName.isEmpty) return;

      final l10n = AppLocalizations.of(context)!;
      final db = context.read<DatabaseService>();
      final added = await db.addCustomItemToCatalogAndList(
        idListaCompra: widget.shoppingList.idListaCompra,
        nbArticulo: cleanName,
      );

      if (!added && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.itemAlreadyInList(cleanName)),
            backgroundColor: Colors.orange[800],
            duration: const Duration(seconds: 2),
          ),
        );
      }

      _searchController.clear();
      FocusManager.instance.primaryFocus?.unfocus();
    });
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
              textCapitalization: TextCapitalization.sentences,
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
    final currentUserFam = db.currentUser?.idFamilia;

    if (currentUserFam == null || currentUserFam != widget.shoppingList.idFamilia) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });
    }

    final localeProvider = context.watch<LocaleProvider>();
    final currentLang = localeProvider.locale?.languageCode ?? 'es';

    List<ListDetailItemModel> pendingItems = db.getPendingItems(widget.shoppingList.idListaCompra);
    final completedItems = db.getCompletedItems(widget.shoppingList.idListaCompra);
    final catalogItems = db.getCatalogItems();

    // 1. Filtrar artículos por comprar si hay término de búsqueda activo en la sección
    if (_pendingFilterQuery.isNotEmpty) {
      final qLower = _pendingFilterQuery.toLowerCase();
      pendingItems = pendingItems.where((item) {
        final nameMatch = item.nbArticulo.toLowerCase().contains(qLower);
        final noteMatch = item.dsDetalle?.toLowerCase().contains(qLower) ?? false;
        return nameMatch || noteMatch;
      }).toList();
    }

    // 2. Aplicar ordenamiento
    switch (_pendingSortOption) {
      case PendingItemsSortOption.manual:
        break;
      case PendingItemsSortOption.alphabeticalAsc:
        pendingItems.sort((a, b) => a.nbArticulo.toLowerCase().compareTo(b.nbArticulo.toLowerCase()));
        break;
      case PendingItemsSortOption.alphabeticalDesc:
        pendingItems.sort((a, b) => b.nbArticulo.toLowerCase().compareTo(a.nbArticulo.toLowerCase()));
        break;
    }

    // Filtrar el catálogo al vuelo según el texto ingresado en el buscador Fast-Add
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
          const SyncIndicatorWidget(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n.syncTooltip,
            onPressed: () {
              _runWithPausedSyncTimer(() async {
                await db.fetchFamilyData();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.check_circle_outline_rounded, size: 28),
            tooltip: l10n.finishListTooltip,
            onPressed: _handleFinishEntireList,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _runWithPausedSyncTimer(() async {
            await db.fetchFamilyData();
          });
        },
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- SECCIÓN 1: ARTÍCULOS POR COMPRAR ---
              Row(
                children: [
                  Icon(Icons.list_alt_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    l10n.pendingItemsHeader,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${pendingItems.length}",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const Spacer(),

                  // Icono para desplegar/ocultar barra de búsqueda de por comprar
                  IconButton(
                    icon: Icon(
                      _showPendingFilter ? Icons.filter_alt_off_rounded : Icons.search_rounded,
                      color: _showPendingFilter || _pendingFilterQuery.isNotEmpty
                          ? theme.colorScheme.primary
                          : Colors.grey[700],
                      size: 22,
                    ),
                    tooltip: l10n.filterTooltip,
                    onPressed: () {
                      setState(() {
                        _showPendingFilter = !_showPendingFilter;
                        if (!_showPendingFilter) {
                          _pendingFilterController.clear();
                          _pendingFilterQuery = "";
                        }
                      });
                    },
                  ),

                  // Botón desplegable para seleccionar tipo de ordenamiento
                  PopupMenuButton<PendingItemsSortOption>(
                    icon: Icon(
                      Icons.sort_rounded,
                      color: _pendingSortOption != PendingItemsSortOption.manual
                          ? theme.colorScheme.primary
                          : Colors.grey[700],
                      size: 22,
                    ),
                    tooltip: l10n.sortTooltip,
                    initialValue: _pendingSortOption,
                    onSelected: (PendingItemsSortOption option) {
                      _runWithPausedSyncTimer(() async {
                        setState(() {
                          _pendingSortOption = option;
                        });
                        if (option != PendingItemsSortOption.manual) {
                          final db = context.read<DatabaseService>();
                          await db.saveAlphabeticalOrder(
                            widget.shoppingList.idListaCompra,
                            ascending: option == PendingItemsSortOption.alphabeticalAsc,
                          );
                        }
                      });
                    },
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<PendingItemsSortOption>>[
                      PopupMenuItem<PendingItemsSortOption>(
                        value: PendingItemsSortOption.manual,
                        child: Row(
                          children: [
                            Icon(
                              Icons.drag_indicator_rounded,
                              size: 18,
                              color: _pendingSortOption == PendingItemsSortOption.manual
                                  ? theme.colorScheme.primary
                                  : Colors.grey[600],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.sortOptionManual,
                              style: TextStyle(
                                fontWeight: _pendingSortOption == PendingItemsSortOption.manual
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem<PendingItemsSortOption>(
                        value: PendingItemsSortOption.alphabeticalAsc,
                        child: Row(
                          children: [
                            Icon(
                              Icons.sort_by_alpha_rounded,
                              size: 18,
                              color: _pendingSortOption == PendingItemsSortOption.alphabeticalAsc
                                  ? theme.colorScheme.primary
                                  : Colors.grey[600],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.sortOptionAlphabeticalAsc,
                              style: TextStyle(
                                fontWeight: _pendingSortOption == PendingItemsSortOption.alphabeticalAsc
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem<PendingItemsSortOption>(
                        value: PendingItemsSortOption.alphabeticalDesc,
                        child: Row(
                          children: [
                            Icon(
                              Icons.sort_by_alpha_rounded,
                              size: 18,
                              color: _pendingSortOption == PendingItemsSortOption.alphabeticalDesc
                                  ? theme.colorScheme.primary
                                  : Colors.grey[600],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.sortOptionAlphabeticalDesc,
                              style: TextStyle(
                                fontWeight: _pendingSortOption == PendingItemsSortOption.alphabeticalDesc
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // CAMPO DE BÚSQUEDA / FILTRO PARA ARTÍCULOS POR COMPRAR
              if (_showPendingFilter) ...[
                TextField(
                  controller: _pendingFilterController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: l10n.filterPendingItemsHint,
                    prefixIcon: Icon(Icons.filter_list_rounded, color: theme.colorScheme.primary, size: 20),
                    suffixIcon: _pendingFilterQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: Colors.grey, size: 18),
                            onPressed: () {
                              _pendingFilterController.clear();
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: theme.cardColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              Material(
                color: theme.cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: theme.dividerColor),
                ),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 120, maxHeight: 280),
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
                      : Scrollbar(
                          child: Listener(
                            onPointerMove: (event) {
                              if (!_isDraggingReorder) return;
                              final screenHeight = MediaQuery.of(context).size.height;
                              final dy = event.position.dy;

                              const edgeThreshold = 160.0;
                              if (dy < edgeThreshold) {
                                final double scrollOffset = (edgeThreshold - dy) / edgeThreshold * 18;
                                if (_scrollController.hasClients) {
                                  final newOffset = (_scrollController.offset - scrollOffset).clamp(
                                    0.0,
                                    _scrollController.position.maxScrollExtent,
                                  );
                                  _scrollController.jumpTo(newOffset);
                                }
                              } else if (dy > screenHeight - edgeThreshold) {
                                final double scrollOffset = (dy - (screenHeight - edgeThreshold)) / edgeThreshold * 18;
                                if (_scrollController.hasClients) {
                                  final newOffset = (_scrollController.offset + scrollOffset).clamp(
                                    0.0,
                                    _scrollController.position.maxScrollExtent,
                                  );
                                  _scrollController.jumpTo(newOffset);
                                }
                              }
                            },
                            onPointerUp: (_) {
                              _isDraggingReorder = false;
                            },
                            onPointerCancel: (_) {
                              _isDraggingReorder = false;
                            },
                            child: ReorderableListView.builder(
                              shrinkWrap: true,
                              physics: const ClampingScrollPhysics(),
                              buildDefaultDragHandles: _pendingSortOption == PendingItemsSortOption.manual && _pendingFilterQuery.isEmpty,
                              itemCount: pendingItems.length,
                              onReorderStart: (index) {
                                _isDraggingReorder = true;
                                _stopSyncTimer();
                              },
                              onReorder: (oldIndex, newIndex) {
                                if (_pendingSortOption != PendingItemsSortOption.manual || _pendingFilterQuery.isNotEmpty) {
                                  return;
                                }
                                _isDraggingReorder = false;
                                if (newIndex > oldIndex) {
                                  newIndex -= 1;
                                }
                                _runWithPausedSyncTimer(() async {
                                  await db.reorderPendingItems(
                                    widget.shoppingList.idListaCompra,
                                    oldIndex,
                                    newIndex,
                                  );
                                });
                              },
                          itemBuilder: (context, index) {
                            final item = pendingItems[index];
                            return Column(
                              key: Key(item.idDetalle),
                              children: [
                                if (index > 0) const Divider(height: 1),
                                Dismissible(
                                  key: Key("dismiss_${item.idDetalle}"),
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
                                    _runWithPausedSyncTimer(() async {
                                      if (direction == DismissDirection.startToEnd) {
                                        await db.markItemAsCompleted(item.idDetalle);
                                      } else if (direction == DismissDirection.endToStart) {
                                        await db.removeListDetailItem(item.idDetalle);
                                      }
                                    });
                                  },
                                  child: PendingItemTile(
                                    item: item,
                                    onSaveNote: (newNote) {
                                      _runWithPausedSyncTimer(() async {
                                        await db.updateItemDetailNote(item.idDetalle, newNote);
                                      });
                                    },
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
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
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    _addCustomItem(value);
                  }
                },
                decoration: InputDecoration(
                  hintText: l10n.searchOrTypeItemHint,
                  prefixIcon: Icon(Icons.search_rounded, color: theme.colorScheme.primary),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: theme.cardColor,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Material(
                color: Colors.amber.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  height: 220,
                  child: Column(
                    children: [
                      // Opción dinámica de agregar artículo personalizado cuando el usuario escribe algo no coincidente
                      if (_searchQuery.isNotEmpty && !hasExactMatch)
                        Material(
                          color: Colors.transparent,
                          child: ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            tileColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                            leading: CircleAvatar(
                              backgroundColor: theme.colorScheme.primary,
                              radius: 14,
                              child: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                            ),
                            title: Text(
                              l10n.addQueryToListOption(_searchQuery),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            subtitle: Text(
                              l10n.addQueryToListSubtitle,
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                            onTap: () => _addCustomItem(_searchQuery),
                          ),
                        ),

                      if (filteredCatalog.isEmpty && (_searchQuery.isEmpty || hasExactMatch))
                        Expanded(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(l10n.noCatalogItemsFound),
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: Scrollbar(
                            child: ListView.separated(
                              physics: const BouncingScrollPhysics(),
                              itemCount: filteredCatalog.length,
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final catItem = filteredCatalog[index];
                                final name = catItem.getLocalizedName(currentLang);

                                return Material(
                                  color: Colors.transparent,
                                  child: ListTile(
                                    dense: true,
                                    onLongPress: () => _showEditCatalogItemDialog(catItem),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                                            softWrap: true,
                                          ),
                                        ),
                                        if (catItem.nuUso > 0) ...[
                                          const SizedBox(width: 6),
                                          const Icon(Icons.local_fire_department_rounded, color: Colors.orange, size: 16),
                                        ],
                                      ],
                                    ),
                                    trailing: const Icon(Icons.add_rounded, color: Colors.blue),
                                    onTap: () {
                                      _runWithPausedSyncTimer(() async {
                                        final added = await db.addItemToList(
                                          idListaCompra: widget.shoppingList.idListaCompra,
                                          idArticulo: catItem.idArticulo,
                                          nbArticulo: name,
                                        );

                                        if (!added && context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(l10n.itemAlreadyInList(name)),
                                              backgroundColor: Colors.orange[800],
                                              duration: const Duration(seconds: 2),
                                            ),
                                          );
                                        }

                                        _searchController.clear();
                                        FocusManager.instance.primaryFocus?.unfocus();
                                      });
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
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
                Material(
                  color: Colors.green.withValues(alpha: 0.04),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.green.withValues(alpha: 0.2)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: Scrollbar(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: completedItems.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = completedItems[index];
                          final addedByName = db.getUserDisplayName(item.idUsuarioAgrego);
                          final hasNote = item.dsDetalle != null && item.dsDetalle!.trim().isNotEmpty;
                          return Material(
                            color: Colors.transparent,
                            child: ListTile(
                              dense: true,
                              leading: const Icon(Icons.check_box_rounded, color: Colors.green),
                              title: Text(
                                item.nbArticulo,
                                style: TextStyle(
                                  decoration: TextDecoration.lineThrough,
                                  color: Colors.grey[700],
                                ),
                              ),
                              subtitle: (hasNote || addedByName.isNotEmpty)
                                  ? Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (hasNote)
                                          Text(
                                            item.dsDetalle!,
                                            style: TextStyle(
                                              decoration: TextDecoration.lineThrough,
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        if (addedByName.isNotEmpty)
                                          Align(
                                            alignment: Alignment.bottomRight,
                                            child: Text(
                                              l10n.addedBy(addedByName),
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontStyle: FontStyle.italic,
                                                color: Colors.grey[500],
                                              ),
                                            ),
                                          ),
                                      ],
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
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

  void _saveCurrentNote() {
    if (_isEditingNote) {
      _isEditingNote = false;
      widget.onSaveNote(_noteController.text);
    }
  }

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.item.dsDetalle ?? "");
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isEditingNote && mounted) {
        setState(() {
          _saveCurrentNote();
        });
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
    final db = context.watch<DatabaseService>();
    final noteText = widget.item.dsDetalle?.trim() ?? "";
    final addedByName = db.getUserDisplayName(widget.item.idUsuarioAgrego);

    return InkWell(
      onTap: () {
        if (!_isEditingNote) {
          _startEditing();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                          decoration: InputDecoration(
                            hintText: l10n.addDetailHint,
                            hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            filled: true,
                            fillColor: Theme.of(context).cardColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
                            ),
                          ),
                          onSubmitted: (val) {
                            if (_isEditingNote && mounted) {
                              setState(() {
                                _saveCurrentNote();
                              });
                            }
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
                              color: noteText.isNotEmpty ? Theme.of(context).colorScheme.primary : Colors.grey[500],
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
                    SizedBox(width: 6),
                    Icon(Icons.drag_handle_rounded, color: Colors.grey, size: 20),
                  ],
                ),
              ],
            ),
            if (addedByName.isNotEmpty) ...[
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  l10n.addedBy(addedByName),
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
