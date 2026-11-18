import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lista_compras/models/list_detail_item_model.dart';
import 'package:lista_compras/models/shopping_list_model.dart';
import 'package:lista_compras/models/user_model.dart';
import 'package:lista_compras/services/connectivity_service.dart';
import 'package:lista_compras/services/database_service.dart';
import 'package:lista_compras/services/local_db_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  SharedPreferences.setMockInitialValues({});

  group('ConnectivityService Tests', () {
    test('ConnectivityService singleton instance and initial state', () {
      final service1 = ConnectivityService();
      final service2 = ConnectivityService();
      expect(identical(service1, service2), isTrue);
      expect(service1.isOnline, isNotNull);
      expect(service1.isOffline, equals(!service1.isOnline));
    });

    test('ConnectivityService listener notification', () {
      final service = ConnectivityService();
      bool listenerCalled = false;
      void listener() {
        listenerCalled = true;
      }

      service.addListener(listener);
      // Reporting network failure triggers active check
      service.reportNetworkFailure();
      service.removeListener(listener);
      expect(listenerCalled, isA<bool>());
    });
  });

  group('Offline Cache Warm-Up Flag Tests', () {
    test('isOfflineCacheWarmUpDone returns false initially and true once sealed', () async {
      SharedPreferences.setMockInitialValues({});
      final localDb = LocalDbService();
      const testUserId = "usr_test_123";

      final initial = await localDb.isOfflineCacheWarmUpDone(testUserId);
      expect(initial, isFalse);

      await localDb.setOfflineCacheWarmUpDone(testUserId, done: true);
      final afterWarmUp = await localDb.isOfflineCacheWarmUpDone(testUserId);
      expect(afterWarmUp, isTrue);
    });

    test('saveListDetailItemsBatch removes remotely deleted synced items including when list becomes empty', () async {
      final localDb = LocalDbService();
      await localDb.clearAllData();

      const listId = 'list_sync_del_test';
      final item1 = ListDetailItemModel(
        idDetalle: 'det_1',
        idListaCompra: listId,
        idArticulo: 'art_1',
        nbArticulo: 'Leche',
        status: 'pending',
      );
      final item2 = ListDetailItemModel(
        idDetalle: 'det_2',
        idListaCompra: listId,
        idArticulo: 'art_2',
        nbArticulo: 'Pan',
        status: 'pending',
      );

      // Inicialmente ambos productos están sincronizados localmente
      await localDb.saveListDetailItemsBatch(
        [item1, item2],
        activeListIds: [listId],
      );
      var stored = await localDb.getAllListDetailsForFamily([listId]);
      expect(stored.length, equals(2));

      // Otro miembro de la familia elimina 'Leche' (det_1) en otro dispositivo -> solo queda item2
      await localDb.saveListDetailItemsBatch(
        [item2],
        activeListIds: [listId],
      );
      stored = await localDb.getAllListDetailsForFamily([listId]);
      expect(stored.length, equals(1));
      expect(stored.first.idDetalle, equals('det_2'));

      // El otro miembro elimina el último artículo 'Pan' (det_2) -> lista queda vacía ([])
      await localDb.saveListDetailItemsBatch(
        [],
        activeListIds: [listId],
      );
      stored = await localDb.getAllListDetailsForFamily([listId]);
      expect(stored, isEmpty);
    });

    test('clearAllData and purgeDataOutsideFamilies remove previous user lists and families', () async {
      final localDb = LocalDbService();
      await localDb.clearAllData();

      await localDb.setOfflineCacheWarmUpDone('usr_prev', done: true);
      expect(await localDb.isOfflineCacheWarmUpDone('usr_prev'), isTrue);

      await localDb.clearAllData();
      expect(await localDb.isOfflineCacheWarmUpDone('usr_prev'), isFalse);
      expect(await localDb.getFamilies(), isEmpty);
    });

    test('restoreAllCompletedItems moves all purchased items back to pending in memory and SQLite', () async {
      final localDb = LocalDbService();
      await localDb.clearAllData();

      const famId = 'fam_restore_test';
      const listId = 'list_restore_test';
      const userId = 'usr_restore_test';

      await localDb.saveUser(
        UserModel(
          idUsuario: userId,
          nbCompleto: 'Test User',
          nbEmail: 'test@restore.com',
          clPass: 'hash',
          idFamilia: famId,
        ),
      );
      await localDb.saveSessionUserId(userId);
      await localDb.saveShoppingList(
        ShoppingListModel(
          idListaCompra: listId,
          idFamilia: famId,
          nbLista: 'Super',
          isDefault: true,
          isActive: true,
          isCompleted: false,
        ),
      );

      final pendingItem = ListDetailItemModel(
        idDetalle: 'det_p1',
        idListaCompra: listId,
        idArticulo: 'art_1',
        nbArticulo: 'Leche',
        status: 'pending',
        nuOrder: 0,
      );
      final completed1 = ListDetailItemModel(
        idDetalle: 'det_c1',
        idListaCompra: listId,
        idArticulo: 'art_2',
        nbArticulo: 'Pan',
        dsDetalle: 'Integral',
        status: 'completed',
        fechaCompra: DateTime.now(),
        idUsuarioFinalizo: userId,
      );
      final completed2 = ListDetailItemModel(
        idDetalle: 'det_c2',
        idListaCompra: listId,
        idArticulo: 'art_3',
        nbArticulo: 'Huevos',
        status: 'completed',
        fechaCompra: DateTime.now(),
        idUsuarioFinalizo: userId,
      );

      await localDb.saveListDetailItemsBatch([
        pendingItem,
        completed1,
        completed2,
      ]);

      final dbService = DatabaseService();
      await dbService.initSession();

      expect(dbService.getPendingItems(listId).length, equals(1));
      expect(dbService.getPendingItemsCount(listId), equals(1));
      expect(dbService.getCompletedItems(listId).length, equals(2));

      final restoredCount = await dbService.restoreAllCompletedItems(listId);
      expect(restoredCount, equals(2));
      expect(dbService.getCompletedItems(listId), isEmpty);
      expect(dbService.getPendingItemsCount(listId), equals(3));

      final pendingAfter = dbService.getPendingItems(listId);
      expect(pendingAfter.length, equals(3));
      expect(
        pendingAfter.map((e) => e.nbArticulo).toList(),
        equals(['Leche', 'Pan', 'Huevos']),
      );
      expect(pendingAfter[1].dsDetalle, equals('Integral'));
      expect(pendingAfter[1].fechaCompra, isNull);
      expect(pendingAfter[1].idUsuarioFinalizo, isNull);

      final storedInSqlite = await localDb.getListDetails(listId);
      expect(storedInSqlite.every((i) => i.isPending), isTrue);

      // Marcar dos como comprados y luego limpiar físicamente los comprados
      await dbService.markItemAsCompleted('det_c1');
      await dbService.markItemAsCompleted('det_c2');
      expect(dbService.getCompletedItems(listId).length, equals(2));

      final clearedCount = await dbService.clearAllCompletedItems(listId);
      expect(clearedCount, equals(2));
      expect(dbService.getCompletedItems(listId), isEmpty);
      expect(dbService.getPendingItems(listId).length, equals(1));

      final storedAfterClear = await localDb.getListDetails(listId);
      expect(storedAfterClear.length, equals(1));
      expect(storedAfterClear.first.idDetalle, equals('det_p1'));
    });
  });
}
