import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config/mongo_config.dart';
import '../models/item_catalog_model.dart';
import '../models/list_detail_item_model.dart';
import '../models/shopping_list_model.dart';
import 'connectivity_service.dart';
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
  final Set<String> _tombstones = {};
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

  /// Registra una acción local de usuario (DELETE, UPDATE, INSERT) con marca de tiempo y tombstone para evitar resurrecciones
  void recordLocalMutation({
    required String entityId,
    required String action,
  }) {
    if (action == 'DELETE') {
      _tombstones.add(entityId);
    }
    _recentMutations[entityId] = _LocalMutation(
      entityId: entityId,
      action: action,
      timestamp: DateTime.now(),
    );
    // Limpieza defensiva de mutaciones muy antiguas (> 24 horas) para no acumular memoria infinita
    final threshold = DateTime.now().subtract(const Duration(hours: 24));
    _recentMutations.removeWhere((_, m) => m.timestamp.isBefore(threshold));
  }

  /// Limpia la marca de mutación local una vez que se confirma sincronización con MongoDB
  void clearLocalMutation(String entityId) {
    _recentMutations.remove(entityId);
  }

  /// Comprueba si una entidad fue eliminada localmente (garantía anti-resurrección con Tombstone)
  bool isLocallyDeleted(String entityId, {DateTime? since}) {
    if (_tombstones.contains(entityId)) return true;
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

  /// Limpia todo el estado en memoria de mutaciones y tombstones al cerrar o cambiar de sesión
  void resetState() {
    cancelDebounce();
    _recentMutations.clear();
    _tombstones.clear();
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
    if (ConnectivityService().isOffline) {
      debugPrint("[SYNC_SERVICE] Modo offline: posponiendo vaciado de sync_queue hasta reconexión.");
      return;
    }

    if (_isProcessing) {
      if (_syncCompleter != null) {
        await _syncCompleter!.future;
      }
      final remaining = await _localDb.getPendingSyncQueue();
      if (remaining.any((i) => i.retryCount <= 10) && !ConnectivityService().isOffline) {
        return processSyncQueue();
      }
      return;
    }
    _isProcessing = true;
    _syncCompleter = Completer<void>();

    try {
      while (!ConnectivityService().isOffline) {
        final queue = await _localDb.getPendingSyncQueue();
        if (queue.isEmpty) {
          break;
        }

        final validQueue = queue.where((i) => i.retryCount <= 10).toList();
        if (validQueue.isEmpty) break;

        debugPrint("[SYNC_SERVICE] Procesando cola de sincronización (${validQueue.length} elementos pendientes)...");

        // Agrupar elementos por colección para enviarlos en lotes (bulkWrite)
        final Map<String, List<SyncQueueItem>> groupedByCollection = {};
        for (var item in validQueue) {
          groupedByCollection.putIfAbsent(item.collectionName, () => []).add(item);
        }

        bool anyBatchFailed = false;

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
                if (collectionName == MongoConfig.colDetalleLista) {
                  success = await MongoService.updateOne(
                    collectionName: collectionName,
                    filter: {primaryKeyField: item.entityId},
                    update: {
                      '\$set': {'status': 'deleted'},
                    },
                    upsert: false,
                  );
                } else {
                  success = await MongoService.deleteOne(
                    collectionName: collectionName,
                    filter: {primaryKeyField: item.entityId},
                  );
                }
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
              anyBatchFailed = true;
              if (ConnectivityService().isOffline) {
                debugPrint("[SYNC_SERVICE] Pérdida de conexión detectada. Se conserva el ítem #${item.id} en cola sin penalizar reintentos.");
                break;
              }
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
                if (collectionName == MongoConfig.colDetalleLista) {
                  statements.add({
                    'updateOne': {
                      'filter': {primaryKeyField: item.entityId},
                      'update': {
                        '\$set': {'status': 'deleted'},
                      },
                      'upsert': false,
                    }
                  });
                } else {
                  statements.add({
                    'deleteOne': {
                      'filter': {primaryKeyField: item.entityId},
                    }
                  });
                }
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
              anyBatchFailed = true;
              debugPrint("[SYNC_SERVICE] Error enviando lote a Mongo. Se reintentará en el próximo ciclo.");
              if (ConnectivityService().isOffline) {
                debugPrint("[SYNC_SERVICE] Pérdida de conexión detectada. Se conserva el lote en cola sin penalizar reintentos.");
                break;
              }
              for (var item in itemsBatch) {
                if (item.id != null) {
                  await _localDb.updateSyncQueueRetry(item.id!, item.retryCount);
                }
              }
              break;
            }
          }
        }

        if (anyBatchFailed) {
          break;
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
    if (ConnectivityService().isOffline) {
      debugPrint("[SYNC_SERVICE] Dispositivo sin conexión. Omitiendo pullDeltaSync.");
      return false;
    }
    if (_isSyncingDelta) return false;
    _isSyncingDelta = true;

    final pullStartTime = DateTime.now();
    bool hasChanges = false;

    try {
      // 1. Primero vaciar la cola de cambios locales pendientes si los hay
      await processSyncQueue();

      // 2. Descargar listas remotas (si ocurre error de red retorna null y abortamos para proteger caché local)
      final remoteListDocs = await MongoService.findOrNull(
        collectionName: MongoConfig.colListasCompra,
        filter: {'id_familia': famId},
      );
      if (remoteListDocs == null) {
        debugPrint("[SYNC_SERVICE] Fallo de red al consultar listas en pullDeltaSync. Abortando sin alterar SQLite.");
        return false;
      }
      final remoteLists = remoteListDocs.map((doc) => ShoppingListModel.fromMap(doc)).toList();

      // 3. Descargar catálogo de artículos
      final remoteCatalogDocs = await MongoService.findOrNull(
        collectionName: MongoConfig.colCArticulo,
        filter: {'id_familia': famId},
      );
      if (remoteCatalogDocs == null) {
        debugPrint("[SYNC_SERVICE] Fallo de red al consultar catálogo en pullDeltaSync. Abortando sin alterar SQLite.");
        return false;
      }
      final remoteCatalog = remoteCatalogDocs.map((doc) => ItemCatalogModel.fromMap(doc)).toList();

      // 4. Descargar detalles/productos de todas las listas activas
      final localLists = await _localDb.getShoppingLists(famId);
      final allListIds = {
        ...remoteLists.map((l) => l.idListaCompra),
        ...localLists.map((l) => l.idListaCompra),
      }.toList();

      final List<ListDetailItemModel> remoteDetails = [];
      if (allListIds.isNotEmpty) {
        final detailDocs = await MongoService.findOrNull(
          collectionName: MongoConfig.colDetalleLista,
          filter: {
            'id_lista_compra': {'\$in': allListIds},
          },
        );
        if (detailDocs == null) {
          debugPrint("[SYNC_SERVICE] Fallo de red al consultar detalles en pullDeltaSync. Abortando sin alterar SQLite.");
          return false;
        }
        for (var doc in detailDocs) {
          final item = ListDetailItemModel.fromMap(doc);
          remoteDetails.add(item);

          if (doc['fecha_agrego'] == null && item.fechaAgrego != null) {
            unawaited(MongoService.updateOne(
              collectionName: MongoConfig.colDetalleLista,
              filter: {'id_detalle': item.idDetalle},
              update: {
                '\$set': {'fecha_agrego': item.fechaAgrego!.toIso8601String()},
              },
            ));
          }
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
      final Map<String, ShoppingListModel> localListsMap = {for (var l in localLists) l.idListaCompra: l};
      final Map<String, ShoppingListModel> mergedLists = {};

      for (var l in remoteLists) {
        final action = pendingListActions[l.idListaCompra];
        final wasDeletedLocally = action == 'DELETE' || isLocallyDeleted(l.idListaCompra, since: pullStartTime);
        if (wasDeletedLocally) {
          continue; // No revivir lista borrada
        }
        if (action == 'UPDATE' || action == 'INSERT' || isLocallyModified(l.idListaCompra, since: pullStartTime)) {
          final local = localListsMap[l.idListaCompra];
          if (local != null) {
            mergedLists[l.idListaCompra] = local;
            continue;
          }
        }
        mergedLists[l.idListaCompra] = l;
      }

      // Preservar listas creadas o modificadas localmente que aún no han subido a MongoDB
      for (var l in localLists) {
        if (!mergedLists.containsKey(l.idListaCompra)) {
          final action = pendingListActions[l.idListaCompra];
          final wasDeletedLocally = action == 'DELETE' || isLocallyDeleted(l.idListaCompra, since: pullStartTime);
          if (!wasDeletedLocally && (action != null || isLocallyModified(l.idListaCompra, since: pullStartTime))) {
            mergedLists[l.idListaCompra] = l;
          }
        }
      }
      await _localDb.saveShoppingLists(
        mergedLists.values.toList(),
        famId: famId,
        pendingEntityIds: pendingListActions.keys.toSet(),
      );

      // --- MERGE CATÁLOGO ---
      final localCatalog = await _localDb.getCatalogItems(famId);
      final Map<String, ItemCatalogModel> mergedCatalog = {for (var c in localCatalog) c.idArticulo: c};

      for (var c in remoteCatalog) {
        final action = pendingCatalogActions[c.idArticulo];
        final wasDeletedLocally = action == 'DELETE' || isLocallyDeleted(c.idArticulo, since: pullStartTime);
        if (wasDeletedLocally) {
          mergedCatalog.remove(c.idArticulo);
          continue; // No revivir artículo borrado
        }
        if (action == 'UPDATE' || isLocallyModified(c.idArticulo, since: pullStartTime)) {
          final local = mergedCatalog[c.idArticulo];
          if (local != null) {
            continue;
          }
        }
        mergedCatalog[c.idArticulo] = c;
      }
      await _localDb.saveCatalogItems(mergedCatalog.values.toList(), famId: famId);

      // --- MERGE DETALLES DE PRODUCTOS (GRANULAR POR PRODUCTO) ---
      final activeListIds = mergedLists.values.map((l) => l.idListaCompra).toList();
      final localDetails = await _localDb.getAllListDetailsForFamily(activeListIds);
      final Map<String, ListDetailItemModel> localDetailMap = {for (var d in localDetails) d.idDetalle: d};
      final Map<String, ListDetailItemModel> mergedDetails = {};

      for (var d in remoteDetails) {
        if (d.status == 'deleted') {
          debugPrint("[SYNC_SERVICE] Merge: Descartando producto '${d.nbArticulo}' (${d.idDetalle}) con status 'deleted' en Mongo.");
          continue;
        }

        final action = pendingDetailActions[d.idDetalle];
        final wasDeletedLocally = action == 'DELETE' || isLocallyDeleted(d.idDetalle, since: pullStartTime);

        if (wasDeletedLocally) {
          // 👉 EL PRODUCTO FUE BORRADO LOCALMENTE: Ignorar y quitar si existía
          debugPrint("[SYNC_SERVICE] Merge: Descartando producto '${d.nbArticulo}' (${d.idDetalle}) de Mongo porque fue eliminado localmente.");
          continue;
        }

        final wasModifiedLocally = action == 'UPDATE' || action == 'INSERT' || isLocallyModified(d.idDetalle, since: pullStartTime);
        if (wasModifiedLocally) {
          // 👉 EL PRODUCTO FUE MODIFICADO LOCALMENTE: Preservar la versión de SQLite/RAM
          final local = localDetailMap[d.idDetalle];
          if (local != null) {
            mergedDetails[d.idDetalle] = (local.fechaAgrego == null && d.fechaAgrego != null)
                ? local.copyWith(fechaAgrego: d.fechaAgrego)
                : local;
            continue;
          }
        }

        // 👉 PRODUCTO NUEVO O NO TOCADO LOCALMENTE: Aceptar versión remota inmediatamente
        mergedDetails[d.idDetalle] = d;
      }

      // Preservar productos creados o modificados localmente que aún están en cola por subir a MongoDB.
      // Cualquier producto que estaba en SQLite como 'synced' (sin mutación local pendiente) y ya no viene en remoteDetails
      // fue eliminado por otro integrante de la familia y se descarta para que también desaparezca en este dispositivo.
      for (var d in localDetails) {
        if (!mergedDetails.containsKey(d.idDetalle)) {
          final action = pendingDetailActions[d.idDetalle];
          final wasDeletedLocally = action == 'DELETE' || isLocallyDeleted(d.idDetalle, since: pullStartTime);
          if (!wasDeletedLocally && (action != null || isLocallyModified(d.idDetalle, since: pullStartTime))) {
            mergedDetails[d.idDetalle] = d;
          } else {
            debugPrint("[SYNC_SERVICE] Merge: Producto '${d.nbArticulo}' (${d.idDetalle}) eliminado remotamente por otro integrante; removiendo de caché local.");
          }
        }
      }

      await _localDb.saveListDetailItemsBatch(
        mergedDetails.values.toList(),
        activeListIds: activeListIds,
        pendingEntityIds: pendingDetailActions.keys.toSet(),
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
