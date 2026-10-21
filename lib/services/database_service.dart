import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../config/mongo_config.dart';
import '../config/notification_config.dart';
import '../models/user_model.dart';
import '../models/family_model.dart';
import '../models/shopping_list_model.dart';
import '../models/item_catalog_model.dart';
import '../models/list_detail_item_model.dart';
import '../models/user_family_model.dart';
import 'connectivity_service.dart';
import 'email_service.dart';
import 'local_db_service.dart';
import 'mongo_service.dart';
import 'push_notification_service.dart';
import 'security_service.dart';
import 'sync_service.dart';

class DatabaseService extends ChangeNotifier {
  final Uuid _uuid = const Uuid();
  final LocalDbService _localDb = LocalDbService();
  final SyncService _syncService = SyncService();
  final ConnectivityService _connectivity = ConnectivityService();
  bool _wasOffline = false;

  bool get isOnline => _connectivity.isOnline;
  bool get isOffline => _connectivity.isOffline;

  final List<UserModel> _users = [];
  final List<FamilyModel> _families = [];
  final List<FamilyModel> _userFamilies = [];
  List<FamilyModel> get userFamilies => List.unmodifiable(_userFamilies);

  final List<ShoppingListModel> _shoppingLists = [];
  List<ShoppingListModel> get shoppingLists =>
      List.unmodifiable(_shoppingLists);
  final List<ItemCatalogModel> _catalogItems = [];
  final List<ListDetailItemModel> _listDetailItems = [];

  final bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  bool _isBackgroundSyncing = false;
  bool get isBackgroundSyncing => _isBackgroundSyncing;

  bool _isReconnectingSync = false;
  bool get isReconnectingSync => _isReconnectingSync;

  /// Retorna la cantidad de mutaciones locales pendientes en la cola por hacer push
  Future<int> getPendingSyncCount() async {
    return await _localDb.getPendingSyncCount();
  }

  /// Retorna true si hay cambios locales en cola por hacer push a MongoDB
  Future<bool> hasPendingPush() async {
    final count = await _localDb.getPendingSyncCount();
    return count > 0;
  }

  /// Ejecuta la sincronización inmediata de la cola pendiente y espera a que el backend responda
  Future<void> syncNow() async {
    await _syncService.syncNow();
  }

  Timer? _backgroundSyncTimeoutTimer;

  void _startBackgroundSync() {
    _backgroundSyncTimeoutTimer?.cancel();
    if (!_isBackgroundSyncing) {
      _isBackgroundSyncing = true;
      notifyListeners();
    }
    // Safety watchdog: Si la sincronización dura más de 12 segundos por latencia o caída de red, forzar apagado
    _backgroundSyncTimeoutTimer = Timer(const Duration(seconds: 12), () {
      if (_isBackgroundSyncing) {
        debugPrint(
          "[DB_SERVICE] Watchdog: Tiempo límite de sincronización alcanzado (12s). Forzando cierre del indicador.",
        );
        _isBackgroundSyncing = false;
        _isFetchingFamilyData = false;
        _isReconnectingSync = false;
        notifyListeners();
      }
    });
  }

  void _stopBackgroundSync() {
    _backgroundSyncTimeoutTimer?.cancel();
    _backgroundSyncTimeoutTimer = null;
    if (_isBackgroundSyncing) {
      _isBackgroundSyncing = false;
      notifyListeners();
    }
  }

  void _handleConnectivityChange() async {
    final currentOnline = _connectivity.isOnline;
    if (currentOnline && _wasOffline) {
      _wasOffline = false;
      final pendingCount = await _localDb.getPendingSyncCount();
      if (pendingCount > 0) {
        debugPrint(
          "[DB_SERVICE] ¡Conexión restablecida con $pendingCount datos pendientes por hacer push! Disparando sincronización...",
        );
        unawaited(onInternetRestored(isAppOpen: false));
      } else {
        debugPrint(
          "[DB_SERVICE] ¡Conexión restablecida! Pero la cola está en 0 (sin datos por hacer push). Sincronización omitida.",
        );
      }
    } else if (!currentOnline && !_wasOffline) {
      _wasOffline = true;
      debugPrint("[DB_SERVICE] Modo sin conexión activado.");
    }
    notifyListeners();
  }

  /// Ejecuta la sincronización:
  /// - Si isAppOpen es false, SOLO activa la sincronización si hay datos pendientes por hacer push (sync_queue > 0).
  /// - Si la cola está en 0 y isAppOpen es false, omite la sincronización para evitar consumo de red y batería.
  /// - Si isAppOpen es true (al abrir la app o reanudarla), sincroniza con MongoDB para obtener la última versión.
  Future<void> onInternetRestored({bool isAppOpen = false}) async {
    if (isOffline) {
      debugPrint("[DB_SERVICE] Dispositivo sin conexión (offline). Sincronización omitida.");
      return;
    }
    if (_isReconnectingSync) return;

    final pendingCount = await _localDb.getPendingSyncCount();
    if (!isAppOpen && pendingCount == 0) {
      debugPrint("[DB_SERVICE] Cola de sincronización en 0 y no es apertura de app. Sincronización omitida.");
      return;
    }

    _isReconnectingSync = true;
    _startBackgroundSync();
    try {
      debugPrint(
        "[DB_SERVICE] --- INICIO DE SINCRONIZACIÓN (${isAppOpen ? 'APERTURA DE APP' : 'PUSH DE $pendingCount CAMBIOS'}) ---",
      );
      if (pendingCount > 0) {
        debugPrint("[DB_SERVICE] 1/3: Reiniciando contadores de reintento en sync_queue...");
        await _localDb.resetSyncQueueRetries();

        debugPrint("[DB_SERVICE] 2/3: Subiendo mutaciones locales pendientes a MongoDB en bulk...");
        await _syncService.syncNow();
      }

      debugPrint("[DB_SERVICE] 3/3: Descargando y fusionando delta remota de todas las listas y familias...");
      await fetchFamilyData(isSilentPeriodic: false);

      unawaited(checkAppVersion());
      debugPrint("[DB_SERVICE] --- SINCRONIZACIÓN COMPLETADA CON ÉXITO ---");
    } catch (e) {
      debugPrint("[DB_SERVICE] Error durante sincronización: $e");
    } finally {
      _isReconnectingSync = false;
      _stopBackgroundSync();
    }
  }

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  bool _isUpdateRequired = false;
  bool get isUpdateRequired => _isUpdateRequired;

  String? _remoteAppVersion;
  String? get remoteAppVersion => _remoteAppVersion;

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;

  FamilyModel? get currentFamily {
    final famId = _currentUser?.idFamilia;
    if (famId == null) return null;
    try {
      return _userFamilies.firstWhere((f) => f.idFamilia == famId);
    } catch (_) {
      try {
        return _families.firstWhere((f) => f.idFamilia == famId);
      } catch (_) {
        return null;
      }
    }
  }

  /// Retorna el nombre legible de una familia según su ID
  String getFamilyName(String idFamilia) {
    if (idFamilia.isEmpty) return '';
    try {
      final match = _userFamilies.firstWhere((f) => f.idFamilia == idFamilia);
      if (match.nbFamilia.isNotEmpty) return match.nbFamilia;
    } catch (_) {}

    try {
      final match = _families.firstWhere((f) => f.idFamilia == idFamilia);
      if (match.nbFamilia.isNotEmpty) return match.nbFamilia;
    } catch (_) {}

    if (currentFamily?.idFamilia == idFamilia &&
        currentFamily?.nbFamilia != null) {
      return currentFamily!.nbFamilia;
    }

    return '';
  }

  DatabaseService() {
    _wasOffline = _connectivity.isOffline;
    _connectivity.addListener(_handleConnectivityChange);
    _initSeedData();
    initSession();
  }

  @override
  void dispose() {
    _connectivity.removeListener(_handleConnectivityChange);
    super.dispose();
  }

  void _initSeedData() {
    final demoPassHash = SecurityService.hashPassword("Password123!");
    final demoUser = UserModel(
      idUsuario: "usr_demo",
      nbCompleto: "Julio Pérez",
      nbUsuario: "julioperez",
      nbEmail: "demo@ejemplo.com",
      clPass: demoPassHash,
    );
    _users.add(demoUser);
  }

  /// Carga la sesión guardada del usuario usando SQLite (0ms delay UI)
  Future<void> initSession() async {
    try {
      final savedUserId = await _localDb.getSessionUserId();

      if (savedUserId != null && savedUserId.isNotEmpty) {
        // Cargar usuario guardado localmente en SQLite
        final localUser = await _localDb.getUser(savedUserId);
        if (localUser != null) {
          _currentUser = localUser;
          if (!_users.any((u) => u.idUsuario == _currentUser!.idUsuario)) {
            _users.add(_currentUser!);
          }
        }

        if (_currentUser?.idFamilia != null) {
          await loadLocalDataOnly();
        }

        if (_currentUser != null) {
          await _localDb.saveSessionUserId(_currentUser!.idUsuario);
          _checkAndUpdateUserAppVersion(_currentUser!);
        }

        // Consultar usuario en MongoDB de fondo únicamente si está online
        unawaited(() async {
          if (isOffline) {
            debugPrint(
              "[DB_SERVICE LOG] Modo offline al iniciar sesión. Datos locales cargados exitosamente de SQLite.",
            );
            return;
          }
          try {
            final remoteUser = await MongoService.findOne(
              collectionName: MongoConfig.colUsuario,
              filter: {'id_usuario': savedUserId},
            );
            if (remoteUser != null) {
              _currentUser = UserModel.fromMap(remoteUser);
              await _localDb.saveUser(_currentUser!);
              final uIdx = _users.indexWhere(
                (u) => u.idUsuario == _currentUser!.idUsuario,
              );
              if (uIdx != -1) {
                _users[uIdx] = _currentUser!;
              } else {
                _users.add(_currentUser!);
              }
              if (_currentUser != null) {
                _checkAndUpdateUserAppVersion(_currentUser!);
              }
            }
            if (_currentUser != null) {
              PushNotificationService.subscribeToFamily(
                _currentUser!.idFamilia,
              );
              // PUSH ANTES DE PULL: Subir cambios locales pendientes de todas las listas/familias y luego descargar deltas
              await onInternetRestored(isAppOpen: true);
            }
          } catch (e) {
            debugPrint(
              "[DB_SERVICE LOG] Error en consulta background de initSession: $e",
            );
          }
        }());
      }
    } catch (e) {
      debugPrint("[DB_SERVICE LOG] Error cargando sesión local: $e");
    } finally {
      _isInitialized = true;
      notifyListeners();
      if (isOnline) {
        unawaited(checkAppVersion());
      }
    }
  }

  /// Compara dos versiones semánticas (ej. "1.0.15" y "1.0.14").
  /// Retorna < 0 si v1 < v2, 0 si v1 == v2, > 0 si v1 > v2.
  int _compareVersions(String v1, String v2) {
    final cleanV1 = v1.split('+').first.trim();
    final cleanV2 = v2.split('+').first.trim();

    final parts1 = cleanV1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final parts2 = cleanV2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final maxLength = max(parts1.length, parts2.length);
    for (int i = 0; i < maxLength; i++) {
      final num1 = i < parts1.length ? parts1[i] : 0;
      final num2 = i < parts2.length ? parts2[i] : 0;
      if (num1 != num2) {
        return num1.compareTo(num2);
      }
    }
    return 0;
  }

