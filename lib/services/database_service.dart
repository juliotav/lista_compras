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

  final List<UserModel> _users = [];
  final List<FamilyModel> _families = [];
  final List<FamilyModel> _userFamilies = [];
  List<FamilyModel> get userFamilies => List.unmodifiable(_userFamilies);

  final List<ShoppingListModel> _shoppingLists = [];
  List<ShoppingListModel> get shoppingLists => List.unmodifiable(_shoppingLists);
  final List<ItemCatalogModel> _catalogItems = [];
  final List<ListDetailItemModel> _listDetailItems = [];

  final bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  bool _isBackgroundSyncing = false;
  bool get isBackgroundSyncing => _isBackgroundSyncing;

  void _startBackgroundSync() {
    if (!_isBackgroundSyncing) {
      _isBackgroundSyncing = true;
      notifyListeners();
    }
  }

  void _stopBackgroundSync() {
    if (_isBackgroundSyncing) {
      _isBackgroundSyncing = false;
      notifyListeners();
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
    if (_currentUser?.idFamilia == null) return null;
    try {
      return _families.firstWhere((f) => f.idFamilia == _currentUser!.idFamilia);
    } catch (_) {
      return null;
    }
  }

  DatabaseService() {
    _initSeedData();
    initSession();
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
          await _loadFromLocalDb(_currentUser!.idFamilia!);
        }

        if (_currentUser != null) {
          await _localDb.saveSessionUserId(_currentUser!.idUsuario);
          _checkAndUpdateUserAppVersion(_currentUser!);
        }

        // Consultar usuario en MongoDB de fondo
        unawaited(() async {
          try {
            final remoteUser = await MongoService.findOne(
              collectionName: MongoConfig.colUsuario,
              filter: {'id_usuario': savedUserId},
            );
            if (remoteUser != null) {
              _currentUser = UserModel.fromMap(remoteUser);
              await _localDb.saveUser(_currentUser!);
              final uIdx = _users.indexWhere((u) => u.idUsuario == _currentUser!.idUsuario);
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
              PushNotificationService.subscribeToFamily(_currentUser!.idFamilia);
              await fetchFamilyData();
            }
          } catch (e) {
            debugPrint("[DB_SERVICE LOG] Error en consulta background de initSession: $e");
          }
        }());
      }
    } catch (e) {
      debugPrint("[DB_SERVICE LOG] Error cargando sesión local: $e");
    } finally {
      _isInitialized = true;
      notifyListeners();
      unawaited(checkAppVersion());
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
  /// Si la versión almacenada es estrictamente mayor que `MongoConfig.appVersion`, requiere actualización obligatoria.
  Future<void> checkAppVersion() async {
    try {
      final doc = await MongoService.findOne(
        collectionName: MongoConfig.colAppVersion,
        filter: {'app_name': MongoConfig.appName},
      );
      if (doc != null && doc.containsKey('app_version')) {
        final remoteVer = (doc['app_version'] as String?)?.trim();
        _remoteAppVersion = remoteVer;
        if (remoteVer != null && remoteVer.isNotEmpty) {
          final localVer = MongoConfig.appVersion.trim();
          if (_compareVersions(localVer, remoteVer) < 0) {
            debugPrint("[VERSION CHECK] ¡Versión de la app ($localVer) es menor a la versión requerida de la BD ($remoteVer)!");
            _isUpdateRequired = true;
            notifyListeners();
            return;
          }
        }
      }
      _isUpdateRequired = false;
      notifyListeners();
    } catch (e) {
      debugPrint("[VERSION CHECK LOG] Error al consultar app_version en MongoDB: $e");
    }
  }

  /// Verifica si la versión de la app difiere de la registrada en el perfil del usuario.
  /// Si es diferente, actualiza ds_version_app en MongoDB Atlas y SQLite. Si es igual, omite llamadas de red (0 over-fetching).
  Future<void> _checkAndUpdateUserAppVersion(UserModel user) async {
    final currentAppVer = MongoConfig.appVersion;
    if (user.dsVersionApp != currentAppVer) {
      debugPrint("[VERSION CHECK] Actualizando versión registrada del usuario '${user.idUsuario}' de '${user.dsVersionApp}' a '$currentAppVer'...");
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
          '\$set': {'ds_version_app': currentAppVer}
        },
      );
    }
  }

  /// Carga instantáneamente desde SQLite las listas, catálogo y productos guardados localmente
  Future<void> _loadFromLocalDb(String famId) async {
    try {
      final localLists = await _localDb.getShoppingLists(famId);
      _shoppingLists.clear();
      _shoppingLists.addAll(localLists);

      final localCatalog = await _localDb.getCatalogItems(famId);
      _catalogItems.removeWhere((c) => c.idFamilia == famId);
      _catalogItems.addAll(localCatalog);

      final activeListIds = _shoppingLists.map((l) => l.idListaCompra).toList();
      final localDetails = await _localDb.getAllListDetailsForFamily(activeListIds);
      _listDetailItems.clear();
      _listDetailItems.addAll(localDetails);

      final localFamilies = await _localDb.getFamilies();
      _families.clear();
      _families.addAll(localFamilies);
      _userFamilies.clear();
      _userFamilies.addAll(localFamilies);

      final localUsers = await _localDb.getAllUsers();
      for (var u in localUsers) {
        final idx = _users.indexWhere((existing) => existing.idUsuario == u.idUsuario);
        if (idx == -1) {
          _users.add(u);
        } else {
          _users[idx] = u;
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint("[DB_SERVICE LOG] Error cargando de SQLite: $e");
    }
  }

  /// Carga instantáneamente desde SQLite los datos locales de la familia sin peticiones de red
  Future<void> loadLocalDataOnly() async {
    final famId = _currentUser?.idFamilia;
    if (famId != null && famId.isNotEmpty) {
      await _loadFromLocalDb(famId);
    }
  }

  /// Reanudación desde segundo plano: Carga SQLite de inmediato y dispara delta sync no bloqueante
  Future<void> onAppResume() async {
    unawaited(checkAppVersion());
    final famId = _currentUser?.idFamilia;
    if (famId != null && famId.isNotEmpty) {
      debugPrint("[DB_SERVICE LOG] App reanudada. Cargando SQLite de inmediato...");
      await _loadFromLocalDb(famId);
      _startBackgroundSync();
      try {
        await _syncService.pullDeltaSync(
          famId: famId,
          onDataUpdated: () async {
            await _loadFromLocalDb(famId);
          },
        );
      } finally {
        _stopBackgroundSync();
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
        filter: {'id_usuario': userId},
      );

      final Set<String> knownFamIds = userFamDocs
          .map((doc) => doc['id_familia'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toSet();

      final createdFamDocs = await MongoService.find(
        collectionName: MongoConfig.colFamilia,
        filter: {'id_creador': userId},
      );

      for (var famDoc in createdFamDocs) {
        final famId = famDoc['id_familia'] as String?;
        if (famId != null && famId.isNotEmpty && !knownFamIds.contains(famId)) {
          final newLink = UserFamilyModel(
            idUsuario: userId,
            idFamilia: famId,
            fechaUnion: DateTime.now(),
          );
          await MongoService.insertOne(
            collectionName: MongoConfig.colUsuarioFamilia,
            document: newLink.toMap(),
          );
          knownFamIds.add(famId);
        }
      }

      if (_currentUser?.idFamilia != null &&
          _currentUser!.idFamilia!.isNotEmpty &&
          !knownFamIds.contains(_currentUser!.idFamilia!)) {
        final activeFamId = _currentUser!.idFamilia!;
        final newLink = UserFamilyModel(
          idUsuario: userId,
          idFamilia: activeFamId,
          fechaUnion: DateTime.now(),
        );
        await MongoService.insertOne(
          collectionName: MongoConfig.colUsuarioFamilia,
          document: newLink.toMap(),
        );
        knownFamIds.add(activeFamId);
      }

      final List<FamilyModel> loadedFamilies = [];
      for (var famId in knownFamIds) {
        final famDocs = await MongoService.find(
          collectionName: MongoConfig.colFamilia,
          filter: {'id_familia': famId},
        );
        if (famDocs.isNotEmpty) {
          loadedFamilies.add(FamilyModel.fromMap(famDocs.first));
        }
      }

      _userFamilies.clear();
      _userFamilies.addAll(loadedFamilies);
      await _localDb.saveFamilies(loadedFamilies);

      if ((_currentUser?.idFamilia == null ||
              !_userFamilies.any((f) => f.idFamilia == _currentUser!.idFamilia)) &&
          _userFamilies.isNotEmpty) {
        final activeFamId = _userFamilies.first.idFamilia;
        _currentUser = _currentUser!.copyWith(idFamilia: activeFamId);
        if (_currentUser != null) {
          await _localDb.saveUser(_currentUser!);
        }
        await MongoService.updateOne(
          collectionName: MongoConfig.colUsuario,
          filter: {'id_usuario': userId},
          update: {
            '\$set': {'id_familia': activeFamId}
          },
        );
      }
      await cleanOrphanCatalogItems();
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
      final validFamIds = allFamilies.map((f) => f['id_familia'] as String).toSet();

      final allCatalogDocs = await MongoService.find(
        collectionName: MongoConfig.colCArticulo,
        filter: {},
      );
      for (var doc in allCatalogDocs) {
        final famId = doc['id_familia'] as String?;
        if (famId != null && famId.isNotEmpty && !validFamIds.contains(famId)) {
          debugPrint("[DB_SERVICE LOG] Limpiando automáticamente artículos huérfanos en c_articulo de la familia eliminada '$famId'...");
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

  /// Sincroniza en segundo plano todos los datos de la familia sin bloquear la UI ni borrar datos locales
  Future<void> fetchFamilyData({bool isSilentPeriodic = false}) async {
    final userId = _currentUser?.idUsuario;
    if (userId == null) return;

    if (!isSilentPeriodic) {
      _startBackgroundSync();
    }

    if (_isFetchingFamilyData) return;
    _isFetchingFamilyData = true;

    try {
      // 1. Cargar estado de SQLite de inmediato si ya se cuenta con idFamilia (0ms delay UI)
      final initialFamId = _currentUser?.idFamilia;
      if (initialFamId != null && initialFamId.isNotEmpty) {
        await _loadFromLocalDb(initialFamId);
      }

      // 2. Buscar y sincronizar las familias del usuario desde MongoDB Atlas
      await fetchUserFamilies();

      final famId = _currentUser?.idFamilia;
      if (famId == null || famId.isEmpty) {
        return;
      }

      // 3. Volver a recargar de SQLite si la familia cambió tras consultar el servidor
      await _loadFromLocalDb(famId);

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
          filter: {'id_familia': famId},
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

        for (var mId in memberIds) {
          final userDoc = await MongoService.findOne(
            collectionName: MongoConfig.colUsuario,
            filter: {'id_usuario': mId},
          );
          if (userDoc != null) {
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
      } catch (e) {
        debugPrint("[DB_SERVICE LOG] Error sincronizando integrantes de familia: $e");
      }

      // 3. Disparar sincronización delta en segundo plano
      await _syncService.pullDeltaSync(
        famId: famId,
        onDataUpdated: () async {
          await _loadFromLocalDb(famId);
        },
      );
    } catch (e) {
      debugPrint("[DB_SERVICE LOG] Error en fetchFamilyData: $e");
    } finally {
      _isFetchingFamilyData = false;
      _stopBackgroundSync();
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

    final remoteUser = await MongoService.findOne(
      collectionName: MongoConfig.colUsuario,
      filter: {'nb_email': cleanEmail},
    );

    if (remoteUser != null || _users.any((u) => u.nbEmail.toLowerCase() == cleanEmail)) {
      throw Exception("El correo electrónico ya está registrado.");
    }

    final passHash = SecurityService.hashPassword(cleanPass);
    final newUser = UserModel(
      idUsuario: _uuid.v4(),
      nbCompleto: nbCompleto.trim(),
      nbUsuario: cleanUsername?.isEmpty == true ? null : cleanUsername,
      nbEmail: cleanEmail,
      clPass: passHash,
      dsVersionApp: MongoConfig.appVersion,
    );

    await MongoService.insertOne(
      collectionName: MongoConfig.colUsuario,
      document: newUser.toMap(),
    );

    _users.add(newUser);
    _currentUser = newUser;
    await _localDb.saveUser(newUser);
    await _localDb.saveSessionUserId(newUser.idUsuario);

    if (_currentUser?.idFamilia != null) {
      await fetchFamilyData();
    }

    notifyListeners();
    return true;
  }

  Future<bool> loginUser(String emailOrUsername, String password) async {
    final cleanInput = emailOrUsername.trim().toLowerCase();
    final cleanPass = password.trim();
    final passHash = SecurityService.hashPassword(cleanPass);

    final escapedInput = RegExp.escape(cleanInput);

    Map<String, dynamic>? remoteUserMap = await MongoService.findOne(
      collectionName: MongoConfig.colUsuario,
      filter: {
        'nb_email': {r'$regex': '^$escapedInput\$', r'$options': 'i'}
      },
    );

    remoteUserMap ??= await MongoService.findOne(
      collectionName: MongoConfig.colUsuario,
      filter: {
        'nb_usuario': {r'$regex': '^$escapedInput\$', r'$options': 'i'}
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
                (u.nbUsuario != null && u.nbUsuario!.toLowerCase() == cleanInput)) &&
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
    _currentUser = null;
    await _localDb.clearSession();
    _shoppingLists.clear();
    _listDetailItems.clear();
    _catalogItems.clear();
    notifyListeners();
  }

  // --- RECUPERACIÓN DE CONTRASEÑA ---
  Future<Map<String, dynamic>> requestPasswordReset(String emailOrUsername) async {
    final cleanInput = emailOrUsername.trim().toLowerCase();
    if (cleanInput.isEmpty) {
      return {'success': false, 'message': 'invalidEmail'};
    }

    final escapedInput = RegExp.escape(cleanInput);

    Map<String, dynamic>? userMap = await MongoService.findOne(
      collectionName: MongoConfig.colUsuario,
      filter: {
        'nb_email': {r'$regex': '^$escapedInput\$', r'$options': 'i'}
      },
    );

    userMap ??= await MongoService.findOne(
      collectionName: MongoConfig.colUsuario,
      filter: {
        'nb_usuario': {r'$regex': '^$escapedInput\$', r'$options': 'i'}
      },
    );

    if (userMap == null) {
      return {'success': true, 'email': cleanInput, 'userExists': false};
    }

    final targetEmail = (userMap['nb_email'] as String).toLowerCase();
    final rnd = Random();
    final pinCode = (100000 + rnd.nextInt(900000)).toString();
    final pinHash = SecurityService.hashPassword(pinCode);
    final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 10)).toIso8601String();

    await MongoService.updateOne(
      collectionName: MongoConfig.colUsuario,
      filter: {'id_usuario': userMap['id_usuario']},
      update: {
        '\$set': {
          'cd_reset_pin': pinHash,
          'fh_reset_expires': expiresAt,
        }
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
        'nb_email': {r'$regex': '^$escapedEmail\$', r'$options': 'i'}
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

  Future<bool> resetPasswordWithPin(String email, String pinCode, String newPassword) async {
    final isValid = await verifyResetPin(email, pinCode);
    if (!isValid) return false;

    final cleanEmail = email.trim().toLowerCase();
    final newPassHash = SecurityService.hashPassword(newPassword.trim());
    final escapedEmail = RegExp.escape(cleanEmail);

    final success = await MongoService.updateOne(
      collectionName: MongoConfig.colUsuario,
      filter: {
        'nb_email': {r'$regex': '^$escapedEmail\$', r'$options': 'i'}
      },
      update: {
        '\$set': {'cl_pass': newPassHash},
        '\$unset': {'cd_reset_pin': '', 'fh_reset_expires': ''}
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

    await MongoService.updateOne(
      collectionName: MongoConfig.colUsuario,
      filter: {'id_usuario': _currentUser!.idUsuario},
      update: {
        '\$set': {'id_familia': idFamilia}
      },
    );

    await fetchFamilyData();
    PushNotificationService.subscribeToFamily(idFamilia);
  }

  Future<void> leaveFamily(String idFamilia) async {
    final userId = _currentUser?.idUsuario;
    if (userId == null) return;

    await MongoService.deleteOne(
      collectionName: MongoConfig.colUsuarioFamilia,
      filter: {
        'id_usuario': userId,
        'id_familia': idFamilia,
      },
    );

    _userFamilies.removeWhere((f) => f.idFamilia == idFamilia);

    if (_currentUser?.idFamilia == idFamilia) {
      if (_userFamilies.isNotEmpty) {
        final newActiveFamId = _userFamilies.first.idFamilia;
        _currentUser = _currentUser!.copyWith(idFamilia: newActiveFamId);
        await _localDb.saveUser(_currentUser!);
        await MongoService.updateOne(
          collectionName: MongoConfig.colUsuario,
          filter: {'id_usuario': userId},
          update: {
            '\$set': {'id_familia': newActiveFamId}
          },
        );
      } else {
        _currentUser = _currentUser!.copyWith(clearFamilia: true);
        await MongoService.updateOne(
          collectionName: MongoConfig.colUsuario,
          filter: {'id_usuario': userId},
          update: {
            '\$unset': {'id_familia': ""}
          },
        );
      }
    }

    await fetchFamilyData();
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
      final familyListIds = familyListDocs.map((l) => l['id_lista_compra'] as String).toList();

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
              '\$set': {'id_familia': newActiveId}
            },
          );
        } else {
          _currentUser = _currentUser!.copyWith(clearFamilia: true);
          await MongoService.updateOne(
            collectionName: MongoConfig.colUsuario,
            filter: {'id_usuario': userId},
            update: {
              '\$unset': {'id_familia': ""}
            },
          );
        }
      }

      await fetchFamilyData();
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
    final code = List.generate(5, (_) => chars[rnd.nextInt(chars.length)]).join();
    return 'FAM-$code';
  }

  Future<FamilyModel> createFamily(String nbFamilia, String? dsFamilia) async {
    if (_currentUser == null) throw Exception("Usuario no autenticado");

    final createdCount = _userFamilies.where((f) => f.idCreador == _currentUser!.idUsuario).length;
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

    final userFamilyLink = UserFamilyModel(
      idUsuario: _currentUser!.idUsuario,
      idFamilia: idFam,
      fechaUnion: DateTime.now(),
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
        '\$set': {'id_familia': idFam}
      },
    );

    final userIdx = _users.indexWhere((u) => u.idUsuario == _currentUser!.idUsuario);
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
      final famIdx = _families.indexWhere((f) => f.idFamilia == family!.idFamilia);
      if (famIdx != -1) {
        _families[famIdx] = family;
      } else {
        _families.add(family);
      }
    } else {
      try {
        family = _families.firstWhere((f) => f.clFamilia.toUpperCase() == cleanCode);
      } catch (_) {
        return 'invalid_code';
      }
    }

    if (family.idCreador == _currentUser!.idUsuario) {
      return 'already_creator';
    }

    final existingLink = await MongoService.findOne(
      collectionName: MongoConfig.colUsuarioFamilia,
      filter: {
        'id_usuario': _currentUser!.idUsuario,
        'id_familia': family.idFamilia,
      },
    );

    final isAlreadyMemberInMemory = _userFamilies.any((f) => f.idFamilia == family!.idFamilia);

    if (existingLink != null || isAlreadyMemberInMemory) {
      return 'already_member';
    }

    final link = UserFamilyModel(
      idUsuario: _currentUser!.idUsuario,
      idFamilia: family.idFamilia,
      fechaUnion: DateTime.now(),
    );
    await MongoService.insertOne(
      collectionName: MongoConfig.colUsuarioFamilia,
      document: link.toMap(),
    );

    _currentUser = _currentUser!.copyWith(idFamilia: family.idFamilia);
    await _localDb.saveUser(_currentUser!);

    await MongoService.updateOne(
      collectionName: MongoConfig.colUsuario,
      filter: {'id_usuario': _currentUser!.idUsuario},
      update: {
        '\$set': {'id_familia': family.idFamilia}
      },
    );

    final userIdx = _users.indexWhere((u) => u.idUsuario == _currentUser!.idUsuario);
    if (userIdx != -1) {
      _users[userIdx] = _currentUser!;
    }

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
        if (u.idFamilia == famId || u.idUsuario == _currentUser?.idUsuario || u.idUsuario == currentFamily?.idCreador) {
          uniqueMembers[u.idUsuario] = u;
        }
      }
    }
    return uniqueMembers.values.toList();
  }

  Future<void> removeFamilyMember(String idUsuario) async {
    final famId = _currentUser?.idFamilia;
    if (famId == null) return;

    await MongoService.deleteOne(
      collectionName: MongoConfig.colUsuarioFamilia,
      filter: {
        'id_usuario': idUsuario,
        'id_familia': famId,
      },
    );

    await MongoService.updateOne(
      collectionName: MongoConfig.colUsuario,
      filter: {'id_usuario': idUsuario, 'id_familia': famId},
      update: {
        '\$unset': {'id_familia': ""}
      },
    );

    final userIdx = _users.indexWhere((u) => u.idUsuario == idUsuario);
    if (userIdx != -1) {
      _users.removeAt(userIdx);
      notifyListeners();
    }
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
      (l) => l.idFamilia == famId &&
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
    final idx = _shoppingLists.indexWhere((l) => l.idListaCompra == idListaCompra);
    if (idx != -1) {
      final target = _shoppingLists[idx];
      if (target.isDefault) return;
      final updatedList = target.copyWith(isActive: false);
      _shoppingLists[idx] = updatedList;

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
      if (_listDetailItems[i].idListaCompra == idListaCompra && _listDetailItems[i].isPending) {
        _incrementCatalogUsage(_listDetailItems[i].idArticulo, _listDetailItems[i].nbArticulo);
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

    final idx = _shoppingLists.indexWhere((l) => l.idListaCompra == idListaCompra);
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
    final idx = _shoppingLists.indexWhere((l) => l.idListaCompra == idListaCompra);
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
    return _listDetailItems
        .where((i) => i.idListaCompra == idListaCompra && i.isPending)
        .toList();
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
      return a.nbArticuloEs.toLowerCase().compareTo(b.nbArticuloEs.toLowerCase());
    });
    return items;
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
              (idArticulo.isNotEmpty && i.idArticulo.isNotEmpty && i.idArticulo == idArticulo)),
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
              (idArticulo.isNotEmpty && i.idArticulo.isNotEmpty && i.idArticulo == idArticulo)),
    );

    if (completedExistingIdx != -1) {
      final existingItem = _listDetailItems[completedExistingIdx];
      final reactivatedItem = existingItem.copyWith(
        status: 'pending',
        fechaCompra: null,
        idUsuarioAgrego: _currentUser?.idUsuario,
        dsDetalle: dsDetalle ?? existingItem.dsDetalle,
      );

      _listDetailItems.removeAt(completedExistingIdx);
      _listDetailItems.add(reactivatedItem);
      await _localDb.saveListDetailItem(reactivatedItem, syncStatus: 'pending');
      notifyListeners();

      await _localDb.enqueueSyncItem(
        collectionName: MongoConfig.colDetalleLista,
        action: 'UPDATE',
        entityId: reactivatedItem.idDetalle,
        payload: {
          'status': 'pending',
          'id_usuario_agrego': reactivatedItem.idUsuarioAgrego,
          'ds_detalle': dsDetalle,
        },
      );

      _checkAndTriggerListNotification(idListaCompra);
      _syncService.triggerSync();
      return true;
    }

    // 3. Crear nuevo elemento
    final newItem = ListDetailItemModel(
      idDetalle: _uuid.v4(),
      idListaCompra: idListaCompra,
      idArticulo: idArticulo,
      nbArticulo: cleanName,
      dsDetalle: dsDetalle,
      status: 'pending',
      idUsuarioAgrego: _currentUser?.idUsuario,
    );

    // Agregar DE INMEDIATO en SQLite y en memoria local (0ms UI latency)
    _listDetailItems.add(newItem);
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
    _syncService.triggerSync();
    return true;
  }

  Future<void> _checkAndTriggerListNotification(String idListaCompra) async {
    final famId = _currentUser?.idFamilia;
    final userId = _currentUser?.idUsuario;
    if (famId == null || userId == null) return;

    final listIdx = _shoppingLists.indexWhere((l) => l.idListaCompra == idListaCompra);
    if (listIdx == -1) return;

    final targetList = _shoppingLists[listIdx];
    final lastNotif = targetList.feUltimaNotificacion;
    final now = DateTime.now();

    final canSendNotification = lastNotif == null ||
        now.difference(lastNotif) >= NotificationConfig.listNotificationCooldown;

    if (!canSendNotification) return;

    _shoppingLists[listIdx] = targetList.copyWith(feUltimaNotificacion: now);
    await _localDb.saveShoppingList(_shoppingLists[listIdx]);

    MongoService.updateOne(
      collectionName: MongoConfig.colListasCompra,
      filter: {'id_lista_compra': idListaCompra},
      update: {
        '\$set': {'fe_ultima_notificacion': now.toIso8601String()}
      },
    );

    final senderName = getUserDisplayName(userId);
    PushNotificationService.sendListProductsAddedNotification(
      idFamilia: famId,
      idListaCompra: idListaCompra,
      nbLista: targetList.nbLista,
      senderUserId: userId,
      senderName: senderName.isNotEmpty ? senderName : 'Un integrante',
    );
  }

  /// Verifica el cooldown de 10 minutos para notificación de marcación como comprado
  Future<void> _checkAndTriggerPurchaseNotification(String idListaCompra, {String? productName}) async {
    final famId = _currentUser?.idFamilia;
    final userId = _currentUser?.idUsuario;
    if (famId == null || userId == null) return;

    final listIdx = _shoppingLists.indexWhere((l) => l.idListaCompra == idListaCompra);
    if (listIdx == -1) return;

    final targetList = _shoppingLists[listIdx];
    final lastNotif = targetList.feUltimaNotificacionCompra;
    final now = DateTime.now();

    final canSendNotification = lastNotif == null ||
        now.difference(lastNotif) >= NotificationConfig.listNotificationCooldown;

    if (!canSendNotification) {
      final elapsedMin = now.difference(lastNotif).inMinutes;
      debugPrint(
        "[PUSH_NOTIF LOG] Cooldown de COMPRA ACTIVO en lista '${targetList.nbLista}'. "
        "Transcurridos: $elapsedMin min (Requiere >= ${NotificationConfig.listNotificationCooldown.inMinutes} min). Omitiendo push.",
      );
      return;
    }

    debugPrint("[PUSH_NOTIF LOG] Cooldown CUMPLIDO en lista '${targetList.nbLista}' para compra. Disparando notificación push...");

    _shoppingLists[listIdx] = targetList.copyWith(feUltimaNotificacionCompra: now);
    await _localDb.saveShoppingList(_shoppingLists[listIdx]);

    MongoService.updateOne(
      collectionName: MongoConfig.colListasCompra,
      filter: {'id_lista_compra': idListaCompra},
      update: {
        '\$set': {'fe_ultima_notificacion_compra': now.toIso8601String()}
      },
    );

    final senderName = getUserDisplayName(userId);
    PushNotificationService.sendListProductsPurchasedNotification(
      idFamilia: famId,
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
      await _localDb.saveListDetailItem(updated, syncStatus: 'pending');
      notifyListeners();

      await _localDb.enqueueSyncItem(
        collectionName: MongoConfig.colDetalleLista,
        action: 'UPDATE',
        entityId: idDetalle,
        payload: {'ds_detalle': cleanNote},
      );
      _syncService.triggerSync();
    }
  }

  Future<void> removeListDetailItem(String idDetalle) async {
    _listDetailItems.removeWhere((item) => item.idDetalle == idDetalle);
    await _localDb.deleteListDetailItemLocally(idDetalle);
    notifyListeners();

    await _localDb.enqueueSyncItem(
      collectionName: MongoConfig.colDetalleLista,
      action: 'DELETE',
      entityId: idDetalle,
      payload: {'id_detalle': idDetalle},
    );
    _syncService.triggerSync();
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
      _checkAndTriggerPurchaseNotification(updated.idListaCompra, productName: updated.nbArticulo);
      _syncService.triggerSync();
    }
  }
}
