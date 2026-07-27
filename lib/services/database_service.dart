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
import 'mongo_service.dart';
import 'security_service.dart';

class DatabaseService extends ChangeNotifier {
  final Uuid _uuid = const Uuid();

  final List<UserModel> _users = [];
  final List<FamilyModel> _families = [];
  final List<ShoppingListModel> _shoppingLists = [];
  final List<ItemCatalogModel> _catalogItems = [];
  final List<ListDetailItemModel> _listDetailItems = [];

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

  /// Sincroniza y descarga en tiempo real todos los datos compartidos de la familia desde MongoDB Cloud
  Future<void> fetchFamilyData() async {
    final famId = _currentUser?.idFamilia;
    if (famId == null) return;

    _isSyncing = true;
    notifyListeners();

    try {
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

      // 2. Obtener todos los Integrantes/Usuarios de la Familia desde MongoDB
      final userDocs = await MongoService.find(
        collectionName: MongoConfig.colUsuario,
        filter: {'id_familia': famId},
      );
      for (var doc in userDocs) {
        final u = UserModel.fromMap(doc);
        final idx = _users.indexWhere((existing) => existing.idUsuario == u.idUsuario);
        if (idx != -1) {
          _users[idx] = u;
        } else {
          _users.add(u);
        }
      }

      // 3. Obtener todas las Listas de Compras de la Familia desde MongoDB ('lista_compra')
      final listDocs = await MongoService.find(
        collectionName: MongoConfig.colListasCompra,
        filter: {'id_familia': famId},
      );

      for (var doc in listDocs) {
        final listModel = ShoppingListModel.fromMap(doc);
        final idx = _shoppingLists.indexWhere((l) => l.idListaCompra == listModel.idListaCompra);
        if (idx != -1) {
          _shoppingLists[idx] = listModel;
        } else {
          _shoppingLists.add(listModel);
        }
      }

      // 4. Obtener Catálogo Fast-Select de la Familia desde MongoDB
      final catalogDocs = await MongoService.find(
        collectionName: MongoConfig.colCArticulo,
        filter: {'id_familia': famId},
      );
      for (var doc in catalogDocs) {
        final catModel = ItemCatalogModel.fromMap(doc);
        final idx = _catalogItems.indexWhere((c) => c.idArticulo == catModel.idArticulo);
        if (idx != -1) {
          _catalogItems[idx] = catModel;
        } else {
          _catalogItems.add(catModel);
        }
      }

      // 5. Obtener los detalles/artículos de las listas de la familia desde MongoDB
      final activeListIds = _shoppingLists.map((l) => l.idListaCompra).toList();
      for (var listId in activeListIds) {
        final detailDocs = await MongoService.find(
          collectionName: MongoConfig.colDetalleLista,
          filter: {'id_lista_compra': listId},
        );
        for (var doc in detailDocs) {
          final detailModel = ListDetailItemModel.fromMap(doc);
          final idx = _listDetailItems.indexWhere((d) => d.idDetalle == detailModel.idDetalle);
          if (idx != -1) {
            _listDetailItems[idx] = detailModel;
          } else {
            _listDetailItems.add(detailModel);
          }
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
    final remoteUser = await MongoService.findOne(
      collectionName: MongoConfig.colUsuario,
      filter: {'nb_email': nbEmail.toLowerCase()},
    );

    if (remoteUser != null || _users.any((u) => u.nbEmail.toLowerCase() == nbEmail.toLowerCase())) {
      throw Exception("El correo electrónico ya está registrado.");
    }

    final passHash = SecurityService.hashPassword(password);
    final newUser = UserModel(
      idUsuario: _uuid.v4(),
      nbCompleto: nbCompleto,
      nbUsuario: nbUsuario,
      nbEmail: nbEmail,
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
    final passHash = SecurityService.hashPassword(password);

    final remoteUserMap = await MongoService.findOne(
      collectionName: MongoConfig.colUsuario,
      filter: {
        'cl_pass': passHash,
        '\$or': [
          {'nb_email': emailOrUsername.toLowerCase()},
          {'nb_usuario': emailOrUsername.toLowerCase()},
        ],
      },
    );

    if (remoteUserMap != null) {
      _currentUser = UserModel.fromMap(remoteUserMap);
      await _saveSession(_currentUser!.idUsuario);
      if (_currentUser?.idFamilia != null) {
        await fetchFamilyData();
      }
      notifyListeners();
      return true;
    }

    try {
      final user = _users.firstWhere(
        (u) =>
            (u.nbEmail.toLowerCase() == emailOrUsername.toLowerCase() ||
                (u.nbUsuario != null && u.nbUsuario!.toLowerCase() == emailOrUsername.toLowerCase())) &&
            u.clPass == passHash,
      );
      _currentUser = user;
      await _saveSession(user.idUsuario);
      if (_currentUser?.idFamilia != null) {
        await fetchFamilyData();
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    _currentUser = null;
    await _clearSession();
    notifyListeners();
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
    return _users.where((u) => u.idFamilia == famId).toList();
  }

  Future<void> removeFamilyMember(String idUsuario) async {
    await MongoService.updateOne(
      collectionName: MongoConfig.colUsuario,
      filter: {'id_usuario': idUsuario},
      update: {
        '\$unset': {'id_familia': ""}
      },
    );

    final userIdx = _users.indexWhere((u) => u.idUsuario == idUsuario);
    if (userIdx != -1) {
      _users[userIdx] = _users[userIdx].copyWith(clearFamilia: true);
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

  Future<void> addItemToList({
    required String idListaCompra,
    required String idArticulo,
    required String nbArticulo,
  }) async {
    final newItem = ListDetailItemModel(
      idDetalle: _uuid.v4(),
      idListaCompra: idListaCompra,
      idArticulo: idArticulo,
      nbArticulo: nbArticulo,
      status: 'pending',
    );
    await MongoService.insertOne(
      collectionName: MongoConfig.colDetalleLista,
      document: newItem.toMap(),
    );
    _listDetailItems.add(newItem);
    notifyListeners();
  }

  Future<void> addCustomItemToCatalogAndList({
    required String idListaCompra,
    required String nbArticulo,
  }) async {
    final famId = _currentUser?.idFamilia;
    if (famId == null) return;

    final cleanName = nbArticulo.trim();
    if (cleanName.isEmpty) return;

    // Verificar si el artículo ya existe en el catálogo exclusivo de ESTA familia
    final familyCatalog = getCatalogItems();
    final existingIdx = familyCatalog.indexWhere(
      (c) => c.nbArticuloEs.toLowerCase() == cleanName.toLowerCase() ||
             c.nbArticuloEn.toLowerCase() == cleanName.toLowerCase(),
    );

    if (existingIdx != -1) {
      final existingArt = familyCatalog[existingIdx];
      await addItemToList(
        idListaCompra: idListaCompra,
        idArticulo: existingArt.idArticulo,
        nbArticulo: cleanName,
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

      await addItemToList(
        idListaCompra: idListaCompra,
        idArticulo: artId,
        nbArticulo: cleanName,
      );
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
