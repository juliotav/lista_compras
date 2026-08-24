import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/notification_config.dart';
import '../models/shopping_list_model.dart';
import '../screens/list_detail_screen.dart';
import 'database_service.dart';
import 'local_db_service.dart';

/// Manejador de notificaciones en segundo plano (cuando la app está cerrada o minimizada)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }

    final senderUserId = message.data['sender_user_id']?.toString();

    // 1. Verificar si la notificación fue enviada por el mismo usuario
    String? currentUserId;
    try {
      final prefs = await SharedPreferences.getInstance();
      currentUserId = prefs.getString('session_user_id');
    } catch (_) {}
    if (currentUserId == null || currentUserId.isEmpty) {
      try {
        currentUserId = await LocalDbService().getSessionUserId();
      } catch (_) {}
    }

    if (senderUserId != null && currentUserId != null && senderUserId == currentUserId) {
      debugPrint('[PUSH_NOTIF LOG] Omitiendo push en segundo plano: enviada por el propio usuario ($currentUserId).');
      return;
    }

    // 2. Si FCM ya incluye el payload de notificación (message.notification != null), el SO Android/iOS
    // ya muestra la notificación nativa en segundo plano automáticamente.
    // Omitimos la llamada manual a FlutterLocalNotificationsPlugin para evitar notificaciones duplicadas.
    if (message.notification != null) {
      debugPrint('[PUSH_NOTIF LOG] Notificación nativa ya mostrada por el SO. Omitiendo duplicado local en segundo plano.');
      return;
    }

    final title = message.data['title']?.toString() ?? message.notification?.title ?? 'Lista de Compras';
    final body = message.data['body']?.toString() ?? message.notification?.body ?? '';

    if (body.isEmpty) return;

    // 2. Mostrar la notificación local con sonido
    final localNotifications = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@drawable/ic_notification');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
    await localNotifications.initialize(settings: initSettings);

    const androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'Notificaciones de Listas',
      channelDescription: 'Canal para alertas con sonido de productos agregados a listas de compras.',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@drawable/ic_notification',
      color: Color(0xFFFFFFFF),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await localNotifications.show(
      id: (message.messageId ?? message.hashCode.toString()).hashCode & 0x7FFFFFFF,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: jsonEncode(message.data),
    );
  } catch (e) {
    debugPrint('[PUSH_NOTIF LOG] Error en firebaseMessagingBackgroundHandler: $e');
  }
}

