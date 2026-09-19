import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class MongoConfig {
  /// Cadena de conexión URI de tu base de datos en MongoDB Atlas
  static String mongoUri =
      "mongodb+srv://lista_compras_user:SR4aWABFrn9mMBw@agenda-servicios.ekqaaeb.mongodb.net/lista_compras?retryWrites=true&w=majority&safeAtlas=true";

  /// Nombre de la base de datos
  static const String databaseName = "lista_compras";

  /// Nombres exactos de tus Colecciones (Coincidiendo exactamente con tu panel de MongoDB Atlas)
  static const String colUsuario = "usuario";
  static const String colFamilia = "familia";
  static const String colListasCompra =
      "lista_compra"; // Nombre exacto en singular
  static const String colCArticulo = "c_articulo";
  static const String colUsuarioFamilia = "usuario_familia";
  static const String colDetalleLista = "detalle_lista_compra";
  static const String colAppVersion = "app_version";

  /// Nombre identificador de la aplicación en MongoDB
  static const String appName = "listalista";

  static String _cachedAppVersion = "";

  /// Carga la versión real directamente desde el archivo pubspec.yaml
  static Future<String> loadAppVersionFromPubspec() async {
    if (_cachedAppVersion.isNotEmpty) return _cachedAppVersion;
    if (kIsWeb) {
      _cachedAppVersion = "1.0.20";
      return _cachedAppVersion;
    }
    try {
      final info = await PackageInfo.fromPlatform();
      final ver = info.version.split('+').first.trim();
      if (ver.isNotEmpty) {
        _cachedAppVersion = ver;
      }
    } catch (e) {
      debugPrint("[MONGO_CONFIG LOG] Error leyendo versión de pubspec.yaml: $e");
    }
    return appVersion;
  }

  /// Retorna la versión visible y de validación (sin número de compilación +x).
  /// Se obtiene automáticamente de pubspec.yaml.
  static String get appVersion {
    if (_cachedAppVersion.isNotEmpty) return _cachedAppVersion;
    return "1.0.20";
  }

  /// Retorna la URL de la tienda según el entorno (QA vs PR)
  static String get storeUrl {
    const env = String.fromEnvironment('ENV', defaultValue: 'qa');
    if (env.trim().toLowerCase() == 'pr') {
      // Placeholder para producción
      return 'https://play.google.com/store/apps/details?id=com.sonorodevs.lista_compras'; // TODO: Reemplazar con la URL real de Producción cuando esté disponible
    }
    // Entorno QA / Closed Testing
    return 'https://play.google.com/store/apps/details?id=com.sonorodevs.lista_compras';
  }
}
