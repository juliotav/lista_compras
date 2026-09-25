import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }
    application.registerForRemoteNotifications()

    // Restablecer el badge del icono al abrir la aplicación
    AppDelegate.clearBadgeCount()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    // Limpiar el badge cada vez que la app pasa a primer plano / activa
    AppDelegate.clearBadgeCount()
  }

  /// Limpia el número de notificación (badge) en el icono de la aplicación en iOS
  static func clearBadgeCount() {
    if #available(iOS 16.0, *) {
      UNUserNotificationCenter.current().setBadgeCount(0) { error in
        if let error = error {
          print("[IOS BADGE] Error al restablecer badge count: \(error.localizedDescription)")
        } else {
          print("[IOS BADGE] Badge restablecido a 0 con éxito (iOS 16+)")
        }
      }
    } else {
      UIApplication.shared.applicationIconBadgeNumber = 0
      print("[IOS BADGE] Badge restablecido a 0 con éxito (iOS <16)")
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    print("[IOS NATIVE APNS] Device Token recibido exitosamente: \(token)")
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("[IOS NATIVE APNS] Error al registrar con Apple APNs: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger: FlutterBinaryMessenger
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BadgePlugin") {
      messenger = registrar.messenger()
    } else {
      messenger = engineBridge.applicationRegistrar.messenger()
    }

    let badgeChannel = FlutterMethodChannel(name: "com.andylu.lista_compras/badge", binaryMessenger: messenger)
    badgeChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "clearBadge" {
        AppDelegate.clearBadgeCount()
        result(true)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

