import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config/mongo_config.dart';
import '../models/item_catalog_model.dart';
import '../models/list_detail_item_model.dart';
import '../models/shopping_list_model.dart';
import 'local_db_service.dart';
import 'mongo_service.dart';

class _LocalMutation {
  final String entityId;
  final String action; // 'DELETE', 'UPDATE', 'INSERT'
  final DateTime timestamp;

  _LocalMutation({
    required this.entityId,
    required this.action,
    required this.timestamp,
  });
}

class SyncService {
  static SyncService? _instance;
  final LocalDbService _localDb = LocalDbService();
  final Map<String, _LocalMutation> _recentMutations = {};
  Timer? _debounceTimer;
  bool _isProcessing = false;
  bool _isSyncingDelta = false;
  Completer<void>? _syncCompleter;

  bool get isSyncing => _isProcessing || _isSyncingDelta;

  SyncService._internal();

  factory SyncService() {
    _instance ??= SyncService._internal();
    return _instance!;
  }

  /// Registra una acción local de usuario (DELETE, UPDATE, INSERT) con marca de tiempo para evitar resurrecciones
  void recordLocalMutation({
    required String entityId,
    required String action,
  }) {
    _recentMutations[entityId] = _LocalMutation(
      entityId: entityId,
      action: action,
      timestamp: DateTime.now(),
    );
    // Limpieza de entradas con más de 60 segundos
    final threshold = DateTime.now().subtract(const Duration(seconds: 60));
    _recentMutations.removeWhere((_, m) => m.timestamp.isBefore(threshold));
  }

  /// Limpia la marca de mutación local una vez que se confirma sincronización
  void clearLocalMutation(String entityId) {
    _recentMutations.remove(entityId);
  }

  /// Comprueba si una entidad fue eliminada localmente
  bool isLocallyDeleted(String entityId, {DateTime? since}) {
    final m = _recentMutations[entityId];
    if (m == null) return false;
    if (m.action != 'DELETE') return false;
    if (since != null && m.timestamp.isBefore(since)) return false;
    return true;
  }

  /// Comprueba si una entidad fue modificada localmente (UPDATE, INSERT o DELETE)
  bool isLocallyModified(String entityId, {DateTime? since}) {
    final m = _recentMutations[entityId];
    if (m == null) return false;
    if (since != null && m.timestamp.isBefore(since)) return false;
    return true;
  }

  /// Cancela el temporizador de debounce si existe
  void cancelDebounce() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  /// Dispara la sincronización inmediata sin debounce y espera a que el envío a backend termine
  Future<void> syncNow() async {
    cancelDebounce();
    await processSyncQueue();
  }

