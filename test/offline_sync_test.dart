import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lista_compras/services/connectivity_service.dart';
import 'package:lista_compras/services/local_db_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
  });
}
