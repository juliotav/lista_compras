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

  SyncService._internal();

  factory SyncService() {
    _instance ??= SyncService._internal();
    return _instance!;
  }

  /// Dispara el procesamiento de la cola de sincronización con un pequeño debounce
  void triggerSync({Duration delay = const Duration(milliseconds: 500)}) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () {
      processSyncQueue();
    });
  }

  /// Procesa secuencialmente todos los elementos pendientes en sync_queue enviándolos a MongoDB Atlas
  Future<void> processSyncQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final queue = await _localDb.getPendingSyncQueue();
      if (queue.isEmpty) {
        _isProcessing = false;
        return;
      }

      debugPrint("[SYNC_SERVICE] Procesando cola de sincronización (${queue.length} elementos)...");

      for (var item in queue) {
        if (item.retryCount > 10) {
          debugPrint("[SYNC_SERVICE] Elemento #${item.id} superó el límite de reintentos (10). Omitiendo temporalmente.");
          continue;
        }

        bool success = false;

        try {
          if (item.action == 'INSERT') {
            success = await MongoService.insertOne(
              collectionName: item.collectionName,
              document: item.payload,
            );
          } else if (item.action == 'UPDATE') {
            final String primaryKeyField = _getPrimaryKeyField(item.collectionName);
            final filter = {primaryKeyField: item.entityId};
            success = await MongoService.updateOne(
              collectionName: item.collectionName,
              filter: filter,
              update: {'\$set': item.payload},
            );
          } else if (item.action == 'DELETE') {
            final String primaryKeyField = _getPrimaryKeyField(item.collectionName);
            final filter = {primaryKeyField: item.entityId};
            success = await MongoService.deleteOne(
              collectionName: item.collectionName,
              filter: filter,
            );
          }
        } catch (e) {
          debugPrint("[SYNC_SERVICE] Error procesando #${item.id} (${item.action} en ${item.collectionName}): $e");
          success = false;
        }

        if (success) {
          debugPrint("[SYNC_SERVICE] ¡Elemento #${item.id} sincronizado exitosamente con MongoDB Atlas!");
          if (item.id != null) {
            await _localDb.removeSyncQueueItem(item.id!);
          }
        } else {
          debugPrint("[SYNC_SERVICE] Error enviando #${item.id} a MongoDB Atlas. Se reintentará en el próximo ciclo.");
          if (item.id != null) {
            await _localDb.updateSyncQueueRetry(item.id!, item.retryCount);
          }
          // Si falla la conexión a MongoDB, detener el ciclo por ahora para no saturar
          break;
        }
      }
    } catch (e) {
      debugPrint("[SYNC_SERVICE] Error general en processSyncQueue: $e");
    } finally {
      _isProcessing = false;
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

      for (var d in remoteDetails) {
        if (!pendingDetailIds.contains(d.idDetalle)) {
          mergedDetails[d.idDetalle] = d;
        }
      }
      // FUSIÓN ATÓMICA: Preservar los productos que el usuario agregó o modificó localmente
      for (var d in localDetails) {
        if (pendingDetailIds.contains(d.idDetalle)) {
          mergedDetails[d.idDetalle] = d;
        }
      }

      await _localDb.saveListDetailItemsBatch(mergedDetails.values.toList());

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
