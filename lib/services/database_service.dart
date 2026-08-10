import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../config/mongo_config.dart';
import '../models/user_model.dart';
import '../models/family_model.dart';
import '../models/shopping_list_model.dart';
import '../models/item_catalog_model.dart';
import '../models/list_detail_item_model.dart';
import '../models/user_family_model.dart';
import 'email_service.dart';
import 'mongo_service.dart';
import 'security_service.dart';

class DatabaseService extends ChangeNotifier {
  final Uuid _uuid = const Uuid();

  final List<UserModel> _users = [];
  final List<FamilyModel> _families = [];
  final List<FamilyModel> _userFamilies = [];
  List<FamilyModel> get userFamilies => List.unmodifiable(_userFamilies);

  final List<ShoppingListModel> _shoppingLists = [];
  final List<ItemCatalogModel> _catalogItems = [];
  final List<ListDetailItemModel> _listDetailItems = [];

  final List<ListDetailItemModel> _pendingInsertQueue = [];
  Timer? _batchInsertTimer;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

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

  /// Carga la sesión guardada del usuario usando SharedPreferences y el caché local (0ms delay)
  Future<void> initSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUserId = prefs.getString('session_user_id');

      if (savedUserId != null && savedUserId.isNotEmpty) {
        // Cargar usuario guardado en caché si existe
        final savedUserJson = prefs.getString('cache_user_$savedUserId');
        if (savedUserJson != null && savedUserJson.isNotEmpty) {
          try {
            final userMap = jsonDecode(savedUserJson);
            _currentUser = UserModel.fromMap(Map<String, dynamic>.from(userMap));
            if (!_users.any((u) => u.idUsuario == _currentUser!.idUsuario)) {
              _users.add(_currentUser!);
            }
            if (_currentUser?.idFamilia != null) {
              await _loadLocalCache(_currentUser!.idFamilia!);
            }
          } catch (_) {}
        }

        // Consultar usuario en MongoDB de fondo
        final remoteUser = await MongoService.findOne(
          collectionName: MongoConfig.colUsuario,
          filter: {'id_usuario': savedUserId},
        );

        if (remoteUser != null) {
          _currentUser = UserModel.fromMap(remoteUser);
          final uIdx = _users.indexWhere((u) => u.idUsuario == _currentUser!.idUsuario);
          if (uIdx != -1) {
            _users[uIdx] = _currentUser!;
          } else {
            _users.add(_currentUser!);
          }
          await prefs.setString('cache_user_$savedUserId', jsonEncode(_currentUser!.toMap()));
        } else {
          try {
            _currentUser = _users.firstWhere((u) => u.idUsuario == savedUserId);
          } catch (_) {}
        }

        if (_currentUser?.idFamilia != null) {
          await _loadLocalCache(_currentUser!.idFamilia!);
          fetchFamilyData();
        }
      }
    } catch (_) {
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Guarda el snapshot de las listas, catálogo y detalles en SharedPreferences para carga instantánea
  Future<void> _saveLocalCache() async {
    final famId = _currentUser?.idFamilia;
    if (famId == null || famId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();

      final listsJson = jsonEncode(_shoppingLists.map((l) => l.toMap()).toList());
      await prefs.setString('cache_lists_$famId', listsJson);

      final catalogJson = jsonEncode(
        _catalogItems.where((c) => c.idFamilia == famId).map((c) => c.toMap()).toList(),
      );
      await prefs.setString('cache_catalog_$famId', catalogJson);

      final detailsJson = jsonEncode(_listDetailItems.map((d) => d.toMap()).toList());
      await prefs.setString('cache_details_$famId', detailsJson);
    } catch (e) {
      debugPrint("[CACHE LOG] Error guardando caché local: $e");
    }
  }

  /// Carga instantáneamente desde SharedPreferences las listas, catálogo y productos guardados localmente
  Future<void> _loadLocalCache(String famId) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Cargar listas
      final listsStr = prefs.getString('cache_lists_$famId');
      if (listsStr != null && listsStr.isNotEmpty) {
        final List decoded = jsonDecode(listsStr);
        _shoppingLists.clear();
        for (var map in decoded) {
          _shoppingLists.add(ShoppingListModel.fromMap(Map<String, dynamic>.from(map)));
        }
      }

      // 2. Cargar catálogo
      final catalogStr = prefs.getString('cache_catalog_$famId');
      if (catalogStr != null && catalogStr.isNotEmpty) {
        final List decoded = jsonDecode(catalogStr);
        _catalogItems.removeWhere((c) => c.idFamilia == famId);
        for (var map in decoded) {
          _catalogItems.add(ItemCatalogModel.fromMap(Map<String, dynamic>.from(map)));
        }
      }

      // 3. Cargar detalles
      final detailsStr = prefs.getString('cache_details_$famId');
      if (detailsStr != null && detailsStr.isNotEmpty) {
        final List decoded = jsonDecode(detailsStr);
        _listDetailItems.clear();
        for (var map in decoded) {
          _listDetailItems.add(ListDetailItemModel.fromMap(Map<String, dynamic>.from(map)));
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint("[CACHE LOG] Error cargando caché local: $e");
    }
  }

  Future<void> _saveSession(String idUsuario) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('session_user_id', idUsuario);
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('session_user_id');
  }

  /// Obtiene todas las familias a las que está vinculado el usuario actual
  Future<void> fetchUserFamilies() async {
    final userId = _currentUser?.idUsuario;
    if (userId == null) return;

    try {
      // 1. Consultar colección puente 'usuario_familia'
      var userFamDocs = await MongoService.find(
        collectionName: MongoConfig.colUsuarioFamilia,
        filter: {'id_usuario': userId},
      );

      final Set<String> knownFamIds = userFamDocs
          .map((doc) => doc['id_familia'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toSet();

      // 2. Auto-recuperar familias creadas por el usuario que no estén en usuario_familia
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

      // 3. Auto-recuperar si el usuario tiene id_familia activo pero no en usuario_familia
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

      // 4. Cargar los objetos FamilyModel de todas las familias vinculadas
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

      // Si no hay familia activa seleccionada pero el usuario tiene familias, seleccionar la primera
      if ((_currentUser?.idFamilia == null ||
              !_userFamilies.any((f) => f.idFamilia == _currentUser!.idFamilia)) &&
          _userFamilies.isNotEmpty) {
        final activeFamId = _userFamilies.first.idFamilia;
        _currentUser = _currentUser!.copyWith(idFamilia: activeFamId);
        await MongoService.updateOne(
          collectionName: MongoConfig.colUsuario,
          filter: {'id_usuario': userId},
          update: {
            '\$set': {'id_familia': activeFamId}
          },
        );
      }
      // Limpieza automática de artículos huérfanos de familias que fueron borradas previamente
      await cleanOrphanCatalogItems();
    } catch (e) {
      debugPrint("[DB_SERVICE LOG] Error en fetchUserFamilies: $e");
    }
  }

  /// Limpia automáticamente cualquier artículo huérfano en c_articulo que pertenezca a familias ya eliminadas en MongoDB
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

  void _scheduleBatchInsert() {
    _batchInsertTimer?.cancel();
    _batchInsertTimer = Timer(const Duration(milliseconds: 1500), () {
      flushPendingInserts();
    });
  }

  /// Procesa y envía todos los elementos acumulados en la cola a MongoDB Atlas en 1 sola petición
  Future<void> flushPendingInserts() async {
    _batchInsertTimer?.cancel();
    _batchInsertTimer = null;

    if (_pendingInsertQueue.isEmpty) return;

    final batchToInsert = List<ListDetailItemModel>.from(_pendingInsertQueue);
    _pendingInsertQueue.clear();

    debugPrint("[DB_SERVICE LOG] Enviando lote de ${batchToInsert.length} elementos a MongoDB Atlas en 1 sola petición...");

    final docs = batchToInsert.map((item) => item.toMap()).toList();
    final success = await MongoService.insertMany(
      collectionName: MongoConfig.colDetalleLista,
      documents: docs,
    );

    if (!success) {
      debugPrint("[DB_SERVICE LOG] Error en insertMany en lote. Re-encolando elementos...");
      _pendingInsertQueue.addAll(batchToInsert);
    }
  }

  bool _isFetchingFamilyData = false;

  /// Sincroniza y descarga en tiempo real todos los datos compartidos de la familia seleccionada desde MongoDB Cloud
  Future<void> fetchFamilyData() async {
    final userId = _currentUser?.idUsuario;
    if (userId == null) return;

    if (_isFetchingFamilyData) {
      debugPrint("[DB_SERVICE LOG] fetchFamilyData en curso. Omitiendo llamada concurrente.");
      return;
    }
    _isFetchingFamilyData = true;

    await flushPendingInserts();

    _isSyncing = true;
    notifyListeners();

    try {
      await fetchUserFamilies();

      final famId = _currentUser?.idFamilia;
      if (famId == null || famId.isEmpty) return;

      // 1. Obtener la Familia actualizada
      final famDocs = await MongoService.find(
        collectionName: MongoConfig.colFamilia,
        filter: {'id_familia': famId},
      );
      if (famDocs.isNotEmpty) {
        final remoteFam = FamilyModel.fromMap(famDocs.first);
        final famIdx = _families.indexWhere((f) => f.idFamilia == famId);
        if (famIdx != -1) {
          _families[famIdx] = remoteFam;
        } else {
          _families.add(remoteFam);
        }
      }

      // 2. Obtener todos los Integrantes/Usuarios de esta Familia desde usuario_familia + usuario
      final memberLinks = await MongoService.find(
        collectionName: MongoConfig.colUsuarioFamilia,
        filter: {'id_familia': famId},
      );
      
      final memberUserIds = memberLinks.map((l) => l['id_usuario'] as String).toList();

      if (famDocs.isNotEmpty) {
        final creatorId = famDocs.first['id_creador'] as String?;
        if (creatorId != null && creatorId.isNotEmpty && !memberUserIds.contains(creatorId)) {
          memberUserIds.add(creatorId);
        }
      }

      if (!memberUserIds.contains(userId)) {
        memberUserIds.add(userId);
      }

      final List<UserModel> freshUsers = [];
      final Set<String> seenUserIds = {};

      for (var mId in memberUserIds) {
        if (seenUserIds.contains(mId)) continue;
        seenUserIds.add(mId);

        final uDoc = await MongoService.findOne(
          collectionName: MongoConfig.colUsuario,
          filter: {'id_usuario': mId},
        );
        if (uDoc != null) {
          final u = UserModel.fromMap(uDoc);
          freshUsers.add(u);
          if (u.idUsuario == userId) {
            _currentUser = u.copyWith(idFamilia: famId);
          }
        }
      }

      _users.clear();
      _users.addAll(freshUsers);

      // 3. Obtener todas las Listas de Compras de la Familia desde MongoDB ('lista_compra')
      final listDocs = await MongoService.find(
        collectionName: MongoConfig.colListasCompra,
        filter: {'id_familia': famId},
      );

      final freshLists = listDocs.map((doc) => ShoppingListModel.fromMap(doc)).toList();
      if (freshLists.isNotEmpty || _shoppingLists.isEmpty) {
        _shoppingLists.clear();
        _shoppingLists.addAll(freshLists);
      }

      // 4. Obtener Catálogo Fast-Select de la Familia desde MongoDB
      final catalogDocs = await MongoService.find(
        collectionName: MongoConfig.colCArticulo,
        filter: {'id_familia': famId},
      );
      final freshCatalog = catalogDocs.map((doc) => ItemCatalogModel.fromMap(doc)).toList();
      if (freshCatalog.isNotEmpty) {
        _catalogItems.removeWhere((c) => c.idFamilia == famId);
        _catalogItems.addAll(freshCatalog);
      } else if (_catalogItems.where((c) => c.idFamilia == famId).isEmpty) {
        await _seedDefaultCatalog(famId);
      }

      // 5. Obtener los detalles/artículos de las listas de la familia desde MongoDB
      final activeListIds = _shoppingLists.map((l) => l.idListaCompra).toList();
      final List<ListDetailItemModel> remoteItems = [];
      for (var listId in activeListIds) {
        final detailDocs = await MongoService.find(
          collectionName: MongoConfig.colDetalleLista,
          filter: {'id_lista_compra': listId},
        );
        final Set<String> seenPendingNames = {};
        for (var doc in detailDocs) {
          final item = ListDetailItemModel.fromMap(doc);
          final normName = item.nbArticulo.trim().toLowerCase();
          if (item.isPending) {
            if (seenPendingNames.contains(normName)) {
              // Limpieza de duplicados almacenados previamente en MongoDB Atlas
              debugPrint("[DB_SERVICE LOG] Limpiando duplicado en MongoDB: '${item.nbArticulo}' (ID: ${item.idDetalle})");
              MongoService.deleteOne(
                collectionName: MongoConfig.colDetalleLista,
                filter: {'id_detalle': item.idDetalle},
              );
              continue;
            }
            seenPendingNames.add(normName);
          }
          remoteItems.add(item);
        }
      }

      // FUSIÓN ATÓMICA INTELIGENTE (Atomic Merge):
      // Preservar elementos en cola de inserción pendiente (_pendingInsertQueue) para que nunca desaparezcan
      final pendingQueueIds = _pendingInsertQueue.map((p) => p.idDetalle).toSet();
      final Map<String, ListDetailItemModel> mergedMap = {};

      // 1. Añadir elementos remotos recibidos de MongoDB
      for (var item in remoteItems) {
        mergedMap[item.idDetalle] = item;
      }

      // 2. Preservar elementos locales que están actualmente en cola o recién agregados localmente
      for (var localItem in _listDetailItems) {
        if (pendingQueueIds.contains(localItem.idDetalle)) {
          mergedMap[localItem.idDetalle] = localItem;
        }
      }

      _listDetailItems.clear();
      _listDetailItems.addAll(mergedMap.values);

      // Guardar snapshot actualizado en caché local de SharedPreferences
      await _saveLocalCache();
    } catch (e) {
      debugPrint("[DB_SERVICE LOG] Error en fetchFamilyData: $e");
    } finally {
      _isFetchingFamilyData = false;
      _isSyncing = false;
      notifyListeners();
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
    );

    await MongoService.insertOne(
      collectionName: MongoConfig.colUsuario,
      document: newUser.toMap(),
    );

    _users.add(newUser);
    _currentUser = newUser;
    await _saveSession(newUser.idUsuario);

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

    debugPrint("[DB_SERVICE LOG] loginUser iniciado. Buscando: '$cleanInput'");
    debugPrint("[DB_SERVICE LOG] Hash generado para la contraseña ingresada: '$passHash'");

    final escapedInput = RegExp.escape(cleanInput);

    // 1. Buscar usuario en MongoDB Cloud por email (insensible a mayúsculas)
    debugPrint("[DB_SERVICE LOG] 1. Buscando en MongoDB por nb_email (\$regex: '$cleanInput')...");
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

    remoteUserMap ??= await MongoService.findOne(
      collectionName: MongoConfig.colUsuario,
      filter: {'nb_email': cleanInput},
    );

    if (remoteUserMap != null) {
      debugPrint("[DB_SERVICE LOG] ¡Usuario encontrado en MongoDB!");
      debugPrint("[DB_SERVICE LOG] Documento retornado: id_usuario='${remoteUserMap['id_usuario']}', email='${remoteUserMap['nb_email']}', nb_usuario='${remoteUserMap['nb_usuario']}'");

      final storedPass = remoteUserMap['cl_pass'] as String?;
      debugPrint("[DB_SERVICE LOG] Hash almacenado en DB: '$storedPass'");
      debugPrint("[DB_SERVICE LOG] Hash ingresado:          '$passHash'");

      if (storedPass == passHash) {
        debugPrint("[DB_SERVICE LOG] ¡Contraseña CORRECTA! Iniciando sesión...");
        _currentUser = UserModel.fromMap(remoteUserMap);
        await _saveSession(_currentUser!.idUsuario);
        if (_currentUser?.idFamilia != null) {
          await fetchFamilyData();
        }
        notifyListeners();
        return true;
      } else {
        debugPrint("[DB_SERVICE LOG] ERROR: La contraseña no coincide (HashMismatch).");
        return false;
      }
    } else {
      debugPrint("[DB_SERVICE LOG] Usuario NO encontrado en MongoDB Cloud con el valor '$cleanInput'.");
      // Consultar usuarios registrados en la DB para auditar el valor guardado
      final allUsers = await MongoService.find(
        collectionName: MongoConfig.colUsuario,
        filter: {},
      );
      debugPrint("[DB_SERVICE LOG] Total de usuarios registrados en la colección 'usuario': ${allUsers.length}");
      for (var u in allUsers) {
        debugPrint("   -> ID: '${u['id_usuario']}', Email en DB: '${u['nb_email']}', Usuario en DB: '${u['nb_usuario']}'");
      }
    }

    debugPrint("[DB_SERVICE LOG] Buscando en usuarios semilla/locales...");
    try {
      final user = _users.firstWhere(
        (u) =>
            (u.nbEmail.toLowerCase() == cleanInput ||
                (u.nbUsuario != null && u.nbUsuario!.toLowerCase() == cleanInput)) &&
            u.clPass == passHash,
      );
      debugPrint("[DB_SERVICE LOG] Usuario encontrado en datos semilla locales.");
      _currentUser = user;
      await _saveSession(user.idUsuario);
      if (_currentUser?.idFamilia != null) {
        await fetchFamilyData();
      }
      notifyListeners();
      return true;
    } catch (_) {
      debugPrint("[DB_SERVICE LOG] ERROR: Usuario tampoco se encuentra en datos semilla locales.");
      return false;
    }
  }

  Future<void> logout() async {
    _currentUser = null;
    await _clearSession();
    notifyListeners();
  }

  // --- RECUPERACIÓN DE CONTRASEÑA CON OTP PIN ---
  /// Solicita el restablecimiento de contraseña enviando un PIN de 6 dígitos por correo
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
      // Prevención de enumeración de usuarios (Estándar de Seguridad OWASP):
      // Si el correo/usuario no existe, retornamos success = true para simular el mismo comportamiento y proteger la información
      debugPrint("[DB_SERVICE LOG] requestPasswordReset: Usuario no existe en DB, simulando respuesta exitosa por seguridad OWASP.");
      return {'success': true, 'email': cleanInput, 'userExists': false};
    }

    final targetEmail = (userMap['nb_email'] as String).toLowerCase();

    // Generar un PIN aleatorio de 6 dígitos
    final rnd = Random();
    final pinCode = (100000 + rnd.nextInt(900000)).toString();
    final pinHash = SecurityService.hashPassword(pinCode);
    final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 10)).toIso8601String();

    debugPrint("[DB_SERVICE LOG] PIN generado: '$pinCode', Hash PIN: '$pinHash', Expiración UTC: '$expiresAt'");

    // Guardar el hash del PIN y fecha de expiración en MongoDB Atlas
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

    // Enviar correo con EmailService (vía Resend / EmailJS API)
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

  /// Verifica si el PIN de 6 dígitos ingresado es válido y no ha expirado
  Future<bool> verifyResetPin(String email, String pinCode) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanPin = pinCode.trim();
    if (cleanEmail.isEmpty || cleanPin.length != 6) return false;

    final pinHash = SecurityService.hashPassword(cleanPin);

    debugPrint("[DB_SERVICE LOG] verifyResetPin para email: '$cleanEmail', PIN: '$cleanPin'");
    debugPrint("[DB_SERVICE LOG] Hash del PIN ingresado: '$pinHash'");

    final escapedEmail = RegExp.escape(cleanEmail);

    final userMap = await MongoService.findOne(
      collectionName: MongoConfig.colUsuario,
      filter: {
        'nb_email': {r'$regex': '^$escapedEmail\$', r'$options': 'i'}
      },
    );

    if (userMap == null) {
      debugPrint("[DB_SERVICE LOG] verifyResetPin ERROR: Usuario no encontrado por email.");
      return false;
    }

    final storedPinHash = userMap['cd_reset_pin'] as String?;
    final storedExpiresStr = userMap['fh_reset_expires'] as String?;

    debugPrint("[DB_SERVICE LOG] Hash PIN en DB: '$storedPinHash'");
    debugPrint("[DB_SERVICE LOG] Expiración en DB: '$storedExpiresStr'");

    if (storedPinHash == null || storedExpiresStr == null) {
      debugPrint("[DB_SERVICE LOG] verifyResetPin ERROR: No hay PIN guardado en DB.");
      return false;
    }

    if (storedPinHash != pinHash) {
      debugPrint("[DB_SERVICE LOG] verifyResetPin ERROR: El hash del PIN ingresado no coincide con el guardado.");
      return false;
    }

    try {
      final expiresAt = DateTime.parse(storedExpiresStr).toUtc();
      final nowUtc = DateTime.now().toUtc();
      debugPrint("[DB_SERVICE LOG] Comparando hora UTC: ahora=$nowUtc, expira=$expiresAt");
      if (nowUtc.isAfter(expiresAt)) {
        debugPrint("[DB_SERVICE LOG] verifyResetPin ERROR: El PIN ya expiró.");
        return false;
      }
    } catch (e) {
      debugPrint("[DB_SERVICE LOG] verifyResetPin ERROR parseando fecha: $e");
      return false;
    }

    debugPrint("[DB_SERVICE LOG] ¡PIN verificado con ÉXITO!");
    return true;
  }

  /// Restablece la contraseña del usuario tras validar el PIN
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

  /// Cambia la familia activa seleccionada por el usuario y recarga sus listas de compras
  Future<void> switchFamily(String idFamilia) async {
    if (_currentUser == null) return;
    if (_currentUser!.idFamilia == idFamilia) return;

    _currentUser = _currentUser!.copyWith(idFamilia: idFamilia);
    await _loadLocalCache(idFamilia);

    await MongoService.updateOne(
      collectionName: MongoConfig.colUsuario,
      filter: {'id_usuario': _currentUser!.idUsuario},
      update: {
        '\$set': {'id_familia': idFamilia}
      },
    );

    await fetchFamilyData();
  }

  /// Permite al usuario salir voluntariamente de la familia especificada
  Future<void> leaveFamily(String idFamilia) async {
    final userId = _currentUser?.idUsuario;
    if (userId == null) return;

    // 1. Eliminar vínculo de usuario_familia
    await MongoService.deleteOne(
      collectionName: MongoConfig.colUsuarioFamilia,
      filter: {
        'id_usuario': userId,
        'id_familia': idFamilia,
      },
    );

    _userFamilies.removeWhere((f) => f.idFamilia == idFamilia);

    // 2. Si salimos de la familia actualmente activa
    if (_currentUser?.idFamilia == idFamilia) {
      if (_userFamilies.isNotEmpty) {
        final newActiveFamId = _userFamilies.first.idFamilia;
        _currentUser = _currentUser!.copyWith(idFamilia: newActiveFamId);
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

  /// Elimina físicamente una familia creada por el usuario y todos sus datos relacionados de MongoDB Cloud
  Future<bool> deleteFamily(String idFamilia) async {
    final userId = _currentUser?.idUsuario;
    if (userId == null) return false;

    // Verificar que el usuario sea el creador de la familia
    final famIndex = _userFamilies.indexWhere((f) => f.idFamilia == idFamilia);
    if (famIndex == -1) return false;

    final family = _userFamilies[famIndex];
    if (family.idCreador != userId) {
      debugPrint("[DB_SERVICE LOG] deleteFamily ERROR: Solo el creador puede eliminar esta familia.");
      return false;
    }

    debugPrint("[DB_SERVICE LOG] Eliminando físicamente familia '$idFamilia' y todas sus entidades asociadas de MongoDB...");

    try {
      // 1. Obtener todas las listas de compras de esta familia para eliminar sus detalles
      final familyListDocs = await MongoService.find(
        collectionName: MongoConfig.colListasCompra,
        filter: {'id_familia': idFamilia},
      );
      final familyListIds = familyListDocs.map((l) => l['id_lista_compra'] as String).toList();

      // 2. Eliminar físicamente todos los detalles/artículos de las listas de esta familia
      for (var listId in familyListIds) {
        await MongoService.deleteMany(
          collectionName: MongoConfig.colDetalleLista,
          filter: {'id_lista_compra': listId},
        );
      }

      // 3. Eliminar físicamente todas las listas de compras de la familia
      await MongoService.deleteMany(
        collectionName: MongoConfig.colListasCompra,
        filter: {'id_familia': idFamilia},
      );

      // 4. Eliminar el catálogo de productos personalizado de la familia
      await MongoService.deleteMany(
        collectionName: MongoConfig.colCArticulo,
        filter: {'id_familia': idFamilia},
      );

      // 5. Eliminar la relación de integrantes en usuario_familia (sin borrar a los usuarios del sistema)
      await MongoService.deleteMany(
        collectionName: MongoConfig.colUsuarioFamilia,
        filter: {'id_familia': idFamilia},
      );

      // 6. Eliminar el documento de la familia en Mongo
      await MongoService.deleteOne(
        collectionName: MongoConfig.colFamilia,
        filter: {'id_familia': idFamilia},
      );

      // 7. Remover de la memoria local
      _userFamilies.removeWhere((f) => f.idFamilia == idFamilia);
      _families.removeWhere((f) => f.idFamilia == idFamilia);

      // 8. Si la familia eliminada era la familia activa actual del usuario
      if (_currentUser?.idFamilia == idFamilia) {
        if (_userFamilies.isNotEmpty) {
          final newActiveId = _userFamilies.first.idFamilia;
          _currentUser = _currentUser!.copyWith(idFamilia: newActiveId);
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

    // Regla de negocio: Máximo 5 familias creadas por el usuario
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

    await MongoService.insertOne(
      collectionName: MongoConfig.colFamilia,
      document: family.toMap(),
    );

    _families.add(family);

    // Registrar en tabla puente usuario_familia
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

    // 1. Validar si el usuario actual es el CREADOR de esta familia
    if (family.idCreador == _currentUser!.idUsuario) {
      debugPrint("[DB_SERVICE LOG] El usuario ya es el creador de la familia '${family.nbFamilia}'");
      return 'already_creator';
    }

    // 2. Validar si el usuario ya es INTEGRANTE de esta familia (en BD o en memoria)
    final existingLink = await MongoService.findOne(
      collectionName: MongoConfig.colUsuarioFamilia,
      filter: {
        'id_usuario': _currentUser!.idUsuario,
        'id_familia': family.idFamilia,
      },
    );

    final isAlreadyMemberInMemory = _userFamilies.any((f) => f.idFamilia == family!.idFamilia);

    if (existingLink != null || isAlreadyMemberInMemory) {
      debugPrint("[DB_SERVICE LOG] El usuario ya es integrante de la familia '${family.nbFamilia}'");
      return 'already_member';
    }

    // 3. Crear nuevo registro de relación en usuario_familia
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
      _catalogItems.add(catItem);
    }
  }

  List<UserModel> getFamilyMembers() {
    final famId = _currentUser?.idFamilia;
    if (famId == null) return [];
    final Map<String, UserModel> uniqueMembers = {};
    for (var u in _users) {
      if (u.idUsuario.isNotEmpty) {
        uniqueMembers[u.idUsuario] = u;
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

  /// Crea una NUEVA lista de compras limpia si no existe una activa con el mismo nombre
  Future<void> createNewList(String nbLista) async {
    final famId = _currentUser?.idFamilia;
    if (famId == null) return;

    final trimmedName = nbLista.trim();
    if (trimmedName.isEmpty) return;

    // Verificar si ya existe una lista ACTIVA (no completada) con el mismo nombre para esta familia
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
    await MongoService.insertOne(
      collectionName: MongoConfig.colListasCompra,
      document: newList.toMap(),
    );
    _shoppingLists.add(newList);
    notifyListeners();
    _saveLocalCache();
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
      _shoppingLists[idx] = target.copyWith(isActive: false);
      await MongoService.updateOne(
        collectionName: MongoConfig.colListasCompra,
        filter: {'id_lista_compra': idListaCompra},
        update: {
          '\$set': {'is_active': false}
        },
      );
      notifyListeners();
      _saveLocalCache();
    }
  }

  /// Finaliza toda la lista: marca todos los elementos pendientes como comprados y la lista como hecha (is_completed = true)
  Future<void> finishAndCompleteEntireList(String idListaCompra) async {
    final nowIso = DateTime.now().toIso8601String();
    final userId = _currentUser?.idUsuario;

    // 1. Marcar todos los elementos pendientes de esta lista en memoria y MongoDB como comprados
    for (int i = 0; i < _listDetailItems.length; i++) {
      if (_listDetailItems[i].idListaCompra == idListaCompra && _listDetailItems[i].isPending) {
        _incrementCatalogUsage(_listDetailItems[i].idArticulo, _listDetailItems[i].nbArticulo);
        _listDetailItems[i] = _listDetailItems[i].copyWith(
          status: 'completed',
          fechaCompra: DateTime.now(),
          idUsuarioFinalizo: userId,
        );
      }
    }

    await MongoService.updateOne(
      collectionName: MongoConfig.colDetalleLista,
      filter: {
        'id_lista_compra': idListaCompra,
        'status': 'pending',
      },
      update: {
        '\$set': {
          'status': 'completed',
          'fecha_compra': nowIso,
          'id_usuario_finalizo': userId,
        }
      },
    );

    // 2. Marcar la lista de compras como completada (is_completed = true)
    final idx = _shoppingLists.indexWhere((l) => l.idListaCompra == idListaCompra);
    if (idx != -1) {
      _shoppingLists[idx] = _shoppingLists[idx].copyWith(isCompleted: true);
      await MongoService.updateOne(
        collectionName: MongoConfig.colListasCompra,
        filter: {'id_lista_compra': idListaCompra},
        update: {
          '\$set': {'is_completed': true}
        },
      );
    }

    notifyListeners();
    _saveLocalCache();
  }

  Future<bool> markListAsCompleted(String idListaCompra) async {
    if (hasPendingItems(idListaCompra)) {
      return false;
    }
    final idx = _shoppingLists.indexWhere((l) => l.idListaCompra == idListaCompra);
    if (idx != -1) {
      _shoppingLists[idx] = _shoppingLists[idx].copyWith(isCompleted: true);
      await MongoService.updateOne(
        collectionName: MongoConfig.colListasCompra,
        filter: {'id_lista_compra': idListaCompra},
        update: {
          '\$set': {'is_completed': true}
        },
      );
      notifyListeners();
      _saveLocalCache();
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

  /// Retorna ÚNICAMENTE los artículos del catálogo pertenecientes a la familia del usuario activo,
  /// ordenados por productos más comprados/usados primero (nuUso descendente)
  List<ItemCatalogModel> getCatalogItems() {
    final famId = _currentUser?.idFamilia;
    if (famId == null) return [];
    final items = _catalogItems.where((c) => c.idFamilia == famId).toList();
    items.sort((a, b) {
      final cmp = b.nuUso.compareTo(a.nuUso); // Más comprados arriba
      if (cmp != 0) return cmp;
      return a.nbArticuloEs.toLowerCase().compareTo(b.nbArticuloEs.toLowerCase());
    });
    return items;
  }

  /// Incrementa el contador de uso (nuUso) del artículo en el catálogo local y en MongoDB ($inc)
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
      _catalogItems[idx] = target.copyWith(nuUso: target.nuUso + 1);

      // Incrementar atómicamente en MongoDB Atlas de fondo ($inc: {nu_uso: 1})
      MongoService.updateOne(
        collectionName: MongoConfig.colCArticulo,
        filter: {'id_articulo': target.idArticulo},
        update: {
          '\$inc': {'nu_uso': 1}
        },
      );
    }
  }

  /// Obtiene el nombre a mostrar de un usuario (prioriza nb_usuario si fue capturado; de lo contrario, usa el primer nombre de nb_completo)
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

  Future<bool> addItemToList({
    required String idListaCompra,
    required String idArticulo,
    required String nbArticulo,
    String? dsDetalle,
  }) async {
    final cleanName = nbArticulo.trim();
    if (cleanName.isEmpty) return false;

    final cleanNameLower = cleanName.toLowerCase();

    // 1. Verificar si ya existe un elemento ACTIVO/PENDIENTE con este nombre en la lista de compras
    final activeExistingIdx = _listDetailItems.indexWhere(
      (i) =>
          i.idListaCompra == idListaCompra &&
          i.isPending &&
          (i.nbArticulo.trim().toLowerCase() == cleanNameLower ||
              (idArticulo.isNotEmpty && i.idArticulo.isNotEmpty && i.idArticulo == idArticulo)),
    );

    if (activeExistingIdx != -1) {
      debugPrint("[DB_SERVICE LOG] Omitiendo adición: '$cleanName' ya se encuentra activo/pendiente en la lista.");
      return false;
    }

    // 2. Verificar si existía un elemento COMPLETADO (comprado previamente) con este nombre/idArticulo
    final completedExistingIdx = _listDetailItems.indexWhere(
      (i) =>
          i.idListaCompra == idListaCompra &&
          i.isCompleted &&
          (i.nbArticulo.trim().toLowerCase() == cleanNameLower ||
              (idArticulo.isNotEmpty && i.idArticulo.isNotEmpty && i.idArticulo == idArticulo)),
    );

    if (completedExistingIdx != -1) {
      // Reactivar el elemento completado volviéndolo a pasar a 'pending'
      final existingItem = _listDetailItems[completedExistingIdx];
      final reactivatedItem = existingItem.copyWith(
        status: 'pending',
        fechaCompra: null,
        idUsuarioAgrego: _currentUser?.idUsuario,
        dsDetalle: dsDetalle ?? existingItem.dsDetalle,
      );

      _listDetailItems[completedExistingIdx] = reactivatedItem;
      notifyListeners();
      _saveLocalCache();

      // Actualizar en MongoDB Atlas de fondo
      final Map<String, dynamic> setFields = {
        'status': 'pending',
        'id_usuario_agrego': reactivatedItem.idUsuarioAgrego,
      };
      if (dsDetalle != null) {
        setFields['ds_detalle'] = dsDetalle;
      }

      MongoService.updateOne(
        collectionName: MongoConfig.colDetalleLista,
        filter: {'id_detalle': reactivatedItem.idDetalle},
        update: {
          '\$set': setFields,
          '\$unset': {
            'fecha_compra': '',
            'id_usuario_finalizo': '',
          }
        },
      );

      return true;
    }

    // 3. Crear nuevo elemento en caso de no existir previamente
    final newItem = ListDetailItemModel(
      idDetalle: _uuid.v4(),
      idListaCompra: idListaCompra,
      idArticulo: idArticulo,
      nbArticulo: cleanName,
      dsDetalle: dsDetalle,
      status: 'pending',
      idUsuarioAgrego: _currentUser?.idUsuario,
    );

    // Agregar DE INMEDIATO en memoria local (0ms delay UI) y notificar a los listeners
    _listDetailItems.add(newItem);
    notifyListeners();
    _saveLocalCache();

    // Encolar para procesamiento en lote agrupado (Batching)
    _pendingInsertQueue.add(newItem);
    _scheduleBatchInsert();

    return true;
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

    // 1. Verificar si ya existe como ACTIVO/PENDIENTE en la lista de compras
    final alreadyPending = _listDetailItems.any(
      (i) =>
          i.idListaCompra == idListaCompra &&
          i.isPending &&
          i.nbArticulo.trim().toLowerCase() == cleanNameLower,
    );

    if (alreadyPending) {
      debugPrint("[DB_SERVICE LOG] Omitiendo adición personalizada: '$cleanName' ya está activo/pendiente en la lista.");
      return false;
    }

    // 2. Verificar si el artículo ya existe en el catálogo exclusivo de ESTA familia
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
      _saveLocalCache();

      await MongoService.insertOne(
        collectionName: MongoConfig.colCArticulo,
        document: newCatalogItem.toMap(),
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
      if (cleanNote == null || cleanNote.isEmpty) {
        _listDetailItems[idx] = _listDetailItems[idx].copyWith(clearDsDetalle: true);
        await MongoService.updateOne(
          collectionName: MongoConfig.colDetalleLista,
          filter: {'id_detalle': idDetalle},
          update: {
            '\$unset': {'ds_detalle': ''}
          },
        );
      } else {
        _listDetailItems[idx] = _listDetailItems[idx].copyWith(dsDetalle: cleanNote);
        await MongoService.updateOne(
          collectionName: MongoConfig.colDetalleLista,
          filter: {'id_detalle': idDetalle},
          update: {
            '\$set': {'ds_detalle': cleanNote}
          },
        );
      }
      notifyListeners();
      _saveLocalCache();
    }
  }

  Future<void> removeListDetailItem(String idDetalle) async {
    _listDetailItems.removeWhere((item) => item.idDetalle == idDetalle);
    _pendingInsertQueue.removeWhere((item) => item.idDetalle == idDetalle);
    await MongoService.deleteOne(
      collectionName: MongoConfig.colDetalleLista,
      filter: {'id_detalle': idDetalle},
    );
    notifyListeners();
    _saveLocalCache();
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
      await MongoService.updateOne(
        collectionName: MongoConfig.colDetalleLista,
        filter: {'id_detalle': idDetalle},
        update: {
          '\$set': {
            'status': 'completed',
            'fecha_compra': updated.fechaCompra?.toIso8601String(),
            'id_usuario_finalizo': updated.idUsuarioFinalizo,
          }
        },
      );
      notifyListeners();
      _saveLocalCache();
    }
  }
}