  /// Consulta en MongoDB Atlas la versión en la colección `app_version` para `app_name: listalista`.
  /// Soporta verificación por plataforma ('android', 'ios') y ambiente ('qa', 'pr').
  /// Mantiene compatibilidad total con el registro legacy (`app_version` en raíz).
  /// Si la versión requerida es estrictamente mayor que `MongoConfig.appVersion`, requiere actualización obligatoria.
  Future<void> checkAppVersion() async {
    try {
      await MongoConfig.loadAppVersionFromPubspec();
      final env = MongoConfig.currentEnv;
      final platform = MongoConfig.currentPlatform;
      final localVer = MongoConfig.appVersion.trim();

      // 1. Intentar consulta por coincidencia de ambiente y plataforma en raíz
      Map<String, dynamic>? doc = await MongoService.findOne(
        collectionName: MongoConfig.colAppVersion,
        filter: {
          'app_name': MongoConfig.appName,
          'environment': env,
          'platform': platform,
        },
      );

      // 2. Fallback a documento general/legacy por app_name
      doc ??= await MongoService.findOne(
        collectionName: MongoConfig.colAppVersion,
        filter: {'app_name': MongoConfig.appName},
      );

      if (doc != null) {
        String? remoteVer;

        // Extraer versión si existe estructura por entornos ('environments')
        if (doc['environments'] != null) {
          final envs = doc['environments'];
          if (envs is Map) {
            final envData = envs[env] ?? envs[env.toLowerCase()];
            if (envData is Map) {
              final platVer = envData[platform] ?? envData[platform.toLowerCase()];
              if (platVer != null) {
                remoteVer = platVer.toString().trim();
              }
            }
          }
        }

        // Fallback a versión global/legacy en raíz 'app_version'
        remoteVer ??= (doc['app_version'] as String?)?.trim();

        _remoteAppVersion = remoteVer;

        debugPrint(
          "[VERSION CHECK LOG] Env: '$env' | Platform: '$platform' | Local: '$localVer' | Remote: '$remoteVer'",
        );

        if (remoteVer != null && remoteVer.isNotEmpty) {
          final cmp = _compareVersions(localVer, remoteVer);
          if (cmp < 0) {
            debugPrint(
              "[VERSION CHECK] ¡Versión local ($localVer) es MENOR a la requerida ($remoteVer)! Requiere actualización.",
            );
            _isUpdateRequired = true;
            notifyListeners();
            return;
          } else {
            debugPrint(
              "[VERSION CHECK] Versión local ($localVer) está AL DÍA respecto a la requerida ($remoteVer).",
            );
          }
        }
      } else {
        debugPrint("[VERSION CHECK LOG] No se encontró ningún documento en app_version.");
      }
      _isUpdateRequired = false;
      notifyListeners();
    } catch (e, stack) {
      debugPrint(
        "[VERSION CHECK LOG] Error al consultar app_version en MongoDB: $e\n$stack",
      );
    }
  }

  /// Verifica si la versión de la app difiere de la registrada en el perfil del usuario.
  /// Si es diferente, actualiza ds_version_app en MongoDB Atlas y SQLite. Si es igual, omite llamadas de red (0 over-fetching).
  Future<void> _checkAndUpdateUserAppVersion(UserModel user) async {
    final currentAppVer = MongoConfig.appVersion;
    if (user.dsVersionApp != currentAppVer) {
      debugPrint(
        "[VERSION CHECK] Actualizando versión registrada del usuario '${user.idUsuario}' de '${user.dsVersionApp}' a '$currentAppVer'...",
      );
      final updatedUser = user.copyWith(dsVersionApp: currentAppVer);
      _currentUser = updatedUser;
      final idx = _users.indexWhere((u) => u.idUsuario == user.idUsuario);
      if (idx != -1) {
        _users[idx] = updatedUser;
      }
      await _localDb.saveUser(updatedUser);

      MongoService.updateOne(
        collectionName: MongoConfig.colUsuario,
        filter: {'id_usuario': user.idUsuario},
        update: {
          '\$set': {'ds_version_app': currentAppVer},
        },
      );
    }
  }