  /// Dispara el procesamiento de la cola de sincronización con un pequeño debounce
  void triggerSync({Duration delay = const Duration(milliseconds: 500)}) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () {
      processSyncQueue();
    });
  }

  /// Procesa en lotes (bulkWrite) todos los elementos pendientes en sync_queue enviándolos a MongoDB Atlas en 1 sola llamada de red por lote
  Future<void> processSyncQueue() async {
    if (_isProcessing) {
      if (_syncCompleter != null) {
        await _syncCompleter!.future;
      }
      final remaining = await _localDb.getPendingSyncQueue();
      if (remaining.isNotEmpty) {
        return processSyncQueue();
      }
      return;
    }
    _isProcessing = true;
    _syncCompleter = Completer<void>();

    try {
      final queue = await _localDb.getPendingSyncQueue();
      if (queue.isEmpty) {
        return;
      }

      final validQueue = queue.where((i) => i.retryCount <= 10).toList();
      if (validQueue.isEmpty) return;

      debugPrint("[SYNC_SERVICE] Procesando cola de sincronización (${validQueue.length} elementos pendientes)...");

      // Agrupar elementos por colección para enviarlos en lotes (bulkWrite)
      final Map<String, List<SyncQueueItem>> groupedByCollection = {};
      for (var item in validQueue) {
        groupedByCollection.putIfAbsent(item.collectionName, () => []).add(item);
      }

      for (var entry in groupedByCollection.entries) {
        final collectionName = entry.key;
        final itemsBatch = entry.value;
        final primaryKeyField = _getPrimaryKeyField(collectionName);

        if (itemsBatch.length == 1) {
          final item = itemsBatch.first;
          bool success = false;
          try {
            if (item.action == 'INSERT' || item.action == 'UPDATE') {
              success = await MongoService.updateOne(
                collectionName: collectionName,
                filter: {primaryKeyField: item.entityId},
                update: {'\$set': item.payload},
                upsert: true,
              );
            } else if (item.action == 'DELETE') {
              success = await MongoService.deleteOne(
                collectionName: collectionName,
                filter: {primaryKeyField: item.entityId},
              );
            }
          } catch (e) {
            debugPrint("[SYNC_SERVICE] Error procesando #${item.id}: $e");
            success = false;
          }

          if (success) {
            if (item.id != null) {
              await _localDb.removeSyncQueueItem(item.id!);
            }
            clearLocalMutation(item.entityId);
            debugPrint("[SYNC_SERVICE] ¡Elemento #${item.id} sincronizado exitosamente con MongoDB Atlas!");
          } else {
            if (item.id != null) {
              await _localDb.updateSyncQueueRetry(item.id!, item.retryCount);
            }
            break;
          }
        } else {
          // LOTE DE MÚLTIPLES ELEMENTOS (bulkWrite) en 1 sola llamada de red
          debugPrint("[SYNC_SERVICE] Sincronizando LOTE de ${itemsBatch.length} elementos en '$collectionName' con MongoDB Atlas en 1 sola llamada...");

          final List<Map<String, Object>> statements = [];
          final List<int> processedIds = [];

          for (var item in itemsBatch) {
            if (item.id != null) processedIds.add(item.id!);
            if (item.action == 'INSERT' || item.action == 'UPDATE') {
              statements.add({
                'updateOne': {
                  'filter': {primaryKeyField: item.entityId},
                  'update': {'\$set': item.payload},
                  'upsert': true,
                }
              });
            } else if (item.action == 'DELETE') {
              statements.add({
                'deleteOne': {
                  'filter': {primaryKeyField: item.entityId},
                }
              });
            }
          }

          bool success = false;
          try {
            success = await MongoService.bulkWrite(
              collectionName: collectionName,
              statements: statements,
            );
          } catch (e) {
            debugPrint("[SYNC_SERVICE] Error en lote bulkWrite para $collectionName: $e");
            success = false;
          }

          if (success) {
            await _localDb.removeSyncQueueItemsBatch(processedIds);
            for (var item in itemsBatch) {
              clearLocalMutation(item.entityId);
            }
            debugPrint("[SYNC_SERVICE] ¡LOTE de ${itemsBatch.length} elementos (#${processedIds.first}-#${processedIds.last}) sincronizado exitosamente en MongoDB Atlas en 1 sola petición!");
          } else {
            debugPrint("[SYNC_SERVICE] Error enviando lote a Mongo. Se reintentará en el próximo ciclo.");
            for (var item in itemsBatch) {
              if (item.id != null) {
                await _localDb.updateSyncQueueRetry(item.id!, item.retryCount);
              }
            }
            break;
          }
        }
      }
    } catch (e) {
      debugPrint("[SYNC_SERVICE] Error general en processSyncQueue: $e");
    } finally {
      _isProcessing = false;
      if (_syncCompleter != null && !_syncCompleter!.isCompleted) {
        _syncCompleter!.complete();
      }
      _syncCompleter = null;
    }
  }

  String _getPrimaryKeyField(String collectionName) {
    if (collectionName == MongoConfig.colListasCompra) return 'id_lista_compra';
    if (collectionName == MongoConfig.colDetalleLista) return 'id_detalle';
    if (collectionName == MongoConfig.colCArticulo) return 'id_articulo';
    if (collectionName == MongoConfig.colFamilia) return 'id_familia';
    if (collectionName == MongoConfig.colUsuario) return 'id_usuario';
    return 'id';
  }

  /// Ejecuta sincronización delta en segundo plano descargando cambios de Mongo y fusionando defensivamente con SQLite
  Future<bool> pullDeltaSync({required String famId, required Function onDataUpdated}) async {
    if (famId.isEmpty) return false;
    if (_isSyncingDelta) return false;
    _isSyncingDelta = true;

    final pullStartTime = DateTime.now();
    bool hasChanges = false;

    try {
      // 1. Primero vaciar la cola de cambios locales pendientes si los hay
      await processSyncQueue();

      // 2. Descargar listas remotas
      final remoteListDocs = await MongoService.find(
        collectionName: MongoConfig.colListasCompra,
        filter: {'id_familia': famId},
      );
      final remoteLists = remoteListDocs.map((doc) => ShoppingListModel.fromMap(doc)).toList();

      // 3. Descargar catálogo de artículos
      final remoteCatalogDocs = await MongoService.find(
        collectionName: MongoConfig.colCArticulo,
        filter: {'id_familia': famId},
      );
      final remoteCatalog = remoteCatalogDocs.map((doc) => ItemCatalogModel.fromMap(doc)).toList();

      // 4. Descargar detalles/productos de todas las listas activas
      final localLists = await _localDb.getShoppingLists(famId);
      final allListIds = {
        ...remoteLists.map((l) => l.idListaCompra),
        ...localLists.map((l) => l.idListaCompra),
      }.toList();

      final List<ListDetailItemModel> remoteDetails = [];
      for (var listId in allListIds) {
        final detailDocs = await MongoService.find(
          collectionName: MongoConfig.colDetalleLista,
          filter: {'id_lista_compra': listId},
        );
        for (var doc in detailDocs) {
          remoteDetails.add(ListDetailItemModel.fromMap(doc));
        }
      }

      // =========================================================================
      // MERGE GRANULAR Y DEFENSIVO JUSTO ANTES DE GUARDAR EN SQLITE
      // =========================================================================

      // Consultamos la cola de sincronización ACTUAL (incluyendo mutaciones locales ocurridas durante el fetch de red)
      final pendingListActions = await _localDb.getPendingSyncActions(MongoConfig.colListasCompra);
      final pendingCatalogActions = await _localDb.getPendingSyncActions(MongoConfig.colCArticulo);
      final pendingDetailActions = await _localDb.getPendingSyncActions(MongoConfig.colDetalleLista);

      // --- MERGE LISTAS ---
      final Map<String, ShoppingListModel> mergedLists = {};
      final Map<String, ShoppingListModel> localListsMap = {for (var l in localLists) l.idListaCompra: l};

      for (var l in remoteLists) {
        final action = pendingListActions[l.idListaCompra];
        final wasDeletedLocally = action == 'DELETE' || isLocallyDeleted(l.idListaCompra, since: pullStartTime);
        if (wasDeletedLocally) {
          continue; // No revivir lista borrada
        }
        if (action == 'UPDATE' || isLocallyModified(l.idListaCompra, since: pullStartTime)) {
          final local = localListsMap[l.idListaCompra];
          if (local != null) {
            mergedLists[l.idListaCompra] = local;
            continue;
          }
        }
        mergedLists[l.idListaCompra] = l;
      }
      for (var l in localLists) {
        final action = pendingListActions[l.idListaCompra];
        if (action != null && action != 'DELETE' && !mergedLists.containsKey(l.idListaCompra)) {
          mergedLists[l.idListaCompra] = l;
        }
      }
      await _localDb.saveShoppingLists(mergedLists.values.toList(), famId: famId);

      // --- MERGE CATÁLOGO ---
      final localCatalog = await _localDb.getCatalogItems(famId);
      final Map<String, ItemCatalogModel> mergedCatalog = {};
      final Map<String, ItemCatalogModel> localCatalogMap = {for (var c in localCatalog) c.idArticulo: c};

      for (var c in remoteCatalog) {
        final action = pendingCatalogActions[c.idArticulo];
        final wasDeletedLocally = action == 'DELETE' || isLocallyDeleted(c.idArticulo, since: pullStartTime);
        if (wasDeletedLocally) {
          continue; // No revivir artículo borrado
        }
        if (action == 'UPDATE' || isLocallyModified(c.idArticulo, since: pullStartTime)) {
          final local = localCatalogMap[c.idArticulo];
          if (local != null) {
            mergedCatalog[c.idArticulo] = local;
            continue;
          }
        }
        mergedCatalog[c.idArticulo] = c;
      }
      for (var c in localCatalog) {
        final action = pendingCatalogActions[c.idArticulo];
        if (action != null && action != 'DELETE' && !mergedCatalog.containsKey(c.idArticulo)) {
          mergedCatalog[c.idArticulo] = c;
        }
      }
      await _localDb.saveCatalogItems(mergedCatalog.values.toList(), famId: famId);

      // --- MERGE DETALLES DE PRODUCTOS (GRANULAR POR PRODUCTO) ---
      final activeListIds = mergedLists.values.map((l) => l.idListaCompra).toList();
      final localDetails = await _localDb.getAllListDetailsForFamily(activeListIds);
      final Map<String, ListDetailItemModel> localDetailMap = {for (var d in localDetails) d.idDetalle: d};
      final Map<String, ListDetailItemModel> mergedDetails = {};

      for (var d in remoteDetails) {
        final action = pendingDetailActions[d.idDetalle];
        final wasDeletedLocally = action == 'DELETE' || isLocallyDeleted(d.idDetalle, since: pullStartTime);

        if (wasDeletedLocally) {
          // 👉 EL PRODUCTO FUE BORRADO LOCALMENTE: Ignorar la respuesta vieja de Mongo
          debugPrint("[SYNC_SERVICE] Merge: Descartando producto '${d.nbArticulo}' (${d.idDetalle}) de Mongo porque fue eliminado localmente.");
          continue;
        }

        final wasModifiedLocally = action == 'UPDATE' || isLocallyModified(d.idDetalle, since: pullStartTime);
        if (wasModifiedLocally) {
          // 👉 EL PRODUCTO FUE MODIFICADO LOCALMENTE: Preservar la versión de SQLite/RAM
          final local = localDetailMap[d.idDetalle];
          if (local != null) {
            mergedDetails[d.idDetalle] = local;
            continue;
          }
        }

        // 👉 PRODUCTO NUEVO O NO TOCADO LOCALMENTE: Aceptar versión remota inmediatamente
        mergedDetails[d.idDetalle] = d;
      }

      // Preservar ítems nuevos creados localmente que aún están pendientes de subir a Mongo
      for (var d in localDetails) {
        final action = pendingDetailActions[d.idDetalle];
        final wasDeletedLocally = action == 'DELETE' || isLocallyDeleted(d.idDetalle, since: pullStartTime);
        if (!wasDeletedLocally && (action != null || isLocallyModified(d.idDetalle, since: pullStartTime)) && !mergedDetails.containsKey(d.idDetalle)) {
          mergedDetails[d.idDetalle] = d;
        }
      }

      await _localDb.saveListDetailItemsBatch(
        mergedDetails.values.toList(),
        activeListIds: activeListIds,
      );

      hasChanges = true;
      onDataUpdated();
      debugPrint("[SYNC_SERVICE] Sincronización delta completada exitosamente con Merge Granular.");
    } catch (e) {
      debugPrint("[SYNC_SERVICE] Error en pullDeltaSync: $e");
    } finally {
      _isSyncingDelta = false;
    }

    return hasChanges;
  }
}
