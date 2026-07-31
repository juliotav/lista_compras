import 'dart:async';
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

  /// Carga la sesión guardada del usuario usando SharedPreferences
  Future<void> initSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUserId = prefs.getString('session_user_id');

      if (savedUserId != null && savedUserId.isNotEmpty) {
        final remoteUser = await MongoService.findOne(
          collectionName: MongoConfig.colUsuario,
          filter: {'id_usuario': savedUserId},
        );

        if (remoteUser != null) {
          _currentUser = UserModel.fromMap(remoteUser);
          _users.add(_currentUser!);
        } else {
          try {
            _currentUser = _users.firstWhere((u) => u.idUsuario == savedUserId);
          } catch (_) {}
        }

        if (_currentUser?.idFamilia != null) {
          await fetchFamilyData();
        }
      }
    } catch (_) {
    } finally {
      _isInitialized = true;
      notifyListeners();
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
    } catch (e) {
      debugPrint("[DB_SERVICE LOG] Error en fetchUserFamilies: $e");
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

  /// Sincroniza y descarga en tiempo real todos los datos compartidos de la familia seleccionada desde MongoDB Cloud
  Future<void> fetchFamilyData() async {
    final userId = _currentUser?.idUsuario;
    if (userId == null) return;

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

      _users.clear();
      for (var mId in memberUserIds) {
        final uDoc = await MongoService.findOne(
          collectionName: MongoConfig.colUsuario,
          filter: {'id_usuario': mId},
        );
        if (uDoc != null) {
          final u = UserModel.fromMap(uDoc);
          _users.add(u);
          if (u.idUsuario == userId) {
            _currentUser = u.copyWith(idFamilia: famId);
          }
        }
      }

      // 3. Obtener todas las Listas de Compras de la Familia desde MongoDB ('lista_compra')
      final listDocs = await MongoService.find(
        collectionName: MongoConfig.colListasCompra,
        filter: {'id_familia': famId},
      );

      _shoppingLists.clear();
      for (var doc in listDocs) {
        _shoppingLists.add(ShoppingListModel.fromMap(doc));
      }

      // 4. Obtener Catálogo Fast-Select de la Familia desde MongoDB
      final catalogDocs = await MongoService.find(
        collectionName: MongoConfig.colCArticulo,
        filter: {'id_familia': famId},
      );
      _catalogItems.clear();
      for (var doc in catalogDocs) {
        _catalogItems.add(ItemCatalogModel.fromMap(doc));
      }

      // 5. Obtener los detalles/artículos de las listas de la familia desde MongoDB
      final activeListIds = _shoppingLists.map((l) => l.idListaCompra).toList();
      _listDetailItems.clear();
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
          _listDetailItems.add(item);
        }
      }
    } catch (_) {
    } finally {
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

  // --- GESTIÓN DE FAMILIA ---
  String _generateFamilyCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random();
    final code = List.generate(5, (_) => chars[rnd.nextInt(chars.length)]).join();
    return 'FAM-$code';
  }

  Future<FamilyModel> createFamily(String nbFamilia, String? dsFamilia) async {
    if (_currentUser == null) throw Exception("Usuario no autenticado");

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

  Future<bool> joinFamily(String clFamilia) async {
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
        return false;
      }
    }

    // Verificar e insertar en usuario_familia si no existe la relación
    final existingLink = await MongoService.findOne(
      collectionName: MongoConfig.colUsuarioFamilia,
      filter: {
        'id_usuario': _currentUser!.idUsuario,
        'id_familia': family.idFamilia,
      },
    );

    if (existingLink == null) {
      final link = UserFamilyModel(
        idUsuario: _currentUser!.idUsuario,
        idFamilia: family.idFamilia,
        fechaUnion: DateTime.now(),
      );
      await MongoService.insertOne(
        collectionName: MongoConfig.colUsuarioFamilia,
        document: link.toMap(),
      );
    }

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
    return true;
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
    return _users.toList();
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
    }
  }

  /// Finaliza toda la lista: marca todos los elementos pendientes como comprados y la lista como hecha (is_completed = true)
  Future<void> finishAndCompleteEntireList(String idListaCompra) async {
    final nowIso = DateTime.now().toIso8601String();
    final userId = _currentUser?.idUsuario;

    // 1. Marcar todos los elementos pendientes de esta lista en memoria y MongoDB como comprados
    for (int i = 0; i < _listDetailItems.length; i++) {
      if (_listDetailItems[i].idListaCompra == idListaCompra && _listDetailItems[i].isPending) {
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

  /// Retorna ÚNICAMENTE los artículos del catálogo pertenecientes a la familia del usuario activo
  List<ItemCatalogModel> getCatalogItems() {
    final famId = _currentUser?.idFamilia;
    if (famId == null) return [];
    return _catalogItems.where((c) => c.idFamilia == famId).toList();
  }

  /// Obtiene el primer nombre o nombre de usuario amigable de la persona que realizó una acción
  String getUserDisplayName(String? idUsuario) {
    if (idUsuario == null || idUsuario.isEmpty) return '';
    if (_currentUser != null && _currentUser!.idUsuario == idUsuario) {
      final name = _currentUser!.nbCompleto.trim();
      final first = name.contains(' ') ? name.split(' ').first : name;
      return first.isNotEmpty ? first : (_currentUser!.nbUsuario ?? '');
    }
    try {
      final u = _users.firstWhere((user) => user.idUsuario == idUsuario);
      final name = u.nbCompleto.trim();
      final first = name.contains(' ') ? name.split(' ').first : name;
      return first.isNotEmpty ? first : (u.nbUsuario ?? '');
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

    // Evitar agregar elementos duplicados con el mismo nombre o idArticulo en la misma lista
    final alreadyExists = _listDetailItems.any(
      (i) =>
          i.idListaCompra == idListaCompra &&
          (i.nbArticulo.trim().toLowerCase() == cleanNameLower ||
              (idArticulo.isNotEmpty && i.idArticulo == idArticulo)),
    );

    if (alreadyExists) {
      debugPrint("[DB_SERVICE LOG] Omitiendo adición: '$cleanName' ya se encuentra en la lista.");
      return false;
    }

    final newItem = ListDetailItemModel(
      idDetalle: _uuid.v4(),
      idListaCompra: idListaCompra,
      idArticulo: idArticulo,
      nbArticulo: cleanName,
      dsDetalle: dsDetalle,
      status: 'pending',
      idUsuarioAgrego: _currentUser?.idUsuario,
    );

    // 2. Agregar DE INMEDIATO en memoria local (0ms delay UI) y notificar a los listeners
    _listDetailItems.add(newItem);
    notifyListeners();

    // 3. Encolar para procesamiento en lote agrupado (Batching)
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

    // Verificar si ya existe en la lista de compras antes de registrar en catálogo
    final alreadyInList = _listDetailItems.any(
      (i) =>
          i.idListaCompra == idListaCompra &&
          i.nbArticulo.trim().toLowerCase() == cleanNameLower,
    );

    if (alreadyInList) {
      debugPrint("[DB_SERVICE LOG] Omitiendo adición personalizada: '$cleanName' ya está en la lista.");
      return false;
    }

    // Verificar si el artículo ya existe en el catálogo exclusivo de ESTA familia
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
      await MongoService.insertOne(
        collectionName: MongoConfig.colCArticulo,
        document: newCatalogItem.toMap(),
      );
      _catalogItems.add(newCatalogItem);

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
    }
  }

  Future<void> removeListDetailItem(String idDetalle) async {
    _listDetailItems.removeWhere((item) => item.idDetalle == idDetalle);
    await MongoService.deleteOne(
      collectionName: MongoConfig.colDetalleLista,
      filter: {'id_detalle': idDetalle},
    );
    notifyListeners();
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
    }
  }
}
