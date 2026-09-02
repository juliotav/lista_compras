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

  /// Versión visible para el usuario en la aplicación (sin número de compilación)
  static const String appVersion = "1.0.17";

  /// Retorna la URL de la tienda según el entorno (QA vs PR)
  static String get storeUrl {
    const env = String.fromEnvironment('ENV', defaultValue: 'qa');
    if (env.trim().toLowerCase() == 'pr') {
      // Placeholder para producción
      return 'https://play.google.com/store/apps/details?id=com.sonorodevs.lista_compras.prod'; // TODO: Reemplazar con la URL real de Producción cuando esté disponible
    }
    // Entorno QA / Closed Testing
    return 'https://play.google.com/store/apps/details?id=com.sonorodevs.lista_compras';
  }
}