  bool _areListsEqual(List<ShoppingListModel> a, List<ShoppingListModel> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].idListaCompra != b[i].idListaCompra ||
          a[i].nbLista != b[i].nbLista ||
          a[i].isActive != b[i].isActive ||
          a[i].isCompleted != b[i].isCompleted ||
          a[i].isDefault != b[i].isDefault) {
        return false;
      }
    }
    return true;
  }

  bool _areCatalogEqual(List<ItemCatalogModel> a, List<ItemCatalogModel> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].idArticulo != b[i].idArticulo ||
          a[i].nbArticuloEs != b[i].nbArticuloEs ||
          a[i].nbArticuloEn != b[i].nbArticuloEn ||
          a[i].nuUso != b[i].nuUso) {
        return false;
      }
    }
    return true;
  }

  bool _areDetailsEqual(
    List<ListDetailItemModel> a,
    List<ListDetailItemModel> b,
  ) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].idDetalle != b[i].idDetalle ||
          a[i].status != b[i].status ||
          a[i].dsDetalle != b[i].dsDetalle ||
          a[i].nuOrder != b[i].nuOrder ||
          a[i].nbArticulo != b[i].nbArticulo ||
          a[i].fechaAgrego != b[i].fechaAgrego) {
        return false;
      }
    }
    return true;
  }

  /// Carga instantáneamente desde SQLite las listas, catálogo y productos guardados localmente
  Future<void> _loadFromLocalDb(String famId) async {
    try {
      final localLists = await _localDb.getShoppingLists(famId);
      final currentFamLists = _shoppingLists.where((l) => l.idFamilia == famId).toList();
      bool listsChanged = false;
      if (localLists.isNotEmpty || currentFamLists.isEmpty) {
        listsChanged = !_areListsEqual(currentFamLists, localLists);
        if (listsChanged) {
          _shoppingLists.removeWhere((l) => l.idFamilia == famId);
          _shoppingLists.addAll(localLists);
        }
      }

      final localCatalog = await _localDb.getCatalogItems(famId);
      final currentFamCatalog = _catalogItems.where((c) => c.idFamilia == famId).toList();
      bool catalogChanged = false;
      if (localCatalog.isNotEmpty || currentFamCatalog.isEmpty) {
        catalogChanged = !_areCatalogEqual(currentFamCatalog, localCatalog);
        if (catalogChanged) {
          _catalogItems.removeWhere((c) => c.idFamilia == famId);
          _catalogItems.addAll(localCatalog);
        }
      }

      final activeListIds = (localLists.isNotEmpty ? localLists : currentFamLists)
          .map((l) => l.idListaCompra)
          .toList();
      final localDetails = await _localDb.getAllListDetailsForFamily(
        activeListIds,
      );

      final currentDetails = _listDetailItems.where((d) => activeListIds.contains(d.idListaCompra)).toList();
      bool detailsChanged = false;
      if (localDetails.isNotEmpty || currentDetails.isEmpty) {
        detailsChanged = !_areDetailsEqual(currentDetails, localDetails);
        if (detailsChanged) {
          _listDetailItems.removeWhere((d) => activeListIds.contains(d.idListaCompra));
          _listDetailItems.addAll(localDetails);
        }
      }

      final localFamilies = await _localDb.getFamilies();
      bool familiesChanged = false;
      if (localFamilies.isNotEmpty) {
        familiesChanged = _userFamilies.length != localFamilies.length;
        _families.clear();
        _families.addAll(localFamilies);
        _userFamilies.clear();
        _userFamilies.addAll(localFamilies);
        PushNotificationService.syncFamilySubscriptions(
          _userFamilies.map((f) => f.idFamilia).toList(),
        );
      }

      final localUsers = await _localDb.getAllUsers();
      for (var u in localUsers) {
        final idx = _users.indexWhere(
          (existing) => existing.idUsuario == u.idUsuario,
        );
        if (idx == -1) {
          _users.add(u);
        } else {
          _users[idx] = u;
        }
      }

      if (listsChanged || catalogChanged || detailsChanged || familiesChanged) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint("[DB_SERVICE LOG] Error cargando de SQLite: $e");
    }
  }

  /// Carga instantáneamente desde SQLite los datos locales de todas las familias conocidas sin peticiones de red
  Future<void> loadLocalDataOnly() async {
    try {
      final localFamilies = await _localDb.getFamilies();
      if (localFamilies.isNotEmpty) {
        _families.clear();
        _families.addAll(localFamilies);
        _userFamilies.clear();
        _userFamilies.addAll(localFamilies);
        for (var f in localFamilies) {
          await _loadFromLocalDb(f.idFamilia);
        }
      } else {
        final famId = _currentUser?.idFamilia;
        if (famId != null && famId.isNotEmpty) {
          await _loadFromLocalDb(famId);
        }
      }
    } catch (e) {
      debugPrint("[DB_SERVICE LOG] Error en loadLocalDataOnly: $e");
    }
  }

  /// Reanudación desde segundo plano: Comprueba conectividad, carga SQLite de inmediato y dispara delta sync si está online
  Future<void> onAppResume() async {
    await _connectivity.checkConnectivity();
    final famId = _currentUser?.idFamilia;
    if (famId != null && famId.isNotEmpty) {
      debugPrint(
        "[DB_SERVICE LOG] App reanudada. Cargando SQLite de inmediato...",
      );
      await _loadFromLocalDb(famId);
      if (isOnline) {
        // PUSH ANTES DE PULL: Subir cambios locales pendientes de todas las listas/familias y luego descargar deltas
        await onInternetRestored(isAppOpen: true);
      }
    }
  }

  /// Obtiene todas las familias a las que está vinculado el usuario actual
  Future<void> fetchUserFamilies() async {
    final userId = _currentUser?.idUsuario;
    if (userId == null) return;

    try {
      var userFamDocs = await MongoService.find(
        collectionName: MongoConfig.colUsuarioFamilia,
        filter: {
          'id_usuario': userId,
          'status': {'\$ne': 'inactive'},
        },
      );

      final Set<String> knownFamIds = userFamDocs
          .map((doc) => doc['id_familia'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toSet();

      final List<FamilyModel> loadedFamilies = [];
      if (knownFamIds.isNotEmpty) {
        final famDocs = await MongoService.find(
          collectionName: MongoConfig.colFamilia,
          filter: {
            'id_familia': {'\$in': knownFamIds.toList()},
          },
        );
        for (var doc in famDocs) {
          loadedFamilies.add(FamilyModel.fromMap(doc));
        }
      }

      // Solo actualizamos familias si obtuvimos resultados válidos del servidor
      if (loadedFamilies.isNotEmpty) {
        _userFamilies.clear();
        _userFamilies.addAll(loadedFamilies);
        await _localDb.saveFamilies(loadedFamilies);
        PushNotificationService.syncFamilySubscriptions(
          _userFamilies.map((f) => f.idFamilia).toList(),
        );

        final oldFamId = _currentUser?.idFamilia;
        final isOldFamActive =
            oldFamId != null && _userFamilies.any((f) => f.idFamilia == oldFamId);

        if (!isOldFamActive) {
          final activeFamId = _userFamilies.first.idFamilia;
          _currentUser = _currentUser!.copyWith(idFamilia: activeFamId);
          if (_currentUser != null) {
            await _localDb.saveUser(_currentUser!);
          }
          await MongoService.updateOne(
            collectionName: MongoConfig.colUsuario,
            filter: {'id_usuario': userId},
            update: {
              '\$set': {'id_familia': activeFamId},
            },
          );
          await _loadFromLocalDb(activeFamId);
          PushNotificationService.subscribeToFamily(activeFamId);
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint("[DB_SERVICE LOG] Error en fetchUserFamilies: $e");
    }
  }

  Future<void> cleanOrphanCatalogItems() async {
    try {
      final allFamilies = await MongoService.find(
        collectionName: MongoConfig.colFamilia,
        filter: {},
      );
      final validFamIds = allFamilies
          .map((f) => f['id_familia'] as String)
          .toSet();

      final allCatalogDocs = await MongoService.find(
        collectionName: MongoConfig.colCArticulo,
        filter: {},
      );
      for (var doc in allCatalogDocs) {
        final famId = doc['id_familia'] as String?;
        if (famId != null && famId.isNotEmpty && !validFamIds.contains(famId)) {
          debugPrint(
            "[DB_SERVICE LOG] Limpiando automáticamente artículos huérfanos en c_articulo de la familia eliminada '$famId'...",
          );
          await MongoService.deleteMany(
            collectionName: MongoConfig.colCArticulo,
            filter: {'id_familia': famId},
          );
        }
      }
    } catch (e) {
      debugPrint("[DB_SERVICE LOG] Error limpiando catálogo huérfano: $e");
    }
  }

  bool _isFetchingFamilyData = false;
  bool get isFetchingFamilyData => _isFetchingFamilyData;

  /// Sincroniza en segundo plano todos los datos de la familia sin bloquear la UI ni borrar datos locales
  Future<void> fetchFamilyData({bool isSilentPeriodic = false}) async {
    final userId = _currentUser?.idUsuario;
    if (userId == null) return;

    if (isOffline) {
      debugPrint(
        "[DB_SERVICE LOG] Dispositivo sin conexión (offline). Omitiendo peticiones de red en fetchFamilyData.",
      );
      final initialFamId = _currentUser?.idFamilia;
      if (initialFamId != null && initialFamId.isNotEmpty && _listDetailItems.isEmpty) {
        await _loadFromLocalDb(initialFamId);
      }
      return;
    }

    // Si hay una reconexión en curso y esta llamada proviene de un timer periódico, ignorar para evitar colisiones
    if (_isReconnectingSync && isSilentPeriodic) {
      debugPrint("[DB_SERVICE LOG] Sincronización periódica omitida: reconexión activa.");
      return;
    }

    if (_isFetchingFamilyData) return;
    _isFetchingFamilyData = true;

    if (!isSilentPeriodic) {
      _startBackgroundSync();
    }

    try {
      // 1. Cargar estado de SQLite de inmediato solo si la memoria RAM no está poblada aún (0ms delay UI)
      final initialFamId = _currentUser?.idFamilia;
      if (initialFamId != null && initialFamId.isNotEmpty && _listDetailItems.isEmpty) {
        await _loadFromLocalDb(initialFamId);
      }

      // 2. Buscar y sincronizar las familias del usuario desde MongoDB Atlas
      await fetchUserFamilies();

      final famId = _currentUser?.idFamilia;
      if (famId == null || famId.isEmpty) {
        return;
      }

      // 3. Recargar de SQLite únicamente si la familia activa cambió tras consultar el servidor
      if (famId != initialFamId || _listDetailItems.isEmpty) {
        await _loadFromLocalDb(famId);
      }

      // Sincronizar perfiles de integrantes de la familia activa
      try {
        final Set<String> memberIds = {};

        // Creador de la familia
        final fam = currentFamily;
        if (fam != null && fam.idCreador.isNotEmpty) {
          memberIds.add(fam.idCreador);
        }

        // Miembros vinculados en usuario_familia
        final links = await MongoService.find(
          collectionName: MongoConfig.colUsuarioFamilia,
          filter: {
            'id_familia': famId,
            'status': {'\$ne': 'inactive'},
          },
        );
        for (var l in links) {
          final mId = l['id_usuario'] as String?;
          if (mId != null && mId.isNotEmpty) memberIds.add(mId);
        }

        // Miembros vinculados en usuario por id_familia
        final usersWithFam = await MongoService.find(
          collectionName: MongoConfig.colUsuario,
          filter: {'id_familia': famId},
        );
        for (var uDoc in usersWithFam) {
          final mId = uDoc['id_usuario'] as String?;
          if (mId != null && mId.isNotEmpty) memberIds.add(mId);
        }

        final Set<String> validMemberIds = Set.from(memberIds);

        if (memberIds.isNotEmpty) {
          final userDocs = await MongoService.find(
            collectionName: MongoConfig.colUsuario,
            filter: {
              'id_usuario': {'\$in': memberIds.toList()},
            },
          );
          for (var userDoc in userDocs) {
            final user = UserModel.fromMap(userDoc).copyWith(idFamilia: famId);
            await _localDb.saveUser(user);
            final idx = _users.indexWhere((u) => u.idUsuario == user.idUsuario);
            if (idx == -1) {
              _users.add(user);
            } else {
              _users[idx] = user;
            }
          }
        }

        // Limpiar de _users y _localDb cualquier usuario que ya no pertenezca a la familia
        for (int i = _users.length - 1; i >= 0; i--) {
          final u = _users[i];
          if (u.idFamilia == famId && !validMemberIds.contains(u.idUsuario) && u.idUsuario != fam?.idCreador) {
            final updated = u.copyWith(clearFamilia: true);
            await _localDb.saveUser(updated);
            _users.removeAt(i);
          }
        }
      } catch (e) {
        debugPrint(
          "[DB_SERVICE LOG] Error sincronizando integrantes de familia: $e",
        );
      }

      // 3. Disparar sincronización delta de la familia activa
      await _syncService.pullDeltaSync(
        famId: famId,
        onDataUpdated: () async {
          await _loadFromLocalDb(famId);
        },
      );

      // 4. Precarga única offline de todas las familias si aún no se ha sellado
      unawaited(warmUpOfflineCacheForAllFamilies(userId));
    } catch (e) {
      debugPrint("[DB_SERVICE LOG] Error en fetchFamilyData: $e");
    } finally {
      _isFetchingFamilyData = false;
      _stopBackgroundSync();
    }
  }

  /// Realiza la precarga/migración única de todas las familias del usuario a SQLite
  /// para garantizar que, si el usuario se queda sin conexión y cambia de familia,
  /// toda la información de listas, catálogos y productos ya esté disponible en local.
  /// Una vez completada, se sella con la bandera `offline_cache_v1_userId` y no vuelve a ejecutarse.
  Future<void> warmUpOfflineCacheForAllFamilies(String userId) async {
    if (isOffline) return;
    final isDone = await _localDb.isOfflineCacheWarmUpDone(userId);
    if (isDone) return;

    try {
      debugPrint("[DB_SERVICE] --- INICIANDO PRECARGA ÚNICA OFFLINE PARA TODAS LAS FAMILIAS ($userId) ---");
      // 1. Obtener todas las familias del usuario
      final allFamIds = _userFamilies.map((f) => f.idFamilia).where((id) => id.isNotEmpty).toList();
      if (allFamIds.isEmpty) return;

      // 2. Descargar en lote todas las listas de todas las familias en 1 sola consulta
      final listDocs = await MongoService.find(
        collectionName: MongoConfig.colListasCompra,
        filter: {
          'id_familia': {'\$in': allFamIds},
        },
      );
      final allLists = listDocs.map((doc) => ShoppingListModel.fromMap(doc)).toList();

      // Guardar listas en SQLite por familia
      for (var fId in allFamIds) {
        final famLists = allLists.where((l) => l.idFamilia == fId).toList();
        await _localDb.saveShoppingLists(famLists, famId: fId);
      }

      // 3. Descargar en lote el catálogo de todas las familias en 1 sola consulta
      final catalogDocs = await MongoService.find(
        collectionName: MongoConfig.colCArticulo,
        filter: {
          'id_familia': {'\$in': allFamIds},
        },
      );
      final allCatalog = catalogDocs.map((doc) => ItemCatalogModel.fromMap(doc)).toList();
      for (var fId in allFamIds) {
        final famCatalog = allCatalog.where((c) => c.idFamilia == fId).toList();
        await _localDb.saveCatalogItems(famCatalog, famId: fId);
      }

      // 4. Descargar en lote todos los detalles/productos de todas las listas en 1 sola consulta
      final allListIds = allLists.map((l) => l.idListaCompra).toList();
      if (allListIds.isNotEmpty) {
        final detailDocs = await MongoService.find(
          collectionName: MongoConfig.colDetalleLista,
          filter: {
            'id_lista_compra': {'\$in': allListIds},
          },
        );
        final allDetails = detailDocs.map((doc) => ListDetailItemModel.fromMap(doc)).toList();
        await _localDb.saveListDetailItemsBatch(allDetails, activeListIds: allListIds);
      }

      // 5. Sellar la migración en SharedPreferences para que jamás vuelva a correr
      await _localDb.setOfflineCacheWarmUpDone(userId, done: true);
      debugPrint("[DB_SERVICE] --- ¡PRECARGA ÚNICA OFFLINE SELLADA CON ÉXITO PARA $userId! ---");
    } catch (e) {
      debugPrint("[DB_SERVICE] Error en precarga única offline: $e");
    }
  }

  // --- AUTENTICACIÓN ---
  Future<bool> registerUser({
    required String nbCompleto,
    String? nbUsuario,
    required String nbEmail,
    required String password,
  }) async {
    final cleanEmail = nbEmail.trim().toLowerCase();
    final cleanUsername = nbUsuario?.trim().toLowerCase();
    final cleanPass = password.trim();

    final escapedEmail = RegExp.escape(cleanEmail);
    final remoteUser = await MongoService.findOne(
      collectionName: MongoConfig.colUsuario,
      filter: {
        'nb_email': {r'$regex': '^$escapedEmail\$', r'$options': 'i'},
      },
    );

    if (remoteUser != null) {
      throw Exception("El correo electrónico ya está registrado.");
    }

    // Asegurar que no quede ningún residuo local (en memoria ni en SQLite) para este correo
    _users.removeWhere((u) => u.nbEmail.toLowerCase() == cleanEmail);
    await _localDb.deleteUserByEmail(cleanEmail);

    final passHash = SecurityService.hashPassword(cleanPass);
    final rnd = Random();
    final pinCode = (100000 + rnd.nextInt(900000)).toString();
    final pinHash = SecurityService.hashPassword(pinCode);
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(const Duration(minutes: 10)).toIso8601String();

    final newUser = UserModel(
      idUsuario: _uuid.v4(),
      nbCompleto: nbCompleto.trim(),
      nbUsuario: cleanUsername?.isEmpty == true ? null : cleanUsername,
      nbEmail: cleanEmail,
      clPass: passHash,
      dsVersionApp: MongoConfig.appVersion,
      status: 'pending_activation',
    );

    final userDoc = newUser.toMap();
    userDoc['cd_activacion_pin'] = pinHash;
    userDoc['fh_activacion_expires'] = expiresAt;
    userDoc['fh_ultimo_envio_activacion'] = now.toIso8601String();
    userDoc['fh_primer_envio_ventana'] = now.toIso8601String();
    userDoc['nu_envios_activacion'] = 1;

    await MongoService.insertOne(
      collectionName: MongoConfig.colUsuario,
      document: userDoc,
    );

    unawaited(
      EmailService.sendActivationCodeEmail(
        toEmail: cleanEmail,
        pinCode: pinCode,
        userName: nbCompleto.trim(),
      ),
    );

    _users.add(newUser);
    _currentUser = newUser;
    await _localDb.saveUser(newUser);
    await _localDb.saveSessionUserId(newUser.idUsuario);

    notifyListeners();
    return true;
  }

  // --- ACTIVACIÓN DE CUENTA ---

  /// Reenvía el código de activación con control de saturación (máximo 5 correos en 10 minutos).
  Future<Map<String, dynamic>> resendActivationCode() async {
    if (_currentUser == null) {
      return {'success': false, 'error': 'no_user'};
    }

    final userId = _currentUser!.idUsuario;
    final now = DateTime.now().toUtc();

    final userDoc = await MongoService.findOne(
      collectionName: MongoConfig.colUsuario,
      filter: {'id_usuario': userId},
    );

    if (userDoc == null) {
      return {'success': false, 'error': 'user_not_found'};
    }

    if (userDoc['status'] == 'active') {
      _currentUser = _currentUser!.copyWith(status: 'active');
      await _localDb.saveUser(_currentUser!);
      notifyListeners();
      return {'success': true, 'already_active': true};
    }

    // 1. Validar si hay un bloqueo de 10 minutos activo
    if (userDoc['fh_bloqueo_activacion'] != null) {
      final blockedUntil = DateTime.tryParse(userDoc['fh_bloqueo_activacion'].toString());
      if (blockedUntil != null && now.isBefore(blockedUntil)) {
        final remainingSeconds = blockedUntil.difference(now).inSeconds;
        final remainingMinutes = (remainingSeconds / 60).ceil();
        return {
          'success': false,
          'error': 'rate_limit_exceeded',
          'remainingSeconds': remainingSeconds,
          'remainingMinutes': remainingMinutes,
        };
      }
    }

    // 2. Control de ventana de 10 minutos
    int sendCount = (userDoc['nu_envios_activacion'] as num?)?.toInt() ?? 0;
    DateTime? firstSentInWindow;
    if (userDoc['fh_primer_envio_ventana'] != null) {
      firstSentInWindow = DateTime.tryParse(userDoc['fh_primer_envio_ventana'].toString());
    } else if (userDoc['fh_ultimo_envio_activacion'] != null) {
      firstSentInWindow = DateTime.tryParse(userDoc['fh_ultimo_envio_activacion'].toString());
    }

    DateTime windowStart = firstSentInWindow ?? now;
    if (now.difference(windowStart).inMinutes >= 10) {
      sendCount = 0;
      windowStart = now;
    }

    if (sendCount >= 5) {
      final blockUntil = (userDoc['fh_bloqueo_activacion'] != null)
          ? DateTime.tryParse(userDoc['fh_bloqueo_activacion'].toString()) ?? windowStart.add(const Duration(minutes: 10))
          : windowStart.add(const Duration(minutes: 10));
      final remainingSeconds = max(1, blockUntil.difference(now).inSeconds);
      final remainingMinutes = (remainingSeconds / 60).ceil();
      return {
        'success': false,
        'error': 'rate_limit_exceeded',
        'remainingSeconds': remainingSeconds,
        'remainingMinutes': remainingMinutes,
      };
    }

    sendCount++;
    DateTime? blockUntil;
    if (sendCount >= 5) {
      blockUntil = now.add(const Duration(minutes: 10));
    }

    // 3. Generar nuevo PIN de 6 dígitos
    final rnd = Random();
    final pinCode = (100000 + rnd.nextInt(900000)).toString();
    final pinHash = SecurityService.hashPassword(pinCode);
    final expiresAt = now.add(const Duration(minutes: 10)).toIso8601String();

    final updateFields = <String, dynamic>{
      'cd_activacion_pin': pinHash,
      'fh_activacion_expires': expiresAt,
      'fh_ultimo_envio_activacion': now.toIso8601String(),
      'fh_primer_envio_ventana': windowStart.toIso8601String(),
      'nu_envios_activacion': sendCount,
    };
    if (blockUntil != null) {
      updateFields['fh_bloqueo_activacion'] = blockUntil.toIso8601String();
    }

    await MongoService.updateOne(
      collectionName: MongoConfig.colUsuario,
      filter: {'id_usuario': userId},
      update: {
        r'$set': updateFields,
        if (blockUntil == null) r'$unset': {'fh_bloqueo_activacion': ''},
      },
    );

    // 4. Enviar correo
    final targetEmail = userDoc['nb_email'] as String? ?? _currentUser!.nbEmail;
    final targetName = userDoc['nb_completo'] as String? ?? _currentUser!.nbCompleto;

    final sent = await EmailService.sendActivationCodeEmail(
      toEmail: targetEmail,
      pinCode: pinCode,
      userName: targetName,
    );

    if (sent) {
      return {
        'success': true,
        'sendCount': sendCount,
        'remainingAttempts': max(0, 5 - sendCount),
        'isBlockedNow': blockUntil != null,
        'remainingMinutes': blockUntil != null ? 10 : null,
      };
    } else {
      return {'success': false, 'error': 'send_email_error'};
    }
  }

  /// Verifica el PIN de activación y cambia el estatus a activo.
  Future<Map<String, dynamic>> verifyActivationCode(String pinCode) async {
    if (_currentUser == null) {
      return {'success': false, 'error': 'no_user'};
    }

    final cleanPin = pinCode.trim();
    if (cleanPin.length != 6) {
      return {'success': false, 'error': 'invalid_format'};
    }

    final userId = _currentUser!.idUsuario;
    final now = DateTime.now().toUtc();

    final userDoc = await MongoService.findOne(
      collectionName: MongoConfig.colUsuario,
      filter: {'id_usuario': userId},
    );

    if (userDoc == null) {
      return {'success': false, 'error': 'user_not_found'};
    }

    if (userDoc['status'] == 'active') {
      _currentUser = _currentUser!.copyWith(status: 'active');
      await _localDb.saveUser(_currentUser!);
      notifyListeners();
      return {'success': true};
    }

    // Validar expiración
    final expiresStr = userDoc['fh_activacion_expires'] as String?;
    if (expiresStr != null) {
      final expires = DateTime.tryParse(expiresStr);
      if (expires != null && now.isAfter(expires)) {
        return {'success': false, 'error': 'expired'};
      }
    }

    // Validar PIN
    final storedHash = userDoc['cd_activacion_pin'] as String?;
    final pinHash = SecurityService.hashPassword(cleanPin);
    if (storedHash != pinHash) {
      return {'success': false, 'error': 'incorrect_pin'};
    }

    // Activar usuario en MongoDB
    await MongoService.updateOne(
      collectionName: MongoConfig.colUsuario,
      filter: {'id_usuario': userId},
      update: {
        r'$set': {'status': 'active'},
        r'$unset': {
          'cd_activacion_pin': '',
          'fh_activacion_expires': '',
          'nu_envios_activacion': '',
          'fh_ultimo_envio_activacion': '',
          'fh_primer_envio_ventana': '',
          'fh_bloqueo_activacion': '',
        },
      },
    );

    _currentUser = _currentUser!.copyWith(status: 'active');
    await _localDb.saveUser(_currentUser!);

    if (_currentUser?.idFamilia != null) {
      await fetchFamilyData();
    }

    notifyListeners();
    return {'success': true};
  }

  /// Obtiene información sobre el estado de activación y tasa de envíos para la interfaz de usuario.
  Future<Map<String, dynamic>> getActivationStatus() async {
    if (_currentUser == null) {
      return {'status': 'none'};
    }
    final userId = _currentUser!.idUsuario;
    final now = DateTime.now().toUtc();
    final userDoc = await MongoService.findOne(
      collectionName: MongoConfig.colUsuario,
      filter: {'id_usuario': userId},
    );
    if (userDoc == null) return {'status': 'not_found'};

    final status = userDoc['status'] as String? ?? 'active';
    if (status == 'active') {
      return {'status': 'active'};
    }

    int remainingBlockSeconds = 0;
    if (userDoc['fh_bloqueo_activacion'] != null) {
      final blockedUntil = DateTime.tryParse(userDoc['fh_bloqueo_activacion'].toString());
      if (blockedUntil != null && now.isBefore(blockedUntil)) {
        remainingBlockSeconds = blockedUntil.difference(now).inSeconds;
      }
    }

    int sendCount = (userDoc['nu_envios_activacion'] as num?)?.toInt() ?? 1;
    DateTime? windowStart;
    if (userDoc['fh_primer_envio_ventana'] != null) {
      windowStart = DateTime.tryParse(userDoc['fh_primer_envio_ventana'].toString());
    }
    if (windowStart != null && now.difference(windowStart).inMinutes >= 10) {
      sendCount = 0;
    }

    int remainingPinSeconds = 0;
    if (userDoc['fh_activacion_expires'] != null) {
      final expiresAt = DateTime.tryParse(userDoc['fh_activacion_expires'].toString());
      if (expiresAt != null && now.isBefore(expiresAt)) {
        remainingPinSeconds = expiresAt.difference(now).inSeconds;
      }
    }

    return {
      'status': status,
      'sendCount': sendCount,
      'maxSends': 5,
      'isBlocked': remainingBlockSeconds > 0,
      'remainingBlockSeconds': remainingBlockSeconds,
      'remainingPinSeconds': remainingPinSeconds,
      'email': userDoc['nb_email'] as String? ?? _currentUser!.nbEmail,
    };
  }

  Future<bool> loginUser(String emailOrUsername, String password) async {
    final cleanInput = emailOrUsername.trim().toLowerCase();
    final cleanPass = password.trim();
    final passHash = SecurityService.hashPassword(cleanPass);

    final escapedInput = RegExp.escape(cleanInput);

    Map<String, dynamic>? remoteUserMap = await MongoService.findOne(
      collectionName: MongoConfig.colUsuario,
      filter: {
        'nb_email': {r'$regex': '^$escapedInput\$', r'$options': 'i'},
      },
    );

    remoteUserMap ??= await MongoService.findOne(
      collectionName: MongoConfig.colUsuario,
      filter: {
        'nb_usuario': {r'$regex': '^$escapedInput\$', r'$options': 'i'},
      },
    );

    if (remoteUserMap != null) {
      final storedPass = remoteUserMap['cl_pass'] as String?;
      if (storedPass == passHash) {
        _currentUser = UserModel.fromMap(remoteUserMap);
        await _localDb.saveUser(_currentUser!);
        await _localDb.saveSessionUserId(_currentUser!.idUsuario);
        await _checkAndUpdateUserAppVersion(_currentUser!);
        await fetchFamilyData();
        if (_currentUser?.idFamilia != null) {
          PushNotificationService.subscribeToFamily(_currentUser!.idFamilia);
        }
        notifyListeners();
        return true;
      } else {
        return false;
      }
    }

    try {
      final user = _users.firstWhere(
        (u) =>
            (u.nbEmail.toLowerCase() == cleanInput ||
                (u.nbUsuario != null &&
                    u.nbUsuario!.toLowerCase() == cleanInput)) &&
            u.clPass == passHash,
      );
      _currentUser = user;
      await _localDb.saveUser(user);
      await _localDb.saveSessionUserId(user.idUsuario);
      await _checkAndUpdateUserAppVersion(_currentUser!);
      await fetchFamilyData();
      if (_currentUser?.idFamilia != null) {
        PushNotificationService.subscribeToFamily(_currentUser!.idFamilia);
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    _syncService.cancelDebounce();
    _currentUser = null;
    _users.clear();
    _userFamilies.clear();
    _families.clear();
    await _localDb.clearSession();
    _shoppingLists.clear();
    _listDetailItems.clear();
    _catalogItems.clear();
    await PushNotificationService.unsubscribeAllFamilies();
    notifyListeners();
  }

  /// Elimina de forma permanente la cuenta del usuario y sus datos de MongoDB y del almacenamiento local.
  Future<Map<String, dynamic>> deleteAccount({
    String? password,
    bool isPendingActivation = false,
  }) async {
    if (_currentUser == null) {
      return {'success': false, 'error': 'no_user'};
    }

    if (!isPendingActivation || (password != null && password.trim().isNotEmpty)) {
      final cleanPass = (password ?? '').trim();
      final passHash = SecurityService.hashPassword(cleanPass);
      if (_currentUser!.clPass != passHash) {
        return {'success': false, 'error': 'incorrect_password'};
      }
    }

    final userId = _currentUser!.idUsuario;

    try {
      // 1. Obtener todas las familias asociadas al usuario
      final userFamDocs = await MongoService.find(
        collectionName: MongoConfig.colUsuarioFamilia,
        filter: {'id_usuario': userId},
      );

      final Set<String> familyIds = userFamDocs
          .map((d) => d['id_familia'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toSet();

      if (_currentUser?.idFamilia != null && _currentUser!.idFamilia!.isNotEmpty) {
        familyIds.add(_currentUser!.idFamilia!);
      }

      for (var famId in familyIds) {
        final allMembers = await MongoService.find(
          collectionName: MongoConfig.colUsuarioFamilia,
          filter: {'id_familia': famId, 'status': 'active'},
        );

        final otherActiveMembers = allMembers
            .where((m) => m['id_usuario'] != userId)
            .toList();

        if (otherActiveMembers.isEmpty) {
          // El usuario es el único miembro activo: borrar familia y sus listas
          final lists = await MongoService.find(
            collectionName: MongoConfig.colListasCompra,
            filter: {'id_familia': famId},
          );
          final listIds = lists
              .map((l) => l['id_lista_compra'] as String?)
              .where((id) => id != null && id.isNotEmpty)
              .cast<String>()
              .toList();

          for (var listId in listIds) {
            await MongoService.deleteMany(
              collectionName: MongoConfig.colDetalleLista,
              filter: {'id_lista_compra': listId},
            );
            await _localDb.deleteShoppingListLocally(listId);
          }

          await MongoService.deleteMany(
            collectionName: MongoConfig.colListasCompra,
            filter: {'id_familia': famId},
          );
          await MongoService.deleteMany(
            collectionName: MongoConfig.colCArticulo,
            filter: {'id_familia': famId},
          );
          await MongoService.deleteMany(
            collectionName: MongoConfig.colUsuarioFamilia,
            filter: {'id_familia': famId},
          );
          await MongoService.deleteOne(
            collectionName: MongoConfig.colFamilia,
            filter: {'id_familia': famId},
          );
          await _localDb.deleteFamilyLocally(famId);
        } else {
          // Hay otros miembros activos: sólo desvincular al usuario
          await MongoService.deleteMany(
            collectionName: MongoConfig.colUsuarioFamilia,
            filter: {'id_usuario': userId, 'id_familia': famId},
          );

          // Si era el creador, transferir autoría al siguiente miembro activo
          final famDoc = await MongoService.findOne(
            collectionName: MongoConfig.colFamilia,
            filter: {'id_familia': famId},
          );
          if (famDoc != null && famDoc['id_creador'] == userId) {
            final newCreatorId = otherActiveMembers.first['id_usuario'] as String;
            await MongoService.updateOne(
              collectionName: MongoConfig.colFamilia,
              filter: {'id_familia': famId},
              update: {
                r'$set': {'id_creador': newCreatorId},
              },
            );
          }
        }
      }

      // 2. Limpiar cualquier registro residual en usuario_familia
      await MongoService.deleteMany(
        collectionName: MongoConfig.colUsuarioFamilia,
        filter: {'id_usuario': userId},
      );

      // 3. Eliminar el documento del usuario en la colección usuario
      await MongoService.deleteOne(
        collectionName: MongoConfig.colUsuario,
        filter: {'id_usuario': userId},
      );

      // 4. Limpieza local completa y desuscripción de notificaciones push
      _syncService.cancelDebounce();
      await PushNotificationService.unsubscribeAllFamilies();
      await _localDb.clearAllData();

      // 5. Limpieza total de estado en memoria
      _currentUser = null;
      _users.clear();
      _shoppingLists.clear();
      _listDetailItems.clear();
      _catalogItems.clear();
      _userFamilies.clear();
      _families.clear();
      _isBackgroundSyncing = false;
      _isFetchingFamilyData = false;

      notifyListeners();
      return {'success': true};
    } catch (e) {
      debugPrint("[DB_SERVICE LOG] Error en deleteAccount: $e");
      return {'success': false, 'error': e.toString()};
    }
  }

  // --- RECUPERACIÓN DE CONTRASEÑA ---
  Future<Map<String, dynamic>> requestPasswordReset(
    String emailOrUsername,
  ) async {
    final cleanInput = emailOrUsername.trim().toLowerCase();
    if (cleanInput.isEmpty) {
      return {'success': false, 'message': 'invalidEmail'};
    }

    final escapedInput = RegExp.escape(cleanInput);

    Map<String, dynamic>? userMap = await MongoService.findOne(
      collectionName: MongoConfig.colUsuario,
      filter: {
        'nb_email': {r'$regex': '^$escapedInput\$', r'$options': 'i'},
      },
    );

    userMap ??= await MongoService.findOne(
      collectionName: MongoConfig.colUsuario,
      filter: {
        'nb_usuario': {r'$regex': '^$escapedInput\$', r'$options': 'i'},
      },
    );

    if (userMap == null) {
      return {'success': true, 'email': cleanInput, 'userExists': false};
    }

    final targetEmail = (userMap['nb_email'] as String).toLowerCase();
    final rnd = Random();
    final pinCode = (100000 + rnd.nextInt(900000)).toString();
    final pinHash = SecurityService.hashPassword(pinCode);
    final expiresAt = DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 10))
        .toIso8601String();

    await MongoService.updateOne(
      collectionName: MongoConfig.colUsuario,
      filter: {'id_usuario': userMap['id_usuario']},
      update: {
        '\$set': {'cd_reset_pin': pinHash, 'fh_reset_expires': expiresAt},
      },
    );

    final sent = await EmailService.sendResetPinEmail(
      toEmail: targetEmail,
      pinCode: pinCode,
    );

    if (sent) {
      return {'success': true, 'email': targetEmail};
    } else {
      return {'success': false, 'message': 'sendEmailErr'};
    }
  }

  Future<bool> verifyResetPin(String email, String pinCode) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanPin = pinCode.trim();
    if (cleanEmail.isEmpty || cleanPin.length != 6) return false;

    final pinHash = SecurityService.hashPassword(cleanPin);
    final escapedEmail = RegExp.escape(cleanEmail);

    final userMap = await MongoService.findOne(
      collectionName: MongoConfig.colUsuario,
      filter: {
        'nb_email': {r'$regex': '^$escapedEmail\$', r'$options': 'i'},
      },
    );

    if (userMap == null) return false;

    final storedPinHash = userMap['cd_reset_pin'] as String?;
    final storedExpiresStr = userMap['fh_reset_expires'] as String?;

    if (storedPinHash == null || storedExpiresStr == null) return false;
    if (storedPinHash != pinHash) return false;

    try {
      final expiresAt = DateTime.parse(storedExpiresStr).toUtc();
      final nowUtc = DateTime.now().toUtc();
      if (nowUtc.isAfter(expiresAt)) return false;
    } catch (_) {
      return false;
    }

    return true;
  }

  Future<bool> resetPasswordWithPin(
    String email,
    String pinCode,
    String newPassword,
  ) async {
    final isValid = await verifyResetPin(email, pinCode);
    if (!isValid) return false;

    final cleanEmail = email.trim().toLowerCase();
    final newPassHash = SecurityService.hashPassword(newPassword.trim());
    final escapedEmail = RegExp.escape(cleanEmail);

    final success = await MongoService.updateOne(
      collectionName: MongoConfig.colUsuario,
      filter: {
        'nb_email': {r'$regex': '^$escapedEmail\$', r'$options': 'i'},
      },
      update: {
        '\$set': {'cl_pass': newPassHash},
        '\$unset': {'cd_reset_pin': '', 'fh_reset_expires': ''},
      },
    );

    return success;
  }

  Future<void> switchFamily(String idFamilia) async {
    if (_currentUser == null) return;
    if (_currentUser!.idFamilia == idFamilia) return;

    _currentUser = _currentUser!.copyWith(idFamilia: idFamilia);
    await _localDb.saveUser(_currentUser!);
    await _loadFromLocalDb(idFamilia);
    notifyListeners();

    unawaited(() async {
      try {
        await MongoService.updateOne(
          collectionName: MongoConfig.colUsuario,
          filter: {'id_usuario': _currentUser!.idUsuario},
          update: {
            '\$set': {'id_familia': idFamilia},
          },
        );

        PushNotificationService.subscribeToFamily(idFamilia);

        // Asegurar que la familia esté registrada en _userFamilies si no existía localmente
        if (!_userFamilies.any((f) => f.idFamilia == idFamilia)) {
          final famDocs = await MongoService.find(
            collectionName: MongoConfig.colFamilia,
            filter: {'id_familia': idFamilia},
          );
          if (famDocs.isNotEmpty) {
            final loadedFam = FamilyModel.fromMap(famDocs.first);
            _userFamilies.add(loadedFam);
            if (!_families.any((f) => f.idFamilia == idFamilia)) {
              _families.add(loadedFam);
            }
            await _localDb.saveFamilies(_userFamilies);
          }
        }

        await _syncService.pullDeltaSync(
          famId: idFamilia,
          onDataUpdated: () async {
            await _loadFromLocalDb(idFamilia);
          },
        );
      } catch (e) {
        debugPrint("[DB_SERVICE] Error en background sync de switchFamily: $e");
      }
    }());
  }

  Future<void> leaveFamily(String idFamilia) async {
    final userId = _currentUser?.idUsuario;
    if (userId == null) return;

    await MongoService.updateOne(
      collectionName: MongoConfig.colUsuarioFamilia,
      filter: {'id_usuario': userId, 'id_familia': idFamilia},
      update: {
        '\$set': {'status': 'inactive'},
      },
    );

    await _localDb.deleteFamilyLocally(idFamilia);

    _userFamilies.removeWhere((f) => f.idFamilia == idFamilia);
    _families.removeWhere((f) => f.idFamilia == idFamilia);
    PushNotificationService.unsubscribeFromFamily(idFamilia);

    if (_currentUser?.idFamilia == idFamilia) {
      if (_userFamilies.isNotEmpty) {
        final newActiveFamId = _userFamilies.first.idFamilia;
        _currentUser = _currentUser!.copyWith(idFamilia: newActiveFamId);
        await _localDb.saveUser(_currentUser!);
        await MongoService.updateOne(
          collectionName: MongoConfig.colUsuario,
          filter: {'id_usuario': userId},
          update: {
            '\$set': {'id_familia': newActiveFamId},
          },
        );
        await _loadFromLocalDb(newActiveFamId);
        PushNotificationService.subscribeToFamily(newActiveFamId);
      } else {
        _currentUser = _currentUser!.copyWith(clearFamilia: true);
        await _localDb.saveUser(_currentUser!);
        await MongoService.updateOne(
          collectionName: MongoConfig.colUsuario,
          filter: {'id_usuario': userId},
          update: {
            '\$unset': {'id_familia': ""},
          },
        );
        _shoppingLists.clear();
        _listDetailItems.clear();
        _catalogItems.clear();
      }
    }

    await fetchFamilyData();
    notifyListeners();
  }

  Future<bool> deleteFamily(String idFamilia) async {
    final userId = _currentUser?.idUsuario;
    if (userId == null) return false;

    final famIndex = _userFamilies.indexWhere((f) => f.idFamilia == idFamilia);
    if (famIndex == -1) return false;

    final family = _userFamilies[famIndex];
    if (family.idCreador != userId) return false;

    try {
      final familyListDocs = await MongoService.find(
        collectionName: MongoConfig.colListasCompra,
        filter: {'id_familia': idFamilia},
      );
      final familyListIds = familyListDocs
          .map((l) => l['id_lista_compra'] as String)
          .toList();

      for (var listId in familyListIds) {
        await MongoService.deleteMany(
          collectionName: MongoConfig.colDetalleLista,
          filter: {'id_lista_compra': listId},
        );
        await _localDb.deleteShoppingListLocally(listId);
      }

      await MongoService.deleteMany(
        collectionName: MongoConfig.colListasCompra,
        filter: {'id_familia': idFamilia},
      );
      await MongoService.deleteMany(
        collectionName: MongoConfig.colCArticulo,
        filter: {'id_familia': idFamilia},
      );
      await MongoService.deleteMany(
        collectionName: MongoConfig.colUsuarioFamilia,
        filter: {'id_familia': idFamilia},
      );
      await MongoService.deleteOne(
        collectionName: MongoConfig.colFamilia,
        filter: {'id_familia': idFamilia},
      );

      await _localDb.deleteFamilyLocally(idFamilia);

      _userFamilies.removeWhere((f) => f.idFamilia == idFamilia);
      _families.removeWhere((f) => f.idFamilia == idFamilia);

      if (_currentUser?.idFamilia == idFamilia) {
        if (_userFamilies.isNotEmpty) {
          final newActiveId = _userFamilies.first.idFamilia;
          _currentUser = _currentUser!.copyWith(idFamilia: newActiveId);
          await _localDb.saveUser(_currentUser!);
          await MongoService.updateOne(
            collectionName: MongoConfig.colUsuario,
            filter: {'id_usuario': userId},
            update: {
              '\$set': {'id_familia': newActiveId},
            },
          );
          await _loadFromLocalDb(newActiveId);
          PushNotificationService.subscribeToFamily(newActiveId);
        } else {
          _currentUser = _currentUser!.copyWith(clearFamilia: true);
          await _localDb.saveUser(_currentUser!);
          await MongoService.updateOne(
            collectionName: MongoConfig.colUsuario,
            filter: {'id_usuario': userId},
            update: {
              '\$unset': {'id_familia': ""},
            },
          );
          _shoppingLists.clear();
          _listDetailItems.clear();
          _catalogItems.clear();
        }
      }

      await fetchFamilyData();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("[DB_SERVICE LOG] Error en deleteFamily: $e");
      return false;
    }
  }

  // --- GESTIÓN DE FAMILIA ---
  String _generateFamilyCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random();
    final code = List.generate(
      5,
      (_) => chars[rnd.nextInt(chars.length)],
    ).join();
    return 'FAM-$code';
  }

  Future<FamilyModel> createFamily(String nbFamilia, String? dsFamilia) async {
    if (_currentUser == null) throw Exception("Usuario no autenticado");

    final createdCount = _userFamilies
        .where((f) => f.idCreador == _currentUser!.idUsuario)
        .length;
    if (createdCount >= 5) {
      throw Exception("maxFamiliesReachedErr");
    }

    final idFam = _uuid.v4();
    final clFam = _generateFamilyCode();

    final family = FamilyModel(
      idFamilia: idFam,
      idCreador: _currentUser!.idUsuario,
      nbFamilia: nbFamilia,
      clFamilia: clFam,
      dsFamilia: dsFamilia,
      fechaCreacion: DateTime.now(),
    );

    await _localDb.saveFamily(family);
    await MongoService.insertOne(
      collectionName: MongoConfig.colFamilia,
      document: family.toMap(),
    );

    _families.add(family);
    _userFamilies.add(family);
    await _localDb.saveFamilies(_userFamilies);
    PushNotificationService.subscribeToFamily(family.idFamilia);

    final userFamilyLink = UserFamilyModel(
      idUsuario: _currentUser!.idUsuario,
      idFamilia: idFam,
      fechaUnion: DateTime.now(),
      status: 'active',
    );
    await MongoService.insertOne(
      collectionName: MongoConfig.colUsuarioFamilia,
      document: userFamilyLink.toMap(),
    );

    _currentUser = _currentUser!.copyWith(idFamilia: idFam);
    await _localDb.saveUser(_currentUser!);
    await MongoService.updateOne(
      collectionName: MongoConfig.colUsuario,
      filter: {'id_usuario': _currentUser!.idUsuario},
      update: {
        '\$set': {'id_familia': idFam},
      },
    );

    final userIdx = _users.indexWhere(
      (u) => u.idUsuario == _currentUser!.idUsuario,
    );
    if (userIdx != -1) {
      _users[userIdx] = _currentUser!;
    }

    final superList = ShoppingListModel(
      idListaCompra: _uuid.v4(),
      idFamilia: idFam,
      nbLista: "Super",
      isDefault: true,
      isActive: true,
      isCompleted: false,
    );
    await _localDb.saveShoppingList(superList);
    await MongoService.insertOne(
      collectionName: MongoConfig.colListasCompra,
      document: superList.toMap(),
    );
    _shoppingLists.add(superList);

    await _seedDefaultCatalog(idFam);
    await fetchFamilyData();

    notifyListeners();
    return family;
  }

  Future<String> joinFamily(String clFamilia) async {
    if (_currentUser == null) throw Exception("Usuario no autenticado");

    final cleanCode = clFamilia.trim().toUpperCase();

    final remoteFamMap = await MongoService.findOne(
      collectionName: MongoConfig.colFamilia,
      filter: {'cl_familia': cleanCode},
    );

    FamilyModel? family;
    if (remoteFamMap != null) {
      family = FamilyModel.fromMap(remoteFamMap);
      await _localDb.saveFamily(family);
      final famIdx = _families.indexWhere(
        (f) => f.idFamilia == family!.idFamilia,
      );
      if (famIdx != -1) {
        _families[famIdx] = family;
      } else {
        _families.add(family);
      }
    } else {
      try {
        family = _families.firstWhere(
          (f) => f.clFamilia.toUpperCase() == cleanCode,
        );
      } catch (_) {
        return 'invalid_code';
      }
    }

    final joinedFamily = family;
    if (joinedFamily.idCreador == _currentUser!.idUsuario) {
      return 'already_creator';
    }

    final existingLink = await MongoService.findOne(
      collectionName: MongoConfig.colUsuarioFamilia,
      filter: {
        'id_usuario': _currentUser!.idUsuario,
        'id_familia': joinedFamily.idFamilia,
      },
    );

    final isAlreadyMemberInMemory = _userFamilies.any(
      (f) => f.idFamilia == joinedFamily.idFamilia,
    );

    if ((existingLink != null && existingLink['status'] != 'inactive') ||
        isAlreadyMemberInMemory) {
      return 'already_member';
    }

    if (existingLink != null && existingLink['status'] == 'inactive') {
      await MongoService.updateOne(
        collectionName: MongoConfig.colUsuarioFamilia,
        filter: {
          'id_usuario': _currentUser!.idUsuario,
          'id_familia': family.idFamilia,
        },
        update: {
          '\$set': {
            'status': 'active',
            'fecha_union': DateTime.now().toIso8601String(),
          },
        },
      );
    } else {
      final link = UserFamilyModel(
        idUsuario: _currentUser!.idUsuario,
        idFamilia: joinedFamily.idFamilia,
        fechaUnion: DateTime.now(),
        status: 'active',
      );
      await MongoService.insertOne(
        collectionName: MongoConfig.colUsuarioFamilia,
        document: link.toMap(),
      );
    }

    _currentUser = _currentUser!.copyWith(idFamilia: joinedFamily.idFamilia);
    await _localDb.saveUser(_currentUser!);

    await MongoService.updateOne(
      collectionName: MongoConfig.colUsuario,
      filter: {'id_usuario': _currentUser!.idUsuario},
      update: {
        '\$set': {'id_familia': joinedFamily.idFamilia},
      },
    );

    final userIdx = _users.indexWhere(
      (u) => u.idUsuario == _currentUser!.idUsuario,
    );
    if (userIdx != -1) {
      _users[userIdx] = _currentUser!;
    }

    if (!_userFamilies.any((f) => f.idFamilia == joinedFamily.idFamilia)) {
      _userFamilies.add(joinedFamily);
      await _localDb.saveFamilies(_userFamilies);
    }
    PushNotificationService.subscribeToFamily(joinedFamily.idFamilia);

    await fetchFamilyData();

    notifyListeners();
    return 'success';
  }

  Future<void> _seedDefaultCatalog(String idFamilia) async {
    final defaultItems = [
      {'es': 'Carne', 'en': 'Meat'},
      {'es': 'Leche', 'en': 'Milk'},
      {'es': 'Cereal', 'en': 'Cereal'},
      {'es': 'Queso', 'en': 'Cheese'},
      {'es': 'Pan', 'en': 'Bread'},
      {'es': 'Huevos', 'en': 'Eggs'},
      {'es': 'Frutas', 'en': 'Fruits'},
      {'es': 'Verduras', 'en': 'Vegetables'},
    ];

    final List<ItemCatalogModel> seeded = [];
    for (var item in defaultItems) {
      final catItem = ItemCatalogModel(
        idArticulo: _uuid.v4(),
        idFamilia: idFamilia,
        nbArticuloEs: item['es']!,
        nbArticuloEn: item['en']!,
      );
      await MongoService.insertOne(
        collectionName: MongoConfig.colCArticulo,
        document: catItem.toMap(),
      );
      seeded.add(catItem);
      _catalogItems.add(catItem);
    }
    await _localDb.saveCatalogItems(seeded, famId: idFamilia);
  }

  List<UserModel> getFamilyMembers() {
    final famId = _currentUser?.idFamilia;
    if (famId == null || famId.isEmpty) return [];
    final Map<String, UserModel> uniqueMembers = {};
    for (var u in _users) {
      if (u.idUsuario.isNotEmpty && u.idUsuario != 'usr_demo') {
        if (u.idFamilia == famId ||
            u.idUsuario == _currentUser?.idUsuario ||
            u.idUsuario == currentFamily?.idCreador) {
          uniqueMembers[u.idUsuario] = u;
        }
      }
    }
    return uniqueMembers.values.toList();
  }

  Future<void> removeFamilyMember(String idUsuario) async {
    final famId = _currentUser?.idFamilia;
    if (famId == null) return;

    await MongoService.updateOne(
      collectionName: MongoConfig.colUsuarioFamilia,
      filter: {'id_usuario': idUsuario, 'id_familia': famId},
      update: {
        '\$set': {'status': 'inactive'},
      },
    );

    await MongoService.updateOne(
      collectionName: MongoConfig.colUsuario,
      filter: {'id_usuario': idUsuario, 'id_familia': famId},
      update: {
        '\$unset': {'id_familia': ""},
      },
    );

    final userIdx = _users.indexWhere((u) => u.idUsuario == idUsuario);
    if (userIdx != -1) {
      final updatedUser = _users[userIdx].copyWith(clearFamilia: true);
      await _localDb.saveUser(updatedUser);
      _users.removeAt(userIdx);
    }

    await fetchFamilyData();
    notifyListeners();
  }

  // --- LISTAS DE COMPRAS ---
  List<ShoppingListModel> getActiveShoppingLists() {
    final famId = _currentUser?.idFamilia;
    if (famId == null) return [];

    final lists = _shoppingLists
        .where((l) => l.idFamilia == famId && l.isActive && !l.isCompleted)
        .toList();

    lists.sort((a, b) {
      if (a.isDefault) return -1;
      if (b.isDefault) return 1;
      return a.nbLista.toLowerCase().compareTo(b.nbLista.toLowerCase());
    });

    return lists;
  }

  Future<void> createOrReactivateList(String nbLista) async {
    await createNewList(nbLista);
  }

  /// Crea una NUEVA lista de compras limpia guardándola primero en SQLite (0ms latency UI)
  Future<void> createNewList(String nbLista) async {
    final famId = _currentUser?.idFamilia;
    if (famId == null) return;

    final trimmedName = nbLista.trim();
    if (trimmedName.isEmpty) return;

    final hasActiveList = _shoppingLists.any(
      (l) =>
          l.idFamilia == famId &&
          l.isActive &&
          !l.isCompleted &&
          l.nbLista.toLowerCase() == trimmedName.toLowerCase(),
    );

    if (hasActiveList) {
      throw Exception("LIST_ALREADY_EXISTS");
    }

    final newList = ShoppingListModel(
      idListaCompra: _uuid.v4(),
      idFamilia: famId,
      nbLista: trimmedName,
      isDefault: false,
      isActive: true,
      isCompleted: false,
    );

    // 1. Guardar en SQLite localmente de inmediato (0ms UI feedback)
    _syncService.recordLocalMutation(entityId: newList.idListaCompra, action: 'INSERT');
    await _localDb.saveShoppingList(newList, syncStatus: 'pending');
    _shoppingLists.add(newList);
    notifyListeners();

    // 2. Encolar en sync_queue para segundo plano
    await _localDb.enqueueSyncItem(
      collectionName: MongoConfig.colListasCompra,
      action: 'INSERT',
      entityId: newList.idListaCompra,
      payload: newList.toMap(),
    );
    _syncService.triggerSync();
  }

  bool hasPendingItems(String idListaCompra) {
    return _listDetailItems.any(
      (item) => item.idListaCompra == idListaCompra && item.isPending,
    );
  }

  Future<void> softDeleteShoppingList(String idListaCompra) async {
    final idx = _shoppingLists.indexWhere(
      (l) => l.idListaCompra == idListaCompra,
    );
    if (idx != -1) {
      final target = _shoppingLists[idx];
      if (target.isDefault) return;
      final updatedList = target.copyWith(isActive: false);
      _shoppingLists[idx] = updatedList;

      _syncService.recordLocalMutation(entityId: idListaCompra, action: 'DELETE');
      await _localDb.saveShoppingList(updatedList, syncStatus: 'pending');
      notifyListeners();

      await _localDb.enqueueSyncItem(
        collectionName: MongoConfig.colListasCompra,
        action: 'UPDATE',
        entityId: idListaCompra,
        payload: {'is_active': false},
      );
      _syncService.triggerSync();
    }
  }

  /// Finaliza toda la lista: marca todos los elementos como comprados y la lista como hecha
  Future<void> finishAndCompleteEntireList(String idListaCompra) async {
    final nowIso = DateTime.now().toIso8601String();
    final userId = _currentUser?.idUsuario;

    for (int i = 0; i < _listDetailItems.length; i++) {
      if (_listDetailItems[i].idListaCompra == idListaCompra &&
          _listDetailItems[i].isPending) {
        _incrementCatalogUsage(
          _listDetailItems[i].idArticulo,
          _listDetailItems[i].nbArticulo,
        );
        final updatedItem = _listDetailItems[i].copyWith(
          status: 'completed',
          fechaCompra: DateTime.now(),
          idUsuarioFinalizo: userId,
        );
        _listDetailItems[i] = updatedItem;
        await _localDb.saveListDetailItem(updatedItem, syncStatus: 'pending');

        await _localDb.enqueueSyncItem(
          collectionName: MongoConfig.colDetalleLista,
          action: 'UPDATE',
          entityId: updatedItem.idDetalle,
          payload: {
            'status': 'completed',
            'fecha_compra': nowIso,
            'id_usuario_finalizo': userId,
          },
        );
      }
    }

    final idx = _shoppingLists.indexWhere(
      (l) => l.idListaCompra == idListaCompra,
    );
    if (idx != -1) {
      final updatedList = _shoppingLists[idx].copyWith(isCompleted: true);
      _shoppingLists[idx] = updatedList;
      await _localDb.saveShoppingList(updatedList, syncStatus: 'pending');

      await _localDb.enqueueSyncItem(
        collectionName: MongoConfig.colListasCompra,
        action: 'UPDATE',
        entityId: idListaCompra,
        payload: {'is_completed': true},
      );
    }

    notifyListeners();
    _checkAndTriggerPurchaseNotification(idListaCompra);
    _syncService.triggerSync();
  }

  Future<bool> markListAsCompleted(String idListaCompra) async {
    if (hasPendingItems(idListaCompra)) {
      return false;
    }
    final idx = _shoppingLists.indexWhere(
      (l) => l.idListaCompra == idListaCompra,
    );
    if (idx != -1) {
      final updatedList = _shoppingLists[idx].copyWith(isCompleted: true);
      _shoppingLists[idx] = updatedList;
      await _localDb.saveShoppingList(updatedList, syncStatus: 'pending');

      await _localDb.enqueueSyncItem(
        collectionName: MongoConfig.colListasCompra,
        action: 'UPDATE',
        entityId: idListaCompra,
        payload: {'is_completed': true},
      );

      notifyListeners();
      _syncService.triggerSync();
      return true;
    }
    return false;
  }

  // --- DETALLE DE ARTÍCULOS ---
  List<ListDetailItemModel> getPendingItems(String idListaCompra) {
    final items = _listDetailItems
        .where((i) => i.idListaCompra == idListaCompra && i.isPending)
        .toList();
    items.sort((a, b) => a.nuOrder.compareTo(b.nuOrder));
    return items;
  }

  List<ListDetailItemModel> getCompletedItems(String idListaCompra) {
    return _listDetailItems
        .where((i) => i.idListaCompra == idListaCompra && i.isCompleted)
        .toList();
  }

  List<ItemCatalogModel> getCatalogItems() {
    final famId = _currentUser?.idFamilia;
    if (famId == null) return [];
    final items = _catalogItems.where((c) => c.idFamilia == famId).toList();
    items.sort((a, b) {
      final cmp = b.nuUso.compareTo(a.nuUso);
      if (cmp != 0) return cmp;
      return a.nbArticuloEs.toLowerCase().compareTo(
        b.nbArticuloEs.toLowerCase(),
      );
    });
    return items;
  }

  /// Actualiza el nombre de un artículo del catálogo rápido en SQLite, memoria RAM y Mongo Atlas
  Future<bool> updateCatalogItemName({
    required String idArticulo,
    required String newName,
  }) async {
    final cleanName = newName.trim();
    if (cleanName.isEmpty) return false;

    final idx = _catalogItems.indexWhere((c) => c.idArticulo == idArticulo);
    if (idx == -1) return false;

    final target = _catalogItems[idx];
    final updatedCatalog = target.copyWith(
      nbArticuloEs: cleanName,
      nbArticuloEn: cleanName,
    );

    _catalogItems[idx] = updatedCatalog;
    _syncService.recordLocalMutation(entityId: idArticulo, action: 'UPDATE');
    await _localDb.saveCatalogItem(updatedCatalog, syncStatus: 'pending');

    for (int i = 0; i < _listDetailItems.length; i++) {
      if (_listDetailItems[i].idArticulo == idArticulo) {
        final updatedDetail = _listDetailItems[i].copyWith(nbArticulo: cleanName);
        _listDetailItems[i] = updatedDetail;
        _syncService.recordLocalMutation(entityId: updatedDetail.idDetalle, action: 'UPDATE');
        await _localDb.saveListDetailItem(updatedDetail, syncStatus: 'pending');
        await _localDb.enqueueSyncItem(
          collectionName: MongoConfig.colDetalleLista,
          action: 'UPDATE',
          entityId: updatedDetail.idDetalle,
          payload: {'nb_articulo': cleanName},
        );
      }
    }

    notifyListeners();

    await _localDb.enqueueSyncItem(
      collectionName: MongoConfig.colCArticulo,
      action: 'UPDATE',
      entityId: idArticulo,
      payload: {
        'nb_articulo_es': cleanName,
        'nb_articulo_en': cleanName,
      },
    );

    await _syncService.syncNow();
    return true;
  }

  void _incrementCatalogUsage(String? idArticulo, String nbArticulo) {
    final famId = _currentUser?.idFamilia;
    if (famId == null) return;

    final cleanNameLower = nbArticulo.trim().toLowerCase();

    int idx = -1;
    if (idArticulo != null && idArticulo.isNotEmpty) {
      idx = _catalogItems.indexWhere((c) => c.idArticulo == idArticulo);
    }
    if (idx == -1) {
      idx = _catalogItems.indexWhere(
        (c) =>
            c.idFamilia == famId &&
            (c.nbArticuloEs.toLowerCase() == cleanNameLower ||
                c.nbArticuloEn.toLowerCase() == cleanNameLower),
      );
    }

    if (idx != -1) {
      final target = _catalogItems[idx];
      final updatedCatalog = target.copyWith(nuUso: target.nuUso + 1);
      _catalogItems[idx] = updatedCatalog;
      _syncService.recordLocalMutation(entityId: target.idArticulo, action: 'UPDATE');
      _localDb.saveCatalogItem(updatedCatalog, syncStatus: 'pending');

      _localDb.enqueueSyncItem(
        collectionName: MongoConfig.colCArticulo,
        action: 'UPDATE',
        entityId: target.idArticulo,
        payload: {'nu_uso': updatedCatalog.nuUso},
      );
    }
  }

  String getUserDisplayName(String? idUsuario) {
    if (idUsuario == null || idUsuario.isEmpty) return '';
    if (_currentUser != null && _currentUser!.idUsuario == idUsuario) {
      final username = _currentUser!.nbUsuario?.trim();
      if (username != null && username.isNotEmpty) {
        return username;
      }
      final name = _currentUser!.nbCompleto.trim();
      return name.contains(' ') ? name.split(' ').first : name;
    }
    try {
      final u = _users.firstWhere((user) => user.idUsuario == idUsuario);
      final username = u.nbUsuario?.trim();
      if (username != null && username.isNotEmpty) {
        return username;
      }
      final name = u.nbCompleto.trim();
      return name.contains(' ') ? name.split(' ').first : name;
    } catch (_) {
      return '';
    }
  }

  /// Añade un producto a la lista con guardado instantáneo en SQLite (0ms UI latency)
  Future<bool> addItemToList({
    required String idListaCompra,
    required String idArticulo,
    required String nbArticulo,
    String? dsDetalle,
  }) async {
    final cleanName = nbArticulo.trim();
    if (cleanName.isEmpty) return false;

    final cleanNameLower = cleanName.toLowerCase();

    // 1. Verificar si ya existe un elemento ACTIVO/PENDIENTE con este nombre
    final activeExistingIdx = _listDetailItems.indexWhere(
      (i) =>
          i.idListaCompra == idListaCompra &&
          i.isPending &&
          (i.nbArticulo.trim().toLowerCase() == cleanNameLower ||
              (idArticulo.isNotEmpty &&
                  i.idArticulo.isNotEmpty &&
                  i.idArticulo == idArticulo)),
    );

    if (activeExistingIdx != -1) {
      return false;
    }

    // 2. Verificar si existía un elemento COMPLETADO (comprado previamente)
    final completedExistingIdx = _listDetailItems.indexWhere(
      (i) =>
          i.idListaCompra == idListaCompra &&
          i.isCompleted &&
          (i.nbArticulo.trim().toLowerCase() == cleanNameLower ||
              (idArticulo.isNotEmpty &&
                  i.idArticulo.isNotEmpty &&
                  i.idArticulo == idArticulo)),
    );

    if (completedExistingIdx != -1) {
      final existingItem = _listDetailItems[completedExistingIdx];
      final cleanDsDetalle = dsDetalle?.trim();
      final currentPendingCount = _listDetailItems
          .where((i) => i.idListaCompra == idListaCompra && i.isPending)
          .length;

      final now = DateTime.now();
      final reactivatedItem = existingItem.copyWith(
        status: 'pending',
        fechaCompra: null,
        fechaAgrego: now,
        idUsuarioAgrego: _currentUser?.idUsuario,
        dsDetalle: cleanDsDetalle,
        clearDsDetalle: cleanDsDetalle == null || cleanDsDetalle.isEmpty,
        nuOrder: currentPendingCount,
      );

      _listDetailItems.removeAt(completedExistingIdx);
      _listDetailItems.add(reactivatedItem);
      _syncService.recordLocalMutation(entityId: reactivatedItem.idDetalle, action: 'UPDATE');
      await _localDb.saveListDetailItem(reactivatedItem, syncStatus: 'pending');
      notifyListeners();

      await _localDb.enqueueSyncItem(
        collectionName: MongoConfig.colDetalleLista,
        action: 'UPDATE',
        entityId: reactivatedItem.idDetalle,
        payload: {
          'status': 'pending',
          'id_usuario_agrego': reactivatedItem.idUsuarioAgrego,
          'fecha_agrego': reactivatedItem.fechaAgrego?.toIso8601String(),
          'ds_detalle': reactivatedItem.dsDetalle,
          'nu_order': reactivatedItem.nuOrder,
        },
      );

      _checkAndTriggerListNotification(idListaCompra);
      _syncService.triggerSync(delay: Duration.zero);
      return true;
    }

    // 3. Crear nuevo elemento
    final currentPendingCount = _listDetailItems
        .where((i) => i.idListaCompra == idListaCompra && i.isPending)
        .length;

    final newItem = ListDetailItemModel(
      idDetalle: _uuid.v4(),
      idListaCompra: idListaCompra,
      idArticulo: idArticulo,
      nbArticulo: cleanName,
      dsDetalle: dsDetalle,
      status: 'pending',
      fechaAgrego: DateTime.now(),
      idUsuarioAgrego: _currentUser?.idUsuario,
      nuOrder: currentPendingCount,
    );

    // Agregar DE INMEDIATO en SQLite y en memoria local (0ms UI latency)
    _listDetailItems.add(newItem);
    _syncService.recordLocalMutation(entityId: newItem.idDetalle, action: 'INSERT');
    await _localDb.saveListDetailItem(newItem, syncStatus: 'pending');
    notifyListeners();

    // Encolar en sync_queue para segundo plano
    await _localDb.enqueueSyncItem(
      collectionName: MongoConfig.colDetalleLista,
      action: 'INSERT',
      entityId: newItem.idDetalle,
      payload: newItem.toMap(),
    );

    _checkAndTriggerListNotification(idListaCompra);
    _syncService.triggerSync(delay: Duration.zero);
    return true;
  }

  Future<void> _checkAndTriggerListNotification(String idListaCompra) async {
    final famId = _currentUser?.idFamilia;
    final userId = _currentUser?.idUsuario;
    if (famId == null || userId == null) return;

    final listIdx = _shoppingLists.indexWhere(
      (l) => l.idListaCompra == idListaCompra,
    );
    if (listIdx == -1) return;

    final targetList = _shoppingLists[listIdx];
    final lastNotif = targetList.feUltimaNotificacion;
    final now = DateTime.now();

    final canSendNotification =
        lastNotif == null ||
        now.difference(lastNotif) >=
            NotificationConfig.listNotificationCooldown;

    if (!canSendNotification) return;

    _shoppingLists[listIdx] = targetList.copyWith(feUltimaNotificacion: now);
    await _localDb.saveShoppingList(_shoppingLists[listIdx]);

    MongoService.updateOne(
      collectionName: MongoConfig.colListasCompra,
      filter: {'id_lista_compra': idListaCompra},
      update: {
        '\$set': {'fe_ultima_notificacion': now.toIso8601String()},
      },
    );

    final listFamId = targetList.idFamilia.isNotEmpty
        ? targetList.idFamilia
        : famId;
    final familyName = getFamilyName(listFamId);

    final senderName = getUserDisplayName(userId);
    PushNotificationService.sendListProductsAddedNotification(
      idFamilia: listFamId,
      nbFamilia: familyName,
      idListaCompra: idListaCompra,
      nbLista: targetList.nbLista,
      senderUserId: userId,
      senderName: senderName.isNotEmpty ? senderName : 'Un integrante',
    );
  }

  /// Verifica el cooldown de 10 minutos para notificación de marcación como comprado
  Future<void> _checkAndTriggerPurchaseNotification(
    String idListaCompra, {
    String? productName,
  }) async {
    final famId = _currentUser?.idFamilia;
    final userId = _currentUser?.idUsuario;
    if (famId == null || userId == null) return;

    final listIdx = _shoppingLists.indexWhere(
      (l) => l.idListaCompra == idListaCompra,
    );
    if (listIdx == -1) return;

    final targetList = _shoppingLists[listIdx];
    final lastNotif = targetList.feUltimaNotificacionCompra;
    final now = DateTime.now();

    final canSendNotification =
        lastNotif == null ||
        now.difference(lastNotif) >=
            NotificationConfig.listNotificationCooldown;

    if (!canSendNotification) {
      final elapsedMin = now.difference(lastNotif).inMinutes;
      debugPrint(
        "[PUSH_NOTIF LOG] Cooldown de COMPRA ACTIVO en lista '${targetList.nbLista}'. "
        "Transcurridos: $elapsedMin min (Requiere >= ${NotificationConfig.listNotificationCooldown.inMinutes} min). Omitiendo push.",
      );
      return;
    }

    debugPrint(
      "[PUSH_NOTIF LOG] Cooldown CUMPLIDO en lista '${targetList.nbLista}' para compra. Disparando notificación push...",
    );

    _shoppingLists[listIdx] = targetList.copyWith(
      feUltimaNotificacionCompra: now,
    );
    await _localDb.saveShoppingList(_shoppingLists[listIdx]);

    MongoService.updateOne(
      collectionName: MongoConfig.colListasCompra,
      filter: {'id_lista_compra': idListaCompra},
      update: {
        '\$set': {'fe_ultima_notificacion_compra': now.toIso8601String()},
      },
    );

    final listFamId = targetList.idFamilia.isNotEmpty
        ? targetList.idFamilia
        : famId;
    final familyName = getFamilyName(listFamId);

    final senderName = getUserDisplayName(userId);
    PushNotificationService.sendListProductsPurchasedNotification(
      idFamilia: listFamId,
      nbFamilia: familyName,
      idListaCompra: idListaCompra,
      nbLista: targetList.nbLista,
      senderUserId: userId,
      senderName: senderName.isNotEmpty ? senderName : 'Un integrante',
      productName: productName,
    );
  }

  Future<bool> addCustomItemToCatalogAndList({
    required String idListaCompra,
    required String nbArticulo,
    String? dsDetalle,
  }) async {
    final famId = _currentUser?.idFamilia;
    if (famId == null) return false;

    final cleanName = nbArticulo.trim();
    if (cleanName.isEmpty) return false;

    final cleanNameLower = cleanName.toLowerCase();

    final alreadyPending = _listDetailItems.any(
      (i) =>
          i.idListaCompra == idListaCompra &&
          i.isPending &&
          i.nbArticulo.trim().toLowerCase() == cleanNameLower,
    );

    if (alreadyPending) return false;

    final familyCatalog = getCatalogItems();
    final existingIdx = familyCatalog.indexWhere(
      (c) =>
          c.nbArticuloEs.toLowerCase() == cleanNameLower ||
          c.nbArticuloEn.toLowerCase() == cleanNameLower,
    );

    if (existingIdx != -1) {
      final existingArt = familyCatalog[existingIdx];
      return await addItemToList(
        idListaCompra: idListaCompra,
        idArticulo: existingArt.idArticulo,
        nbArticulo: cleanName,
        dsDetalle: dsDetalle,
      );
    } else {
      final artId = _uuid.v4();
      final newCatalogItem = ItemCatalogModel(
        idArticulo: artId,
        idFamilia: famId,
        nbArticuloEs: cleanName,
        nbArticuloEn: cleanName,
      );

      _catalogItems.add(newCatalogItem);
      _syncService.recordLocalMutation(entityId: artId, action: 'INSERT');
      await _localDb.saveCatalogItem(newCatalogItem, syncStatus: 'pending');

      await _localDb.enqueueSyncItem(
        collectionName: MongoConfig.colCArticulo,
        action: 'INSERT',
        entityId: artId,
        payload: newCatalogItem.toMap(),
      );

      return await addItemToList(
        idListaCompra: idListaCompra,
        idArticulo: artId,
        nbArticulo: cleanName,
        dsDetalle: dsDetalle,
      );
    }
  }

  Future<void> updateItemDetailNote(String idDetalle, String? dsDetalle) async {
    final cleanNote = dsDetalle?.trim();
    final idx = _listDetailItems.indexWhere((i) => i.idDetalle == idDetalle);
    if (idx != -1) {
      final updated = (cleanNote == null || cleanNote.isEmpty)
          ? _listDetailItems[idx].copyWith(clearDsDetalle: true)
          : _listDetailItems[idx].copyWith(dsDetalle: cleanNote);

      _listDetailItems[idx] = updated;
      _syncService.recordLocalMutation(entityId: idDetalle, action: 'UPDATE');
      await _localDb.saveListDetailItem(updated, syncStatus: 'pending');
      notifyListeners();

      await _localDb.enqueueSyncItem(
        collectionName: MongoConfig.colDetalleLista,
        action: 'UPDATE',
        entityId: idDetalle,
        payload: {'ds_detalle': cleanNote},
      );
      _syncService.triggerSync(delay: Duration.zero);
    }
  }

  Future<void> removeListDetailItem(String idDetalle) async {
    _syncService.recordLocalMutation(entityId: idDetalle, action: 'DELETE');
    _listDetailItems.removeWhere((item) => item.idDetalle == idDetalle);
    await _localDb.deleteListDetailItemLocally(idDetalle);
    notifyListeners();

    await _localDb.enqueueSyncItem(
      collectionName: MongoConfig.colDetalleLista,
      action: 'DELETE',
      entityId: idDetalle,
      payload: {'id_detalle': idDetalle},
    );
    _syncService.triggerSync(delay: Duration.zero);
  }

  Future<void> markItemAsCompleted(String idDetalle) async {
    final idx = _listDetailItems.indexWhere((i) => i.idDetalle == idDetalle);
    if (idx != -1) {
      final updated = _listDetailItems[idx].copyWith(
        status: 'completed',
        fechaCompra: DateTime.now(),
        idUsuarioFinalizo: _currentUser?.idUsuario,
      );
      _listDetailItems[idx] = updated;
      _incrementCatalogUsage(updated.idArticulo, updated.nbArticulo);
      _syncService.recordLocalMutation(entityId: idDetalle, action: 'UPDATE');
      await _localDb.saveListDetailItem(updated, syncStatus: 'pending');
      notifyListeners();

      await _localDb.enqueueSyncItem(
        collectionName: MongoConfig.colDetalleLista,
        action: 'UPDATE',
        entityId: idDetalle,
        payload: {
          'status': 'completed',
          'fecha_compra': updated.fechaCompra?.toIso8601String(),
          'id_usuario_finalizo': updated.idUsuarioFinalizo,
        },
      );
      _checkAndTriggerPurchaseNotification(
        updated.idListaCompra,
        productName: updated.nbArticulo,
      );
      _syncService.triggerSync(delay: Duration.zero);
    }
  }

  Future<void> unmarkItemAsCompleted(String idDetalle) async {
    final idx = _listDetailItems.indexWhere((i) => i.idDetalle == idDetalle);
    if (idx != -1) {
      final updated = _listDetailItems[idx].copyWith(
        status: 'pending',
        clearFechaCompra: true,
        clearIdUsuarioFinalizo: true,
      );
      _listDetailItems[idx] = updated;
      _syncService.recordLocalMutation(entityId: idDetalle, action: 'UPDATE');
      await _localDb.saveListDetailItem(updated, syncStatus: 'pending');
      notifyListeners();

      await _localDb.enqueueSyncItem(
        collectionName: MongoConfig.colDetalleLista,
        action: 'UPDATE',
        entityId: idDetalle,
        payload: {
          'status': 'pending',
          'fecha_compra': null,
          'id_usuario_finalizo': null,
        },
      );
      _syncService.triggerSync(delay: const Duration(seconds: 1));
    }
  }

  Future<void> reorderPendingItems(
    String idListaCompra,
    int oldIndex,
    int newIndex,
  ) async {
    final pendingList = getPendingItems(idListaCompra);
    if (oldIndex < 0 || oldIndex >= pendingList.length) return;
    if (newIndex < 0 || newIndex > pendingList.length) return;

    final itemToMove = pendingList.removeAt(oldIndex);
    pendingList.insert(newIndex, itemToMove);

    final List<ListDetailItemModel> updatedItems = [];

    for (int i = 0; i < pendingList.length; i++) {
      final originalItem = pendingList[i];
      final updatedItem = originalItem.copyWith(nuOrder: i);
      updatedItems.add(updatedItem);

      final idxInMemory = _listDetailItems.indexWhere(
        (x) => x.idDetalle == originalItem.idDetalle,
      );
      if (idxInMemory != -1) {
        _listDetailItems[idxInMemory] = updatedItem;
      }
      _syncService.recordLocalMutation(entityId: updatedItem.idDetalle, action: 'UPDATE');
    }

    notifyListeners();

    await _localDb.saveListDetailItemsBatch(updatedItems);

    for (var updated in updatedItems) {
      await _localDb.enqueueSyncItem(
        collectionName: MongoConfig.colDetalleLista,
        action: 'UPDATE',
        entityId: updated.idDetalle,
        payload: {'nu_order': updated.nuOrder},
      );
    }

    _syncService.triggerSync(delay: Duration.zero);
  }

  /// Reordena los elementos pendientes por orden alfabético y persiste el nuevo orden en SQLite y MongoDB
  Future<void> saveAlphabeticalOrder(
    String idListaCompra, {
    bool ascending = true,
  }) async {
    final pendingList = getPendingItems(idListaCompra);
    if (pendingList.isEmpty) return;

    pendingList.sort((a, b) {
      final cmp = a.nbArticulo.toLowerCase().compareTo(b.nbArticulo.toLowerCase());
      return ascending ? cmp : -cmp;
    });

    final List<ListDetailItemModel> updatedItems = [];
    for (int i = 0; i < pendingList.length; i++) {
      final originalItem = pendingList[i];
      if (originalItem.nuOrder != i) {
        final updatedItem = originalItem.copyWith(nuOrder: i);
        updatedItems.add(updatedItem);

        final idxInMemory = _listDetailItems.indexWhere(
          (x) => x.idDetalle == originalItem.idDetalle,
        );
        if (idxInMemory != -1) {
          _listDetailItems[idxInMemory] = updatedItem;
        }
        _syncService.recordLocalMutation(entityId: updatedItem.idDetalle, action: 'UPDATE');
      }
    }

    if (updatedItems.isEmpty) return;

    notifyListeners();

    await _localDb.saveListDetailItemsBatch(updatedItems);

    for (var updated in updatedItems) {
      await _localDb.enqueueSyncItem(
        collectionName: MongoConfig.colDetalleLista,
        action: 'UPDATE',
        entityId: updated.idDetalle,
        payload: {'nu_order': updated.nuOrder},
      );
    }
    _syncService.triggerSync(delay: Duration.zero);
  }
}
