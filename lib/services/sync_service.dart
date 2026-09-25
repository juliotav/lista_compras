import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config/mongo_config.dart';
import '../models/item_catalog_model.dart';
import '../models/list_detail_item_model.dart';
import '../models/shopping_list_model.dart';
import 'local_db_service.dart';
import 'mongo_service.dart';

class SyncService {
  static SyncService? _instance;
  final LocalDbService _localDb = LocalDbService();
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

  /// Ejecuta sincronización delta en segundo plano descargando cambios de Mongo y fusionando con SQLite
  Future<bool> pullDeltaSync({required String famId, required Function onDataUpdated}) async {
    if (famId.isEmpty) return false;
    if (_isSyncingDelta) return false;
    _isSyncingDelta = true;

    bool hasChanges = false;

    try {
      // 1. Primero vaciar la cola de cambios locales pendientes si los hay
      await processSyncQueue();

      // Obtenemos los IDs de entidades con cambios pendientes locales para no sobrescribirlos
      final pendingListIds = await _localDb.getPendingEntityIds(MongoConfig.colListasCompra);
      final pendingDetailIds = await _localDb.getPendingEntityIds(MongoConfig.colDetalleLista);
      final pendingCatalogIds = await _localDb.getPendingEntityIds(MongoConfig.colCArticulo);

      // 2. Descargar listas remotas
      final remoteListDocs = await MongoService.find(
        collectionName: MongoConfig.colListasCompra,
        filter: {'id_familia': famId},
      );
      final remoteLists = remoteListDocs.map((doc) => ShoppingListModel.fromMap(doc)).toList();

      final localLists = await _localDb.getShoppingLists(famId);
      final Map<String, ShoppingListModel> mergedLists = {};

      for (var l in remoteLists) {
        if (!pendingListIds.contains(l.idListaCompra)) {
          mergedLists[l.idListaCompra] = l;
        }
      }
      for (var l in localLists) {
        if (pendingListIds.contains(l.idListaCompra)) {
          mergedLists[l.idListaCompra] = l;
        }
      }

      await _localDb.saveShoppingLists(mergedLists.values.toList(), famId: famId);

      // 3. Descargar catálogo de artículos
      final remoteCatalogDocs = await MongoService.find(
        collectionName: MongoConfig.colCArticulo,
        filter: {'id_familia': famId},
      );
      final remoteCatalog = remoteCatalogDocs.map((doc) => ItemCatalogModel.fromMap(doc)).toList();
      final localCatalog = await _localDb.getCatalogItems(famId);
      final Map<String, ItemCatalogModel> mergedCatalog = {};

      for (var c in remoteCatalog) {
        if (!pendingCatalogIds.contains(c.idArticulo)) {
          mergedCatalog[c.idArticulo] = c;
        }
      }
      for (var c in localCatalog) {
        if (pendingCatalogIds.contains(c.idArticulo)) {
          mergedCatalog[c.idArticulo] = c;
        }
      }
      await _localDb.saveCatalogItems(mergedCatalog.values.toList(), famId: famId);

      // 4. Descargar detalles/productos de todas las listas activas
      final activeListIds = mergedLists.values.map((l) => l.idListaCompra).toList();
      final List<ListDetailItemModel> remoteDetails = [];

      for (var listId in activeListIds) {
        final detailDocs = await MongoService.find(
          collectionName: MongoConfig.colDetalleLista,
          filter: {'id_lista_compra': listId},
        );
        for (var doc in detailDocs) {
          remoteDetails.add(ListDetailItemModel.fromMap(doc));
        }
      }

      final localDetails = await _localDb.getAllListDetailsForFamily(activeListIds);
      final Map<String, ListDetailItemModel> mergedDetails = {};
      final Map<String, ListDetailItemModel> localMap = {};
      for (var d in localDetails) {
        localMap[d.idDetalle] = d;
      }

      for (var d in remoteDetails) {
        if (pendingDetailIds.contains(d.idDetalle)) {
          final localItem = localMap[d.idDetalle];
          if (localItem != null) {
            mergedDetails[d.idDetalle] = localItem;
          }
        } else {
          mergedDetails[d.idDetalle] = d;
        }
      }

      // Preservar ítems totalmente NUEVOS creados localmente que aún no existen en el servidor
      for (var d in localDetails) {
        if (pendingDetailIds.contains(d.idDetalle) && !mergedDetails.containsKey(d.idDetalle)) {
          mergedDetails[d.idDetalle] = d;
        }
      }

      await _localDb.saveListDetailItemsBatch(
        mergedDetails.values.toList(),
        activeListIds: activeListIds,
      );

      hasChanges = true;
      onDataUpdated();
      debugPrint("[SYNC_SERVICE] Sincronización delta completada exitosamente.");
    } catch (e) {
      debugPrint("[SYNC_SERVICE] Error en pullDeltaSync: $e");
    } finally {
      _isSyncingDelta = false;
    }

    return hasChanges;
  }
}
