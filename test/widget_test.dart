import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lista_compras/services/security_service.dart';
import 'package:lista_compras/services/database_service.dart';
import 'package:uuid/uuid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
  });
}
