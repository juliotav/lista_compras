import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../config/mongo_config.dart';
import 'connectivity_service.dart';

class MongoService {
  static Db? _db;
  static Future<Db?>? _connectingFuture;

  static Future<Db?> _getDb() async {
    if (MongoConfig.mongoUri == "TU_MONGODB_URI_AQUI" || MongoConfig.mongoUri.isEmpty) {
      debugPrint("[MONGO SERVICE] ERROR: URI de MongoDB no está configurado.");
      return null;
    }

    // Si el dispositivo está sin conexión a internet, retornar null inmediatamente (0ms lag)
    if (ConnectivityService().isOffline) {
      return null;
    }

    if (_db != null) {
      if (_db!.isConnected) {
        return _db;
      } else {
        try {
          await _db?.close();
        } catch (_) {}
        _db = null;
      }
    }

    if (_connectingFuture != null) {
      return await _connectingFuture;
    }

    final future = () async {
      Db? dbInstance;
      try {
        debugPrint("[MONGO SERVICE] Conectando a MongoDB Atlas...");
        dbInstance = await Db.create(MongoConfig.mongoUri);
        await dbInstance.open().timeout(const Duration(seconds: 8));
        _db = dbInstance;
        debugPrint("[MONGO SERVICE] ¡Conexión exitosa a MongoDB!");
        return _db;
      } catch (e) {
        debugPrint("[MONGO SERVICE] Error de conexión a MongoDB (se reintentará automáticamente): $e");
        ConnectivityService().reportNetworkFailure();
        try {
          await dbInstance?.close();
        } catch (_) {}
        try {
          await _db?.close();
        } catch (_) {}
        _db = null;
        return null;
      } finally {
        _connectingFuture = null;
      }
    }();
    _connectingFuture = future;
    return await future;
  }

  /// Busca un documento en MongoDB Cloud
  static Future<Map<String, dynamic>?> findOne({
    required String collectionName,
    required Map<String, dynamic> filter,
  }) async {
    try {
      final db = await _getDb();
      if (db == null) return null;

      final collection = db.collection(collectionName);
      final res = await collection.findOne(filter).timeout(const Duration(seconds: 8));
      return res;
    } catch (e) {
      debugPrint("[MONGO SERVICE] findOne ERROR en $collectionName: $e");
      if (e is TimeoutException) {
        ConnectivityService().reportNetworkFailure();
      }
      _db = null;
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
      final res = await collection.find(filter).toList().timeout(const Duration(seconds: 8));
      return res;
    } catch (e) {
      debugPrint("[MONGO SERVICE] find ERROR en $collectionName: $e");
      if (e is TimeoutException) {
        ConnectivityService().reportNetworkFailure();
      }
      _db = null;
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
      final res = await collection.insertOne(document).timeout(const Duration(seconds: 8));
      return res.isSuccess || res.document != null;
    } catch (e) {
      debugPrint("[MONGO SERVICE] insertOne ERROR en $collectionName: $e");
      if (e is TimeoutException) {
        ConnectivityService().reportNetworkFailure();
      }
      _db = null;
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
      final res = await collection.insertMany(documents).timeout(const Duration(seconds: 8));
      debugPrint("[MONGO SERVICE] insertMany exitoso de ${documents.length} documentos en $collectionName");
      return res.isSuccess;
    } catch (e) {
      debugPrint("[MONGO SERVICE] insertMany ERROR en $collectionName: $e");
      if (e is TimeoutException) {
        ConnectivityService().reportNetworkFailure();
      }
      _db = null;
      return false;
    }
  }

  /// Actualiza un documento en MongoDB Cloud
  static Future<bool> updateOne({
    required String collectionName,
    required Map<String, dynamic> filter,
    required Map<String, dynamic> update,
    bool upsert = true,
  }) async {
    final db = await _getDb();
    if (db == null) return false;

    try {
      final collection = db.collection(collectionName);
      final res = await collection.updateOne(filter, update, upsert: upsert).timeout(const Duration(seconds: 8));
      return res.isSuccess || res.writeError == null;
    } catch (e) {
      debugPrint("[MONGO SERVICE] updateOne ERROR en $collectionName: $e");
      if (e is TimeoutException) {
        ConnectivityService().reportNetworkFailure();
      }
      _db = null;
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
      final res = await collection.deleteOne(filter).timeout(const Duration(seconds: 8));
      return res.isSuccess;
    } catch (e) {
      debugPrint("[MONGO SERVICE] deleteOne ERROR en $collectionName: $e");
      if (e is TimeoutException) {
        ConnectivityService().reportNetworkFailure();
      }
      _db = null;
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
      final res = await collection.deleteMany(filter).timeout(const Duration(seconds: 8));
      debugPrint("[MONGO SERVICE] deleteMany exitoso en $collectionName");
      return res.isSuccess;
    } catch (e) {
      debugPrint("[MONGO SERVICE] deleteMany ERROR en $collectionName: $e");
      if (e is TimeoutException) {
        ConnectivityService().reportNetworkFailure();
      }
      _db = null;
      return false;
    }
  }

  /// Ejecuta múltiples operaciones de actualización/inserción/eliminación en lote (bulkWrite) en una sola llamada de red a MongoDB Cloud
  static Future<bool> bulkWrite({
    required String collectionName,
    required List<Map<String, Object>> statements,
  }) async {
    if (statements.isEmpty) return true;
    final db = await _getDb();
    if (db == null) return false;

    try {
      final collection = db.collection(collectionName);
      final res = await collection.bulkWrite(statements).timeout(const Duration(seconds: 10));
      debugPrint("[MONGO SERVICE] bulkWrite exitoso de ${statements.length} operaciones en $collectionName");
      return res.isSuccess || res.writeErrors.isEmpty;
    } catch (e) {
      debugPrint("[MONGO SERVICE] bulkWrite ERROR en $collectionName: $e");
      if (e is TimeoutException) {
        ConnectivityService().reportNetworkFailure();
      }
      _db = null;
      return false;
    }
  }

  /// Cierra limpiamente la conexión activa de MongoDB si existe
  static Future<void> close() async {
    if (_db != null) {
      try {
        debugPrint("[MONGO SERVICE] Cerrando conexión de MongoDB por paso a segundo plano...");
        await _db?.close();
      } catch (e) {
        debugPrint("[MONGO SERVICE] Error cerrando conexión de MongoDB: $e");
      } finally {
        _db = null;
      }
    }
  }
}
