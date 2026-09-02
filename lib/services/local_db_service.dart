import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/family_model.dart';
import '../models/item_catalog_model.dart';
import '../models/list_detail_item_model.dart';
import '../models/shopping_list_model.dart';
import '../models/user_model.dart';

class SyncQueueItem {
  final int? id;
  final String collectionName;
  final String action; // 'INSERT', 'UPDATE', 'DELETE'
  final String entityId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;

  SyncQueueItem({
    this.id,
    required this.collectionName,
    required this.action,
    required this.entityId,
    required this.payload,
    DateTime? createdAt,
    this.retryCount = 0,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'collection_name': collectionName,
      'action': action,
      'entity_id': entityId,
      'payload_json': jsonEncode(payload),
      'created_at': createdAt.toIso8601String(),
      'retry_count': retryCount,
    };
  }

  factory SyncQueueItem.fromMap(Map<String, dynamic> map) {
    return SyncQueueItem(
      id: map['id'] as int?,
      collectionName: map['collection_name'] as String,
      action: map['action'] as String,
      entityId: map['entity_id'] as String,
      payload: jsonDecode(map['payload_json'] as String) as Map<String, dynamic>,
      createdAt: DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now(),
      retryCount: map['retry_count'] as int? ?? 0,
    );
  }
}

class LocalDbService {
  static LocalDbService? _instance;
  static Database? _db;

  LocalDbService._internal();

  factory LocalDbService() {
    _instance ??= LocalDbService._internal();
    return _instance!;
  }

  Future<Database> get db async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'lista_compras_local.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onOpen: (db) async {
        try {
          await db.execute('ALTER TABLE users ADD COLUMN ds_version_app TEXT;');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE shopping_lists ADD COLUMN fe_ultima_notificacion_compra TEXT;');
        } catch (_) {}
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    debugPrint("[LOCAL_DB] Creando tablas SQLite...");

    await db.execute('''
      CREATE TABLE users (
        id_usuario TEXT PRIMARY KEY,
        nb_completo TEXT NOT NULL,
        nb_usuario TEXT,
        nb_email TEXT NOT NULL,
        cl_pass TEXT NOT NULL,
        id_familia TEXT,
        ds_version_app TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE families (
        id_familia TEXT PRIMARY KEY,
        id_creador TEXT NOT NULL,
        nb_familia TEXT NOT NULL,
        cl_familia TEXT NOT NULL,
        ds_familia TEXT,
        fecha_creacion TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE shopping_lists (
        id_lista_compra TEXT PRIMARY KEY,
        id_familia TEXT NOT NULL,
        nb_lista TEXT NOT NULL,
        is_default INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        is_completed INTEGER NOT NULL DEFAULT 0,
        fe_ultima_notificacion TEXT,
        fe_ultima_notificacion_compra TEXT,
        sync_status TEXT NOT NULL DEFAULT 'synced'
      )
    ''');

    await db.execute('''
      CREATE TABLE list_detail_items (
        id_detalle TEXT PRIMARY KEY,
        id_lista_compra TEXT NOT NULL,
        id_articulo TEXT NOT NULL,
        nb_articulo TEXT NOT NULL,
        ds_detalle TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        fecha_compra TEXT,
        id_usuario_finalizo TEXT,
        id_usuario_agrego TEXT,
        sync_status TEXT NOT NULL DEFAULT 'synced'
      )
    ''');