/// Servicio singleton para la gestión de Notificaciones Push (FCM + Backend Hostinger PHP)
class PushNotificationService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  static bool _isFirebaseInitialized = false;
  static String? _currentSubscribedFamilyId;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel', // id
    'Notificaciones de Listas', // title
    description: 'Canal para alertas con sonido de productos agregados a listas de compras.',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  /// Inicializa Firebase, notificaciones locales y configura listeners con sonido en primer plano
  static Future<void> initialize() async {
    if (kIsWeb) return;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _isFirebaseInitialized = true;

      // Registrar manejador de segundo plano
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;

      // Solicitar permisos de notificación (Requerido en iOS y Android 13+)
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint('[PUSH_NOTIF LOG] Estado de permisos de notificación: ${settings.authorizationStatus}');

      // Configurar presentación visual y sonora en primer plano para iOS
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Inicializar plugin de notificaciones locales para Android / iOS
      const androidInit = AndroidInitializationSettings('@drawable/ic_notification');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);

      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          if (response.payload != null && response.payload!.isNotEmpty) {
            try {
              final data = jsonDecode(response.payload!);
              if (data is Map<String, dynamic>) {
                handleNotificationClick(data);
              }
            } catch (_) {}
          }
        },
      );

      // Crear canal de alta prioridad con sonido en Android
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      // 1. Escuchar notificaciones recibidas en primer plano y reproducir sonido / mostrar banner
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        debugPrint('[PUSH_NOTIF LOG] Notificación recibida en primer plano: ${message.notification?.title ?? message.data['title']} - ${message.notification?.body ?? message.data['body']}');

        // Filtrar para NO notificar al propio usuario que agregó los productos
        final senderUserId = message.data['sender_user_id']?.toString();
        String? currentUserId;
        try {
          final prefs = await SharedPreferences.getInstance();
          currentUserId = prefs.getString('session_user_id');
        } catch (_) {}
        if (currentUserId == null || currentUserId.isEmpty) {
          try {
            currentUserId = await LocalDbService().getSessionUserId();
          } catch (_) {}
        }

        if (senderUserId != null && currentUserId != null && senderUserId == currentUserId) {
          debugPrint('[PUSH_NOTIF LOG] Omitiendo notificación en primer plano: enviada por el propio usuario actual ($currentUserId).');
          return;
        }

        final title = message.data['title']?.toString() ?? message.notification?.title ?? 'Lista de Compras';
        final body = message.data['body']?.toString() ?? message.notification?.body ?? '';

        if (body.isNotEmpty && !kIsWeb) {
          try {
            final notifId = (message.messageId ?? message.hashCode.toString()).hashCode & 0x7FFFFFFF;
            await _localNotifications.show(
              id: notifId,
              title: title,
              body: body,
              notificationDetails: const NotificationDetails(
                android: AndroidNotificationDetails(
                  'high_importance_channel',
                  'Notificaciones de Listas',
                  channelDescription: 'Canal para alertas con sonido de productos agregados a listas de compras.',
                  importance: Importance.high,
                  priority: Priority.high,
                  playSound: true,
                  enableVibration: true,
                  icon: '@drawable/ic_notification',
                  color: Color(0xFFFFFFFF),
                ),
                iOS: DarwinNotificationDetails(
                  presentAlert: true,
                  presentBadge: true,
                  presentSound: true,
                ),
              ),
              payload: jsonEncode(message.data),
            );
          } catch (e) {
            debugPrint('[PUSH_NOTIF LOG] Error al mostrar banner local en primer plano: $e');
          }
        }
      });

      // 2. Escuchar clics en la notificación cuando la app está en segundo plano
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('[PUSH_NOTIF LOG] Notificación abierta desde segundo plano: ${message.data}');
        handleNotificationClick(message.data);
      });

      // 3. Manejar apertura cuando la app estaba completamente cerrada (Cold Start vía FCM)
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('[PUSH_NOTIF LOG] Notificación abrió la app desde estado cerrado (FCM): ${initialMessage.data}');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          handleNotificationClick(initialMessage.data);
        });
      }

      // 4. Manejar apertura cuando la app estaba cerrada y se tocó una notificación local
      final localLaunchDetails = await _localNotifications.getNotificationAppLaunchDetails();
      if (localLaunchDetails?.didNotificationLaunchApp ?? false) {
        final payload = localLaunchDetails?.notificationResponse?.payload;
        if (payload != null && payload.isNotEmpty) {
          try {
            final data = jsonDecode(payload);
            if (data is Map<String, dynamic>) {
              debugPrint('[PUSH_NOTIF LOG] Notificación local abrió la app desde estado cerrado: $data');
              WidgetsBinding.instance.addPostFrameCallback((_) {
                handleNotificationClick(data);
              });
            }
          } catch (_) {}
        }
      }

      // Obtener token FCM para depuración
      final token = await messaging.getToken();
      debugPrint('[PUSH_NOTIF LOG] Token FCM del dispositivo: $token');
    } catch (e) {
      debugPrint('[PUSH_NOTIF LOG] Firebase no inicializado o sin archivo de configuración: $e');
    }
  }

  /// Procesa el clic en la notificación: cambia de familia si es necesario y navega al detalle de la lista
  static Future<void> handleNotificationClick(Map<String, dynamic> data) async {
    final idFamilia = data['id_familia']?.toString();
    final idLista = data['id_lista']?.toString();
    final nbLista = data['nb_lista']?.toString();

    if (idFamilia == null || idFamilia.isEmpty || idLista == null || idLista.isEmpty) {
      debugPrint('[PUSH_NOTIF LOG] Datos incompletos en la notificación para navegación.');
      return;
    }

    debugPrint('[PUSH_NOTIF LOG] Procesando navegación a lista: $idLista en familia: $idFamilia');

    // Esperar a que el contexto del Navigator esté disponible
    int retries = 0;
    while (navigatorKey.currentContext == null && retries < 20) {
      await Future.delayed(const Duration(milliseconds: 150));
      retries++;
    }

    final currentCtx = navigatorKey.currentContext;
    if (currentCtx == null || !currentCtx.mounted) {
      debugPrint('[PUSH_NOTIF LOG] No se pudo obtener el contexto de navegación.');
      return;
    }

    final db = Provider.of<DatabaseService>(currentCtx, listen: false);

    // Esperar a que el servicio de base de datos y la sesión inicial estén listos
    while (!db.isInitialized) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (db.currentUser == null) {
      debugPrint('[PUSH_NOTIF LOG] Usuario no autenticado. Omitiendo apertura directa.');
      return;
    }

    // 1. Si el usuario tiene seleccionada otra familia, cambiamos a la familia de la lista
    if (db.currentUser?.idFamilia != idFamilia) {
      debugPrint('[PUSH_NOTIF LOG] Cambiando familia activa de ${db.currentUser?.idFamilia} a $idFamilia...');
      await db.switchFamily(idFamilia);
    } else {
      await db.fetchFamilyData();
    }

    // 2. Localizar la lista de compras dentro de la familia
    ShoppingListModel? targetList;
    try {
      targetList = db.shoppingLists.firstWhere(
        (l) => l.idListaCompra == idLista && l.isActive,
      );
    } catch (_) {
      // Fallback: Si aún no termina de indexar remotamente, construir un modelo de respaldo con los datos del payload
      targetList = ShoppingListModel(
        idListaCompra: idLista,
        idFamilia: idFamilia,
        nbLista: nbLista?.isNotEmpty == true ? nbLista! : 'Lista de Compras',
        isActive: true,
      );
    }

    // 3. Abrir la pantalla de detalle de la lista
    final nav = navigatorKey.currentState;
    if (nav != null) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => ListDetailScreen(shoppingList: targetList!),
        ),
      );
    }
  }

  /// Suscribe el dispositivo al topic de la familia activa para recibir avisos grupales
  static Future<void> subscribeToFamily(String? idFamilia) async {
    if (kIsWeb || !_isFirebaseInitialized || idFamilia == null || idFamilia.isEmpty) return;

    try {
      final messaging = FirebaseMessaging.instance;

      // Desuscribir de la familia anterior si cambió
      if (_currentSubscribedFamilyId != null && _currentSubscribedFamilyId != idFamilia) {
        await messaging.unsubscribeFromTopic('family_$_currentSubscribedFamilyId');
        debugPrint('[PUSH_NOTIF LOG] Desuscrito del topic: family_$_currentSubscribedFamilyId');
      }

      // Suscribir al nuevo topic de la familia
      await messaging.subscribeToTopic('family_$idFamilia');
      _currentSubscribedFamilyId = idFamilia;
      debugPrint('[PUSH_NOTIF LOG] Suscrito exitosamente al topic: family_$idFamilia');
    } catch (e) {
      debugPrint('[PUSH_NOTIF LOG] Error al suscribirse al topic familiar: $e');
    }
  }

  /// Desuscribe el dispositivo de cualquier topic familiar activo (ej. al cerrar sesión)
  static Future<void> unsubscribeCurrentFamily() async {
    if (kIsWeb || !_isFirebaseInitialized || _currentSubscribedFamilyId == null) return;

    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic('family_$_currentSubscribedFamilyId');
      debugPrint('[PUSH_NOTIF LOG] Desuscrito de topic familiar: family_$_currentSubscribedFamilyId');
      _currentSubscribedFamilyId = null;
    } catch (e) {
      debugPrint('[PUSH_NOTIF LOG] Error al desuscribir de topic: $e');
    }
  }

  /// Envía la petición HTTPS al script PHP en Hostinger para disparar el mensaje push a la familia
  static Future<bool> sendListProductsAddedNotification({
    required String idFamilia,
    required String idListaCompra,
    required String nbLista,
    required String senderUserId,
    required String senderName,
  }) async {
    if (NotificationConfig.endpointUrl.isEmpty) {
      debugPrint('[PUSH_NOTIF LOG] Endpoint de notificaciones no configurado.');
      return false;
    }

    final payload = {
      'id_familia': idFamilia,
      'id_lista': idListaCompra,
      'nb_lista': nbLista,
      'sender_user_id': senderUserId,
      'sender_name': senderName,
      'title': 'Lista de Compras',
      'body': '$senderName ha agregado productos a la lista "$nbLista"',
    };

    try {
      debugPrint('[PUSH_NOTIF LOG] Enviando petición push a ${NotificationConfig.endpointUrl}...');
      final response = await http
          .post(
            Uri.parse(NotificationConfig.endpointUrl),
            headers: {
              'Content-Type': 'application/json',
              'X-App-Secret': NotificationConfig.appSecret,
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        debugPrint('[PUSH_NOTIF LOG] Push enviado con éxito: ${response.body}');
        return true;
      } else {
        debugPrint('[PUSH_NOTIF LOG] Error del servidor PHP (${response.statusCode}): ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[PUSH_NOTIF LOG] Excepción al enviar notificación push: $e');
      return false;
    }
  }

  /// Envía notificación push a los integrantes de la familia cuando un usuario marca productos como comprados
  static Future<bool> sendListProductsPurchasedNotification({
    required String idFamilia,
    required String idListaCompra,
    required String nbLista,
    required String senderUserId,
    required String senderName,
    String? productName,
  }) async {
    if (NotificationConfig.endpointUrl.isEmpty) {
      debugPrint('[PUSH_NOTIF LOG] Endpoint de notificaciones no configurado.');
      return false;
    }

    final String bodyText = (productName != null && productName.trim().isNotEmpty)
        ? '$senderName ha marcado "$productName" como comprado en "$nbLista"'
        : '$senderName ha marcado productos como comprados en "$nbLista"';

    final payload = {
      'id_familia': idFamilia,
      'id_lista': idListaCompra,
      'nb_lista': nbLista,
      'sender_user_id': senderUserId,
      'sender_name': senderName,
      'title': 'Lista de Compras',
      'body': bodyText,
    };

    try {
      debugPrint('[PUSH_NOTIF LOG] Enviando petición push de compra a ${NotificationConfig.endpointUrl}...');
      final response = await http
          .post(
            Uri.parse(NotificationConfig.endpointUrl),
            headers: {
              'Content-Type': 'application/json',
              'X-App-Secret': NotificationConfig.appSecret,
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        debugPrint('[PUSH_NOTIF LOG] Push de compra enviado con éxito: ${response.body}');
        return true;
      } else {
        debugPrint('[PUSH_NOTIF LOG] Error del servidor PHP (${response.statusCode}): ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[PUSH_NOTIF LOG] Excepción al enviar notificación push de compra: $e');
      return false;
    }
  }
}
