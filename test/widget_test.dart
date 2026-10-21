import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lista_compras/services/security_service.dart';
import 'package:lista_compras/services/database_service.dart';
import 'package:lista_compras/utils/undo_helper.dart';
import 'package:uuid/uuid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  SharedPreferences.setMockInitialValues({});

  const uuid = Uuid();

  group('SecurityService Tests', () {
    test('Password security evaluation', () {
      final weak = SecurityService.evaluatePassword('12345');
      expect(weak.isValid, isFalse);

      final strong = SecurityService.evaluatePassword('Pass123!@#');
      expect(strong.isValid, isTrue);
    });

    test('Password hashing produces consistent SHA-256 hash', () {
      final hash1 = SecurityService.hashPassword('MyPassword123!');
      final hash2 = SecurityService.hashPassword('MyPassword123!');
      expect(hash1, equals(hash2));
    });
  });

  group('DatabaseService Business Logic Tests', () {
    late DatabaseService db;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = DatabaseService();
    });

    test('User registration and family creation with default Super list', () async {
      final uniqueEmail = 'test_${uuid.v4().substring(0, 8)}@example.com';
      final registered = await db.registerUser(
        nbCompleto: 'Test User',
        nbEmail: uniqueEmail,
        password: 'Password123!',
      );
      expect(registered, isTrue);
      expect(db.currentUser, isNotNull);

      final family = await db.createFamily('Familia Test', 'Pruebas');
      expect(family.clFamilia.startsWith('FAM-'), isTrue);

      final lists = db.getActiveShoppingLists();
      expect(lists.length, equals(1));
      expect(lists.first.nbLista, equals('Super'));
      expect(lists.first.isDefault, isTrue);
    });

    test('Logical soft delete and reactivation on list creation', () async {
      final uniqueEmail = 'test_${uuid.v4().substring(0, 8)}@example.com';
      await db.registerUser(
        nbCompleto: 'Test User',
        nbEmail: uniqueEmail,
        password: 'Password123!',
      );
      await db.createFamily('Familia Test', null);

      await db.createOrReactivateList('Carniceria');
      var lists = db.getActiveShoppingLists();
      expect(lists.any((l) => l.nbLista == 'Carniceria'), isTrue);

      final carniceriaList = lists.firstWhere((l) => l.nbLista == 'Carniceria');
      await db.softDeleteShoppingList(carniceriaList.idListaCompra);

      lists = db.getActiveShoppingLists();
      expect(lists.any((l) => l.nbLista == 'Carniceria'), isFalse);

      await db.createOrReactivateList('Carniceria');
      lists = db.getActiveShoppingLists();
      expect(lists.any((l) => l.nbLista == 'Carniceria'), isTrue);
    });

    test('Shopping lists and detail items are NOT cleared when minimizing/resuming app', () async {
      final uniqueEmail = 'test_${uuid.v4().substring(0, 8)}@example.com';
      await db.registerUser(
        nbCompleto: 'Resume Test User',
        nbEmail: uniqueEmail,
        password: 'Password123!',
      );
      await db.createFamily('Familia Resume Test', null);

      await db.createOrReactivateList('Frutas y Verduras');
      final lists = db.getActiveShoppingLists();
      final targetList = lists.firstWhere((l) => l.nbLista == 'Frutas y Verduras');

      await db.addItemToList(
        idListaCompra: targetList.idListaCompra,
        idArticulo: 'manzana_id',
        nbArticulo: 'Manzanas',
      );

      expect(db.getActiveShoppingLists().any((l) => l.nbLista == 'Frutas y Verduras'), isTrue);
      expect(db.getPendingItems(targetList.idListaCompra).length, equals(1));

      // Simular minimizado y reanudación de la app
      await db.loadLocalDataOnly();
      await db.onAppResume();

      // Verificar que NADA se haya limpiado o borrado
      final listsAfterResume = db.getActiveShoppingLists();
      expect(listsAfterResume.any((l) => l.nbLista == 'Frutas y Verduras'), isTrue);
      final itemsAfterResume = db.getPendingItems(targetList.idListaCompra);
      expect(itemsAfterResume.length, equals(1));
      expect(itemsAfterResume.first.nbArticulo, equals('Manzanas'));
    });

    test('unmarkItemAsCompleted restores completed item back to pending status', () async {
      final uniqueEmail = 'test_${uuid.v4().substring(0, 8)}@example.com';
      await db.registerUser(
        nbCompleto: 'Undo Test User',
        nbEmail: uniqueEmail,
        password: 'Password123!',
      );
      await db.createFamily('Familia Undo Test', null);

      await db.createOrReactivateList('Lista Deshacer');
      final targetList = db.getActiveShoppingLists().firstWhere((l) => l.nbLista == 'Lista Deshacer');

      await db.addItemToList(
        idListaCompra: targetList.idListaCompra,
        idArticulo: 'item_undo_1',
        nbArticulo: 'Pan Integral',
      );

      final pendingBefore = db.getPendingItems(targetList.idListaCompra);
      expect(pendingBefore.length, equals(1));
      final itemId = pendingBefore.first.idDetalle;

      // 1. Marcar como comprado
      await db.markItemAsCompleted(itemId);
      expect(db.getPendingItems(targetList.idListaCompra).length, equals(0));
      expect(db.getCompletedItems(targetList.idListaCompra).length, equals(1));

      // 2. Deshacer la acción
      await db.unmarkItemAsCompleted(itemId);
      expect(db.getPendingItems(targetList.idListaCompra).length, equals(1));
      expect(db.getCompletedItems(targetList.idListaCompra).length, equals(0));
      final restoredItem = db.getPendingItems(targetList.idListaCompra).first;
      expect(restoredItem.nbArticulo, equals('Pan Integral'));
      expect(restoredItem.isPending, isTrue);
      expect(restoredItem.fechaCompra, isNull);
    });
  });

  group('UndoHelper Widget Tests', () {
    testWidgets('UndoHelper shows floating SnackBar and invokes onUndo callback', (tester) async {
      bool undoExecuted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    UndoHelper.show(
                      context: context,
                      message: '"Pan" marcado como comprado',
                      actionLabel: 'Deshacer',
                      onUndo: () async {
                        undoExecuted = true;
                      },
                    );
                  },
                  child: const Text('Comprar'),
                );
              },
            ),
          ),
        ),
      );

      // Presionar botón para disparar SnackBar de deshacer
      await tester.tap(find.text('Comprar'));
      await tester.pump(const Duration(milliseconds: 500)); // Esperar animación de entrada

      expect(find.text('"Pan" marcado como comprado'), findsOneWidget);
      expect(find.byType(SnackBarAction), findsOneWidget);

      // Presionar acción 'Deshacer'
      final action = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
      action.onPressed();
      await tester.pump();

      expect(undoExecuted, isTrue);
    });

    testWidgets('UndoHelper automatically dismisses after duration (5s)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    UndoHelper.show(
                      context: context,
                      message: 'Producto completado',
                      actionLabel: 'Deshacer',
                      duration: const Duration(seconds: 5),
                      onUndo: () async {},
                    );
                  },
                  child: const Text('Comprar'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Comprar'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Producto completado'), findsOneWidget);

      // Avanzar el tiempo 5.5 segundos para que expire el timer y se cierre
      await tester.pump(const Duration(milliseconds: 5500));
      await tester.pumpAndSettle();

      expect(find.text('Producto completado'), findsNothing);
    });

    testWidgets('UndoHelper shows notification even if calling item widget unmounts', (tester) async {
      bool itemMounted = true;
      ScaffoldMessengerState? capturedMessenger;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: itemMounted
                    ? Builder(
                        builder: (itemContext) {
                          return ElevatedButton(
                            onPressed: () {
                              capturedMessenger = ScaffoldMessenger.of(itemContext);
                              setState(() {
                                itemMounted = false; // El elemento se desmonte inmediatamente
                              });
                              UndoHelper.show(
                                context: itemContext,
                                messenger: capturedMessenger,
                                message: 'Último producto comprado',
                                actionLabel: 'Deshacer',
                                onUndo: () async {},
                              );
                            },
                            child: const Text('Comprar Último'),
                          );
                        },
                      )
                    : const Text('Lista vacía'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Comprar Último'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Lista vacía'), findsOneWidget);
      expect(find.text('Último producto comprado'), findsOneWidget);
      expect(find.byType(SnackBarAction), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    });
  });
}