    await db.execute('''
      CREATE TABLE item_catalog (
        id_articulo TEXT PRIMARY KEY,
        id_familia TEXT NOT NULL,
        nb_articulo_es TEXT NOT NULL,
        nb_articulo_en TEXT NOT NULL,
        nu_uso INTEGER NOT NULL DEFAULT 0,
        sync_status TEXT NOT NULL DEFAULT 'synced'
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        collection_name TEXT NOT NULL,
        action TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE session (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Índices para búsquedas eficientes
    await db.execute('CREATE INDEX idx_lists_fam ON shopping_lists (id_familia);');
    await db.execute('CREATE INDEX idx_details_list ON list_detail_items (id_lista_compra);');
    await db.execute('CREATE INDEX idx_catalog_fam ON item_catalog (id_familia);');
    await db.execute('CREATE INDEX idx_queue_id ON sync_queue (id);');

    debugPrint("[LOCAL_DB] Tablas de SQLite creadas exitosamente.");
  }

  // --- SESIÓN Y USUARIO ---
  Future<void> saveSessionUserId(String userId) async {
    final database = await db;
    await database.insert(
      'session',
      {'key': 'current_user_id', 'value': userId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('session_user_id', userId);
    } catch (_) {}
  }

  Future<String?> getSessionUserId() async {
    final database = await db;
    final res = await database.query(
      'session',
      where: 'key = ?',
      whereArgs: ['current_user_id'],
    );
    if (res.isNotEmpty) {
      final uid = res.first['value'] as String?;
      if (uid != null && uid.isNotEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('session_user_id', uid);
        } catch (_) {}
        return uid;
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('session_user_id');
    } catch (_) {}
    return null;
  }

  Future<void> clearSession() async {
    final database = await db;
    await database.delete('session', where: 'key = ?', whereArgs: ['current_user_id']);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('session_user_id');
    } catch (_) {}
  }

  Future<void> saveUser(UserModel user) async {
    final database = await db;
    await database.insert(
      'users',
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<UserModel?> getUser(String userId) async {
    final database = await db;
    final res = await database.query('users', where: 'id_usuario = ?', whereArgs: [userId]);
    if (res.isNotEmpty) {
      return UserModel.fromMap(res.first);
    }
    return null;
  }

  Future<List<UserModel>> getAllUsers() async {
    final database = await db;
    final res = await database.query('users');
    return res.map((m) => UserModel.fromMap(m)).toList();
  }

  // --- FAMILIAS ---
  Future<void> saveFamily(FamilyModel family) async {
    final database = await db;
    await database.insert(
      'families',
      family.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveFamilies(List<FamilyModel> families) async {
    if (families.isEmpty) return;
    final database = await db;
    final batch = database.batch();
    for (var f in families) {
      batch.insert('families', f.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<FamilyModel>> getFamilies() async {
    final database = await db;
    final res = await database.query('families');
    return res.map((m) => FamilyModel.fromMap(m)).toList();
  }

  // --- LISTAS DE COMPRA ---
  Future<List<ShoppingListModel>> getShoppingLists(String famId) async {
    final database = await db;
    final res = await database.query(
      'shopping_lists',
      where: 'id_familia = ? AND is_active = 1',
      whereArgs: [famId],
    );
    return res.map((m) {
      return ShoppingListModel(
        idListaCompra: m['id_lista_compra'] as String,
        idFamilia: m['id_familia'] as String,
        nbLista: m['nb_lista'] as String,
        isDefault: (m['is_default'] as int? ?? 0) == 1,
        isActive: (m['is_active'] as int? ?? 1) == 1,
        isCompleted: (m['is_completed'] as int? ?? 0) == 1,
        feUltimaNotificacion: m['fe_ultima_notificacion'] != null
            ? DateTime.tryParse(m['fe_ultima_notificacion'].toString())
            : null,
        feUltimaNotificacionCompra: m['fe_ultima_notificacion_compra'] != null
            ? DateTime.tryParse(m['fe_ultima_notificacion_compra'].toString())
            : null,
      );
    }).toList();
  }

  Future<void> saveShoppingList(ShoppingListModel list, {String syncStatus = 'synced'}) async {
    final database = await db;
    await database.insert(
      'shopping_lists',
      {
        'id_lista_compra': list.idListaCompra,
        'id_familia': list.idFamilia,
        'nb_lista': list.nbLista,
        'is_default': list.isDefault ? 1 : 0,
        'is_active': list.isActive ? 1 : 0,
        'is_completed': list.isCompleted ? 1 : 0,
        'fe_ultima_notificacion': list.feUltimaNotificacion?.toIso8601String(),
        'fe_ultima_notificacion_compra': list.feUltimaNotificacionCompra?.toIso8601String(),
        'sync_status': syncStatus,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveShoppingLists(List<ShoppingListModel> lists, {String famId = ''}) async {
    final database = await db;
    final batch = database.batch();
    if (famId.isNotEmpty) {
      batch.delete('shopping_lists', where: 'id_familia = ? AND sync_status = ?', whereArgs: [famId, 'synced']);
    }
    for (var list in lists) {
      batch.insert(
        'shopping_lists',
        {
          'id_lista_compra': list.idListaCompra,
          'id_familia': list.idFamilia,
          'nb_lista': list.nbLista,
          'is_default': list.isDefault ? 1 : 0,
          'is_active': list.isActive ? 1 : 0,
          'is_completed': list.isCompleted ? 1 : 0,
          'fe_ultima_notificacion': list.feUltimaNotificacion?.toIso8601String(),
          'fe_ultima_notificacion_compra': list.feUltimaNotificacionCompra?.toIso8601String(),
          'sync_status': 'synced',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteShoppingListLocally(String listId) async {
    final database = await db;
    await database.delete('shopping_lists', where: 'id_lista_compra = ?', whereArgs: [listId]);
    await database.delete('list_detail_items', where: 'id_lista_compra = ?', whereArgs: [listId]);
  }

  // --- DETALLES / ARTÍCULOS DE LISTA ---
  Future<List<ListDetailItemModel>> getListDetails(String listId) async {
    final database = await db;
    final res = await database.query(
      'list_detail_items',
      where: 'id_lista_compra = ?',
      whereArgs: [listId],
    );
    return res.map((m) {
      return ListDetailItemModel(
        idDetalle: m['id_detalle'] as String,
        idListaCompra: m['id_lista_compra'] as String,
        idArticulo: m['id_articulo'] as String,
        nbArticulo: m['nb_articulo'] as String,
        dsDetalle: m['ds_detalle'] as String?,
        status: m['status'] as String? ?? 'pending',
        fechaCompra: m['fecha_compra'] != null ? DateTime.tryParse(m['fecha_compra'].toString()) : null,
        idUsuarioFinalizo: m['id_usuario_finalizo'] as String?,
        idUsuarioAgrego: m['id_usuario_agrego'] as String?,
      );
    }).toList();
  }

  Future<List<ListDetailItemModel>> getAllListDetailsForFamily(List<String> listIds) async {
    if (listIds.isEmpty) return [];
    final database = await db;
    final placeholders = List.filled(listIds.length, '?').join(',');
    final res = await database.query(
      'list_detail_items',
      where: 'id_lista_compra IN ($placeholders)',
      whereArgs: listIds,
    );
    return res.map((m) {
      return ListDetailItemModel(
        idDetalle: m['id_detalle'] as String,
        idListaCompra: m['id_lista_compra'] as String,
        idArticulo: m['id_articulo'] as String,
        nbArticulo: m['nb_articulo'] as String,
        dsDetalle: m['ds_detalle'] as String?,
        status: m['status'] as String? ?? 'pending',
        fechaCompra: m['fecha_compra'] != null ? DateTime.tryParse(m['fecha_compra'].toString()) : null,
        idUsuarioFinalizo: m['id_usuario_finalizo'] as String?,
        idUsuarioAgrego: m['id_usuario_agrego'] as String?,
      );
    }).toList();
  }

  Future<void> saveListDetailItem(ListDetailItemModel item, {String syncStatus = 'synced'}) async {
    final database = await db;
    await database.insert(
      'list_detail_items',
      {
        'id_detalle': item.idDetalle,
        'id_lista_compra': item.idListaCompra,
        'id_articulo': item.idArticulo,
        'nb_articulo': item.nbArticulo,
        'ds_detalle': item.dsDetalle,
        'status': item.status,
        'fecha_compra': item.fechaCompra?.toIso8601String(),
        'id_usuario_finalizo': item.idUsuarioFinalizo,
        'id_usuario_agrego': item.idUsuarioAgrego,
        'sync_status': syncStatus,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveListDetailItemsBatch(List<ListDetailItemModel> items, {List<String>? activeListIds}) async {
    final database = await db;
    final batch = database.batch();
    if (activeListIds != null && activeListIds.isNotEmpty) {
      final placeholders = List.filled(activeListIds.length, '?').join(',');
      batch.delete(
        'list_detail_items',
        where: 'id_lista_compra IN ($placeholders) AND sync_status = ?',
        whereArgs: [...activeListIds, 'synced'],
      );
    }
    for (var item in items) {
      batch.insert(
        'list_detail_items',
        {
          'id_detalle': item.idDetalle,
          'id_lista_compra': item.idListaCompra,
          'id_articulo': item.idArticulo,
          'nb_articulo': item.nbArticulo,
          'ds_detalle': item.dsDetalle,
          'status': item.status,
          'fecha_compra': item.fechaCompra?.toIso8601String(),
          'id_usuario_finalizo': item.idUsuarioFinalizo,
          'id_usuario_agrego': item.idUsuarioAgrego,
          'sync_status': 'synced',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteListDetailItemLocally(String detailId) async {
    final database = await db;
    await database.delete('list_detail_items', where: 'id_detalle = ?', whereArgs: [detailId]);
  }

  // --- CATÁLOGO DE ARTÍCULOS ---
  Future<List<ItemCatalogModel>> getCatalogItems(String famId) async {
    final database = await db;
    final res = await database.query(
      'item_catalog',
      where: 'id_familia = ?',
      whereArgs: [famId],
    );
    return res.map((m) => ItemCatalogModel.fromMap(m)).toList();
  }

  Future<void> saveCatalogItems(List<ItemCatalogModel> items, {String famId = ''}) async {
    final database = await db;
    final batch = database.batch();
    if (famId.isNotEmpty) {
      batch.delete('item_catalog', where: 'id_familia = ? AND sync_status = ?', whereArgs: [famId, 'synced']);
    }
    for (var item in items) {
      batch.insert(
        'item_catalog',
        {
          'id_articulo': item.idArticulo,
          'id_familia': item.idFamilia,
          'nb_articulo_es': item.nbArticuloEs,
          'nb_articulo_en': item.nbArticuloEn,
          'nu_uso': item.nuUso,
          'sync_status': 'synced',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> saveCatalogItem(ItemCatalogModel item, {String syncStatus = 'synced'}) async {
    final database = await db;
    await database.insert(
      'item_catalog',
      {
        'id_articulo': item.idArticulo,
        'id_familia': item.idFamilia,
        'nb_articulo_es': item.nbArticuloEs,
        'nb_articulo_en': item.nbArticuloEn,
        'nu_uso': item.nuUso,
        'sync_status': syncStatus,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- COLA DE SINCRONIZACIÓN (SYNC QUEUE) ---
  Future<int> enqueueSyncItem({
    required String collectionName,
    required String action,
    required String entityId,
    required Map<String, dynamic> payload,
  }) async {
    final database = await db;
    final item = SyncQueueItem(
      collectionName: collectionName,
      action: action,
      entityId: entityId,
      payload: payload,
    );
    final id = await database.insert('sync_queue', item.toMap());
    debugPrint("[LOCAL_DB] Encolado cambio en sync_queue: #$id [$action] $collectionName ($entityId)");
    return id;
  }

  Future<List<SyncQueueItem>> getPendingSyncQueue() async {
    final database = await db;
    final res = await database.query(
      'sync_queue',
      orderBy: 'id ASC',
      limit: 100,
    );
    return res.map((m) => SyncQueueItem.fromMap(m)).toList();
  }

  Future<void> removeSyncQueueItem(int id) async {
    final database = await db;
    await database.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateSyncQueueRetry(int id, int currentRetries) async {
    final database = await db;
    await database.update(
      'sync_queue',
      {'retry_count': currentRetries + 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> getPendingSyncCount() async {
    final database = await db;
    final res = await database.rawQuery('SELECT COUNT(*) as count FROM sync_queue');
    return Sqflite.firstIntValue(res) ?? 0;
  }

  Future<Set<String>> getPendingEntityIds(String collectionName) async {
    final database = await db;
    final res = await database.query(
      'sync_queue',
      columns: ['entity_id'],
      where: 'collection_name = ?',
      whereArgs: [collectionName],
    );
    return res.map((r) => r['entity_id'] as String).toSet();
  }
}
