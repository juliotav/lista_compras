import 'package:flutter/foundation.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../config/mongo_config.dart';

class MongoService {
  static Db? _db;
  static Future<Db?>? _connectingFuture;

  static Future<Db?> _getDb() async {
    if (MongoConfig.mongoUri == "TU_MONGODB_URI_AQUI" || MongoConfig.mongoUri.isEmpty) {
      debugPrint("[MONGO SERVICE] ERROR: URI de MongoDB no está configurado.");
      return null;
    }

    if (_db != null && _db!.isConnected) {
      return _db;
    }

    if (_connectingFuture != null) {
      return await _connectingFuture;
    }

    _connectingFuture = () async {
      try {
        debugPrint("[MONGO SERVICE] Conectando a MongoDB Atlas...");
        final dbInstance = await Db.create(MongoConfig.mongoUri);
        await dbInstance.open();
        _db = dbInstance;
        debugPrint("[MONGO SERVICE] ¡Conexión exitosa a MongoDB!");
        return _db;
      } catch (e) {
        debugPrint("[MONGO SERVICE] ERROR DE CONEXIÓN A MONGODB: $e");
        _db = null;
        return null;
      } finally {
        _connectingFuture = null;
      }
    }();

    return await _connectingFuture;
  }

  /// Busca un documento en MongoDB Cloud
  static Future<Map<String, dynamic>?> findOne({
    required String collectionName,
    required Map<String, dynamic> filter,
  }) async {
    final db = await _getDb();
    if (db == null) {
      debugPrint("[MONGO SERVICE] db es null. No se pudo realizar findOne en '$collectionName'");
      return null;
    }

    try {
      final collection = db.collection(collectionName);
      final res = await collection.findOne(filter);
      return res;
    } catch (e) {
      debugPrint("[MONGO SERVICE] findOne ERROR en $collectionName con filtro $filter: $e");
      return null;
    }
  }

  /// Busca múltiples documentos en MongoDB Cloud
  static Future<List<Map<String, dynamic>>> find({
    required String collectionName,
    required Map<String, dynamic> filter,
  }) async {
    final db = await _getDb();
    if (db == null) return [];

    try {
      final collection = db.collection(collectionName);
      final res = await collection.find(filter).toList();
      return res;
    } catch (_) {
      return [];
    }
  }

  /// Inserta un nuevo documento en MongoDB Cloud
  static Future<bool> insertOne({
    required String collectionName,
    required Map<String, dynamic> document,
  }) async {
    final db = await _getDb();
    if (db == null) return false;

    try {
      final collection = db.collection(collectionName);
      final res = await collection.insertOne(document);
      return res.isSuccess || res.document != null;
    } catch (_) {
      return false;
    }
  }

  /// Inserta múltiples documentos en lote en MongoDB Cloud
  static Future<bool> insertMany({
    required String collectionName,
    required List<Map<String, dynamic>> documents,
  }) async {
    if (documents.isEmpty) return true;
    final db = await _getDb();
    if (db == null) return false;

    try {
      final collection = db.collection(collectionName);
      final res = await collection.insertMany(documents);
      debugPrint("[MONGO SERVICE] insertMany exitoso de ${documents.length} documentos en $collectionName");
      return res.isSuccess;
    } catch (e) {
      debugPrint("[MONGO SERVICE] insertMany ERROR en $collectionName: $e");
      return false;
    }
  }

  /// Actualiza un documento en MongoDB Cloud
  static Future<bool> updateOne({
    required String collectionName,
    required Map<String, dynamic> filter,
    required Map<String, dynamic> update,
  }) async {
    final db = await _getDb();
    if (db == null) return false;

    try {
      final collection = db.collection(collectionName);
      final res = await collection.updateOne(filter, update);
      return res.isSuccess || res.writeError == null;
    } catch (_) {
      return false;
    }
  }

  /// Elimina un documento en MongoDB Cloud
  static Future<bool> deleteOne({
    required String collectionName,
    required Map<String, dynamic> filter,
  }) async {
    final db = await _getDb();
    if (db == null) return false;

    try {
      final collection = db.collection(collectionName);
      final res = await collection.deleteOne(filter);
      return res.isSuccess;
    } catch (_) {
      return false;
    }
  }

  /// Elimina múltiples documentos que coincidan con el filtro en MongoDB Cloud
  static Future<bool> deleteMany({
    required String collectionName,
    required Map<String, dynamic> filter,
  }) async {
    final db = await _getDb();
    if (db == null) return false;

    try {
      final collection = db.collection(collectionName);
      final res = await collection.deleteMany(filter);
      debugPrint("[MONGO SERVICE] deleteMany exitoso en $collectionName");
      return res.isSuccess;
    } catch (e) {
      debugPrint("[MONGO SERVICE] deleteMany ERROR en $collectionName: $e");
      return false;
    }
  }
}
