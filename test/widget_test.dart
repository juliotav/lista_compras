import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lista_compras/services/security_service.dart';
import 'package:lista_compras/services/database_service.dart';
import 'package:lista_compras/utils/undo_helper.dart';
import 'package:lista_compras/widgets/family_qr_dialog.dart';
import 'package:lista_compras/widgets/logout_confirm_dialog.dart';
import 'package:lista_compras/models/family_model.dart';
import 'package:lista_compras/l10n/app_localizations.dart';
import 'package:lista_compras/screens/home_screen.dart';
import 'package:lista_compras/screens/family_setup_screen.dart';
import 'package:lista_compras/services/locale_provider.dart';
import 'package:lista_compras/services/theme_provider.dart';
import 'package:provider/provider.dart';
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

    test('finishAndCompleteEntireList marks all pending items as completed without closing the list', () async {
      final uniqueEmail = 'test_${uuid.v4().substring(0, 8)}@example.com';
      await db.registerUser(
        nbCompleto: 'Complete Items Test User',
        nbEmail: uniqueEmail,
        password: 'Password123!',
      );
      await db.createFamily('Familia Completar Test', null);

      await db.createOrReactivateList('Despensa');
      final targetList = db.getActiveShoppingLists().firstWhere((l) => l.nbLista == 'Despensa');

      await db.addItemToList(
        idListaCompra: targetList.idListaCompra,
        idArticulo: 'art_1',
        nbArticulo: 'Arroz',
      );
      await db.addItemToList(
        idListaCompra: targetList.idListaCompra,
        idArticulo: 'art_2',
        nbArticulo: 'Frijoles',
      );

      expect(db.getPendingItems(targetList.idListaCompra).length, equals(2));
      expect(db.getCompletedItems(targetList.idListaCompra).length, equals(0));

      await db.finishAndCompleteEntireList(targetList.idListaCompra);

      expect(db.getPendingItems(targetList.idListaCompra).length, equals(0));
      expect(db.getCompletedItems(targetList.idListaCompra).length, equals(2));

      final activeLists = db.getActiveShoppingLists();
      final updatedList = activeLists.firstWhere((l) => l.idListaCompra == targetList.idListaCompra);
      expect(updatedList.isActive, isTrue);
      expect(updatedList.isCompleted, isFalse);
    });

    test('New user creating a family and immediately deleting it clears active family and lists', () async {
      final uniqueEmail = 'test_${uuid.v4().substring(0, 8)}@example.com';
      await db.registerUser(
        nbCompleto: 'Delete Family User',
        nbEmail: uniqueEmail,
        password: 'Password123!',
      );

      final family = await db.createFamily('Familia Temporal', 'Para borrar');
      expect(db.currentUser?.idFamilia, equals(family.idFamilia));
      expect(db.userFamilies.length, equals(1));
      expect(db.getActiveShoppingLists().length, equals(1));

      final deleted = await db.deleteFamily(family.idFamilia);
      expect(deleted, isTrue);
      expect(db.currentUser?.idFamilia, isNull);
      expect(db.currentFamily, isNull);
      expect(db.userFamilies, isEmpty);
      expect(db.getActiveShoppingLists(), isEmpty);

      await db.loadLocalDataOnly();
      expect(db.currentUser?.idFamilia, isNull);
      expect(db.userFamilies, isEmpty);
    });

    testWidgets('HomeScreen redirects to FamilySetupScreen when user deletes their only family', (tester) async {
      final uniqueEmail = 'test_${uuid.v4().substring(0, 8)}@example.com';
      await db.registerUser(
        nbCompleto: 'Redirect User',
        nbEmail: uniqueEmail,
        password: 'Password123!',
      );
      final family = await db.createFamily('Familia Única', null);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => LocaleProvider()),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ChangeNotifierProvider.value(value: db),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('es'),
            home: HomeScreen(),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(HomeScreen), findsOneWidget);

      // Eliminar la única familia inmediatamente
      final deleted = await db.deleteFamily(family.idFamilia);
      expect(deleted, isTrue);

      await tester.pumpAndSettle();

      // Debe haber redirigido a FamilySetupScreen y no quedarse en HomeScreen vacío
      expect(find.byType(FamilySetupScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
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

  group('FamilyQrHelper Tests', () {
    test('buildQrPayload and extractFamilyCode handle prefixed and direct codes', () {
      final payload = FamilyQrHelper.buildQrPayload('fam-8x92k');
      expect(payload, equals('LISTALISTA:FAM-8X92K'));

      expect(FamilyQrHelper.extractFamilyCode(payload), equals('FAM-8X92K'));
      expect(FamilyQrHelper.extractFamilyCode('FAM-AB123'), equals('FAM-AB123'));
      expect(FamilyQrHelper.extractFamilyCode('  listalista:fam-z9y8x  '), equals('FAM-Z9Y8X'));
      expect(FamilyQrHelper.extractFamilyCode('https://example.com'), isNull);
      expect(FamilyQrHelper.extractFamilyCode('INVALID-CODE'), isNull);
      expect(FamilyQrHelper.extractFamilyCode(''), isNull);
      expect(FamilyQrHelper.extractFamilyCode(null), isNull);
    });

    testWidgets('showFamilyQrDialog renders QR dialog without layout or intrinsic exceptions', (tester) async {
      final family = FamilyModel(
        idFamilia: 'fam_1',
        idCreador: 'usr_1',
        nbFamilia: 'Familia Pérez',
        clFamilia: 'FAM-8X92K',
        fechaCreacion: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('es'),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => showFamilyQrDialog(context, family),
                  child: const Text('Mostrar QR'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Mostrar QR'));
      await tester.pumpAndSettle();

      expect(find.text('Familia Pérez'), findsOneWidget);
      expect(find.text('FAM-8X92K'), findsOneWidget);
    });
  });

  group('LogoutConfirmDialog Tests', () {
    testWidgets('returns false when cancelled and true when confirmed (es)', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('es'),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showLogoutConfirmDialog(context);
                  },
                  child: const Text('Abrir'),
                );
              },
            ),
          ),
        ),
      );

      // Cancelar
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      expect(find.text('¿Seguro que quieres cerrar sesión?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(result, isFalse);

      // Confirmar
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Cerrar Sesión'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });
  });
}
