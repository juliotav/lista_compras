class NotificationConfig {
  /// URL del endpoint PHP seguro en tu servidor Hostinger
  static const String endpointUrl = String.fromEnvironment(
    'NOTIFICATION_ENDPOINT_URL',
    defaultValue:
        'https://yellowgreen-fly-883530.hostingersite.com/api/notification/notify.php',
    // defaultValue: 'http://10.0.2.2/lista-api/notify.php',
  );

  /// Clave secreta compartida para autorizar las peticiones entre la app móvil y el script PHP
  static const String appSecret = String.fromEnvironment(
    'NOTIFICATION_APP_SECRET',
    defaultValue: 'sonorodevs_push_secret_key_2026',
  );

  /// Tiempo de espera / Cooldown entre notificaciones por cada lista de compras
  static const Duration listNotificationCooldown = Duration(minutes: 10);
}
