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

    if (senderUserId != null &&
        currentUserId != null &&
        senderUserId == currentUserId) {
      debugPrint(
        '[PUSH_NOTIF LOG] Omitiendo push en segundo plano: enviada por el propio usuario ($currentUserId).',
      );
      return;
    }

    // 2. Si FCM ya incluye el payload de notificación (message.notification != null), el SO Android/iOS
    // ya muestra la notificación nativa en segundo plano automáticamente.
    // Omitimos la llamada manual a FlutterLocalNotificationsPlugin para evitar notificaciones duplicadas.
    if (message.notification != null) {
      debugPrint(
        '[PUSH_NOTIF LOG] Notificación nativa ya mostrada por el SO. Omitiendo duplicado local en segundo plano.',
      );
      return;
    }

    final title =
        message.data['title']?.toString() ??
        message.notification?.title ??
        'Lista de Compras';
    final body =
        message.data['body']?.toString() ?? message.notification?.body ?? '';

    if (body.isEmpty) return;

    // 2. Mostrar la notificación local con sonido
    final localNotifications = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings(
      '@drawable/ic_notification',
    );
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
    await localNotifications.initialize(settings: initSettings);

    const androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'Notificaciones de Listas',
      channelDescription:
          'Canal para alertas con sonido de productos agregados a listas de compras.',
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
      id:
          (message.messageId ?? message.hashCode.toString()).hashCode &
          0x7FFFFFFF,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: jsonEncode(message.data),
    );
  } catch (e) {
    debugPrint(
      '[PUSH_NOTIF LOG] Error en firebaseMessagingBackgroundHandler: $e',
    );
  }
}

/// Servicio singleton para la gestión de Notificaciones Push (FCM + Backend Hostinger PHP)
class PushNotificationService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _isFirebaseInitialized = false;
  static final Set<String> _subscribedFamilyIds = {};
  static final Set<String> _pendingFamilyIdsToSync = {};
  static String? _lastHandledNotificationKey;
  static DateTime? _lastHandledNotificationTime;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel', // id
    'Notificaciones de Listas', // title
    description:
        'Canal para alertas con sonido de productos agregados a listas de compras.',
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

      debugPrint(
        '[PUSH_NOTIF LOG] Plataforma actual: ${defaultTargetPlatform.name.toUpperCase()} | Estado de permisos de notificación: ${settings.authorizationStatus}',
      );

      // Configurar presentación visual y sonora en primer plano para iOS (con timeout defensivo)
      try {
        await messaging
            .setForegroundNotificationPresentationOptions(
              alert: true,
              badge: true,
              sound: true,
            )
            .timeout(const Duration(seconds: 3));
      } catch (e) {
        debugPrint(
          '[PUSH_NOTIF LOG] Advertencia en setForegroundNotificationPresentationOptions: $e',
        );
      }

      // Inicializar plugin de notificaciones locales para Android / iOS
      const androidInit = AndroidInitializationSettings(
        '@drawable/ic_notification',
      );
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      );

      try {
        await _localNotifications
            .initialize(
              settings: initSettings,
              onDidReceiveNotificationResponse:
                  (NotificationResponse response) {
                    if (response.payload != null &&
                        response.payload!.isNotEmpty) {
                      try {
                        final data = jsonDecode(response.payload!);
                        if (data is Map<String, dynamic>) {
                          handleNotificationClick(data);
                        }
                      } catch (_) {}
                    }
                  },
            )
            .timeout(const Duration(seconds: 3));
      } catch (e) {
        debugPrint(
          '[PUSH_NOTIF LOG] Advertencia en _localNotifications.initialize: $e',
        );
      }

      // Crear canal de alta prioridad con sonido en Android
      try {
        await _localNotifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(_channel);
      } catch (_) {}

      // 1. Escuchar notificaciones recibidas en primer plano y reproducir sonido / mostrar banner
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        debugPrint(
          '[PUSH_NOTIF LOG] Notificación recibida en primer plano: ${message.notification?.title ?? message.data['title']} - ${message.notification?.body ?? message.data['body']}',
        );

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

        if (senderUserId != null &&
            currentUserId != null &&
            senderUserId == currentUserId) {
          debugPrint(
            '[PUSH_NOTIF LOG] Omitiendo notificación en primer plano: enviada por el propio usuario actual ($currentUserId).',
          );
          return;
        }

        final title =
            message.data['title']?.toString() ??
            message.notification?.title ??
            'Lista de Compras';
        final body =
            message.data['body']?.toString() ??
            message.notification?.body ??
            '';

        if (body.isNotEmpty && !kIsWeb) {
          try {
            final notifId =
                (message.messageId ?? message.hashCode.toString()).hashCode &
                0x7FFFFFFF;
            await _localNotifications.show(
              id: notifId,
              title: title,
              body: body,
              notificationDetails: const NotificationDetails(
                android: AndroidNotificationDetails(
                  'high_importance_channel',
                  'Notificaciones de Listas',
                  channelDescription:
                      'Canal para alertas con sonido de productos agregados a listas de compras.',
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
            debugPrint(
              '[PUSH_NOTIF LOG] Error al mostrar banner local en primer plano: $e',
            );
          }
        }
      });

      // 2. Escuchar clics en la notificación cuando la app está en segundo plano
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint(
          '[PUSH_NOTIF LOG] Notificación abierta desde segundo plano: ${message.data}',
        );
        handleNotificationClick(message.data);
      });

      // 3. Manejar apertura cuando la app estaba completamente cerrada (Cold Start vía FCM)
      try {
        final initialMessage = await messaging.getInitialMessage().timeout(
          const Duration(seconds: 3),
          onTimeout: () => null,
        );
        if (initialMessage != null) {
          debugPrint(
            '[PUSH_NOTIF LOG] Notificación abrió la app desde estado cerrado (FCM): ${initialMessage.data}',
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            handleNotificationClick(initialMessage.data);
          });
        }
      } catch (e) {
        debugPrint('[PUSH_NOTIF LOG] Nota al obtener initialMessage: $e');
      }

      // 4. Manejar apertura cuando la app estaba cerrada y se tocó una notificación local
      try {
        final localLaunchDetails = await _localNotifications
            .getNotificationAppLaunchDetails()
            .timeout(const Duration(seconds: 3), onTimeout: () => null);
        if (localLaunchDetails?.didNotificationLaunchApp ?? false) {
          final payload = localLaunchDetails?.notificationResponse?.payload;
          if (payload != null && payload.isNotEmpty) {
            try {
              final data = jsonDecode(payload);
              if (data is Map<String, dynamic>) {
                debugPrint(
                  '[PUSH_NOTIF LOG] Notificación local abrió la app desde estado cerrado: $data',
                );
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  handleNotificationClick(data);
                });
              }
            } catch (_) {}
          }
        }
      } catch (e) {
        debugPrint('[PUSH_NOTIF LOG] Nota al obtener localLaunchDetails: $e');
      }

      // 5. Iniciar monitoreo reactivo de APNs y FCM en segundo plano sin bloquear la UI
      _startApnsAndFcmSync(messaging);
    } catch (e) {
      debugPrint(
        '[PUSH_NOTIF LOG] Firebase no inicializado o sin archivo de configuración: $e',
      );
    }
  }

  /// Monitorea en segundo plano la entrega del token APNs y la sincronización con FCM
  static void _startApnsAndFcmSync(FirebaseMessaging messaging) {
    // Escuchar actualizaciones de token emitidas por Firebase
    messaging.onTokenRefresh.listen((newToken) {
      debugPrint('[PUSH_NOTIF LOG] Token FCM emitido/actualizado: $newToken');
      _flushPendingFamilySubscriptions(messaging);
    });

    Future.microtask(() async {
      try {
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          debugPrint(
            '[PUSH_NOTIF LOG] Iniciando verificación de token APNs de Apple...',
          );
          String? apnsToken;
          // Reintentar hasta 15 veces (15 * 1.5s = ~22 segundos)
          for (int i = 0; i < 15; i++) {
            apnsToken = await messaging.getAPNSToken();
            if (apnsToken != null) {
              debugPrint(
                '[PUSH_NOTIF LOG] ¡Token APNs asignado con éxito por Apple!: $apnsToken',
              );
              break;
            }
            await Future.delayed(const Duration(milliseconds: 1500));
          }

          if (apnsToken == null) {
            debugPrint(
              '[PUSH_NOTIF LOG] APNs token no estuvo disponible tras 22s. Si estás en un dispositivo físico, asegúrate de haber cerrado la app y recompilado completamente con "flutter run".',
            );
            return;
          }
        }

        // Obtener el token FCM una vez que APNs está garantizado
        final token = await messaging.getToken().timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        );
        if (token != null) {
          debugPrint(
            '[PUSH_NOTIF LOG] Token FCM del dispositivo listo: $token',
          );
        }

        // Sincronizar familias que hayan quedado pendientes
        await _flushPendingFamilySubscriptions(messaging);
      } catch (e) {
        debugPrint(
          '[PUSH_NOTIF LOG] Error durante la sincronización de tokens: $e',
        );
      }
    });
  }

  /// Ejecuta la suscripción de cualquier familia pendiente una vez que APNs esté disponible
  static Future<void> _flushPendingFamilySubscriptions(
    FirebaseMessaging messaging,
  ) async {
    if (_pendingFamilyIdsToSync.isEmpty) return;
    debugPrint(
      '[PUSH_NOTIF LOG] Sincronizando ${_pendingFamilyIdsToSync.length} familias pendientes tras disponibilidad de APNs...',
    );
    final toSync = _pendingFamilyIdsToSync.toList();
    _pendingFamilyIdsToSync.clear();
    await syncFamilySubscriptions(toSync);
  }

  /// Procesa el clic en la notificación: cambia de familia si es necesario y navega al detalle de la lista
  static Future<void> handleNotificationClick(Map<String, dynamic> data) async {
    final idFamilia = data['id_familia']?.toString();
    final idLista = data['id_lista']?.toString();
    final nbLista = data['nb_lista']?.toString();

    if (idFamilia == null ||
        idFamilia.isEmpty ||
        idLista == null ||
        idLista.isEmpty) {
      debugPrint(
        '[PUSH_NOTIF LOG] Datos incompletos en la notificación para navegación.',
      );
      return;
    }

    // Prevención de doble ejecución inmediata (ej. cold-start disparando FCM y localNotif simultáneamente)
    final notifKey = '$idFamilia:$idLista';
    final now = DateTime.now();
    if (_lastHandledNotificationKey == notifKey &&
        _lastHandledNotificationTime != null &&
        now.difference(_lastHandledNotificationTime!) <
            const Duration(seconds: 2)) {
      debugPrint(
        '[PUSH_NOTIF LOG] Ignorando clic duplicado en notificación ($notifKey).',
      );
      return;
    }
    _lastHandledNotificationKey = notifKey;
    _lastHandledNotificationTime = now;

    debugPrint(
      '[PUSH_NOTIF LOG] Procesando navegación a lista: $idLista en familia: $idFamilia',
    );

    // Esperar a que el contexto del Navigator y su estado estén disponibles
    int retries = 0;
    while ((navigatorKey.currentState == null ||
            navigatorKey.currentContext == null) &&
        retries < 50) {
      await Future.delayed(const Duration(milliseconds: 150));
      retries++;
    }

    final currentCtx = navigatorKey.currentContext;
    if (currentCtx == null || !currentCtx.mounted) {
      debugPrint(
        '[PUSH_NOTIF LOG] No se pudo obtener el contexto de navegación.',
      );
      return;
    }

    final db = Provider.of<DatabaseService>(currentCtx, listen: false);

    // Esperar a que el servicio de base de datos y la sesión inicial estén listos
    int dbRetries = 0;
    while (!db.isInitialized && dbRetries < 50) {
      await Future.delayed(const Duration(milliseconds: 100));
      dbRetries++;
    }

    if (db.currentUser == null) {
      debugPrint(
        '[PUSH_NOTIF LOG] Usuario no autenticado. Omitiendo apertura directa.',
      );
      return;
    }

    // 1. Si el usuario está posicionado en otra familia, cambiamos a la familia indicada en la notificación
    if (db.currentUser?.idFamilia != idFamilia) {
      debugPrint(
        '[PUSH_NOTIF LOG] Cambiando familia activa de ${db.currentUser?.idFamilia} a $idFamilia...',
      );
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
      try {
        targetList = db.shoppingLists.firstWhere(
          (l) => l.idListaCompra == idLista,
        );
      } catch (_) {
        // Fallback: Si aún no termina de indexar remotamente, construir un modelo de respaldo con los datos del payload
        targetList = ShoppingListModel(
          idListaCompra: idLista,
          idFamilia: idFamilia,
          nbLista: (nbLista != null && nbLista.isNotEmpty)
              ? nbLista
              : 'Lista de Compras',
          isActive: true,
        );
      }
    }

    // 3. Limpiar pantallas previas acumuladas y abrir la pantalla de detalle de la lista
    final nav = navigatorKey.currentState;
    if (nav != null) {
      nav.popUntil((route) => route.isFirst);
      nav.push(
        MaterialPageRoute(
          builder: (_) => ListDetailScreen(shoppingList: targetList!),
        ),
      );
    }
  }

  /// En iOS, espera de forma no bloqueante a que el APNs token esté listo antes de operar sobre topics
  static Future<bool> _ensureApnsTokenReady(FirebaseMessaging messaging) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return true;

    try {
      final currentToken = await messaging.getAPNSToken();
      if (currentToken != null) return true;

      debugPrint(
        '[PUSH_NOTIF LOG] Verificando disponibilidad inmediata de token APNs...',
      );
      for (int i = 0; i < 4; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final token = await messaging.getAPNSToken();
        if (token != null) {
          debugPrint('[PUSH_NOTIF LOG] Token APNs disponible para topics.');
          return true;
        }
      }
    } catch (e) {
      debugPrint('[PUSH_NOTIF LOG] Error verificando APNs token: $e');
    }
    return false;
  }

  /// Sincroniza las suscripciones de Firebase FCM para todas las familias a las que pertenece el usuario
  static Future<void> syncFamilySubscriptions(List<String> familyIds) async {
    if (kIsWeb || !_isFirebaseInitialized) return;

    try {
      final messaging = FirebaseMessaging.instance;
      final targetSet = familyIds.where((id) => id.isNotEmpty).toSet();

      // En iOS, garantizar que APNs esté disponible antes de llamar a subscribeToTopic
      final isReady = await _ensureApnsTokenReady(messaging);
      if (defaultTargetPlatform == TargetPlatform.iOS && !isReady) {
        debugPrint(
          '[PUSH_NOTIF LOG] APNs token no disponible de inmediato. Guardando ${targetSet.length} familias para sincronizar en onTokenRefresh.',
        );
        _pendingFamilyIdsToSync.addAll(targetSet);
        return;
      }

      // Desuscribir de topics que ya no corresponden
      for (final oldId in _subscribedFamilyIds.toList()) {
        if (!targetSet.contains(oldId)) {
          try {
            await messaging.unsubscribeFromTopic('family_$oldId');
            _subscribedFamilyIds.remove(oldId);
            debugPrint(
              '[PUSH_NOTIF LOG] Desuscrito de topic familiar: family_$oldId',
            );
          } catch (e) {
            debugPrint(
              '[PUSH_NOTIF LOG] Error al desuscribir de family_$oldId: $e',
            );
          }
        }
      }

      // Suscribir a cada una de las familias activas del usuario
      for (final famId in targetSet) {
        if (!_subscribedFamilyIds.contains(famId)) {
          try {
            await messaging.subscribeToTopic('family_$famId');
            _subscribedFamilyIds.add(famId);
            debugPrint(
              '[PUSH_NOTIF LOG] Suscrito exitosamente al topic: family_$famId',
            );
          } catch (e) {
            debugPrint(
              '[PUSH_NOTIF LOG] Error al suscribir a family_$famId: $e',
            );
            _pendingFamilyIdsToSync.add(famId);
          }
        }
      }
    } catch (e) {
      debugPrint(
        '[PUSH_NOTIF LOG] Error al sincronizar suscripciones familiares: $e',
      );
    }
  }

  /// Suscribe el dispositivo al topic de una familia específica
  static Future<void> subscribeToFamily(String? idFamilia) async {
    if (kIsWeb ||
        !_isFirebaseInitialized ||
        idFamilia == null ||
        idFamilia.isEmpty) {
      return;
    }

    try {
      final messaging = FirebaseMessaging.instance;
      final isReady = await _ensureApnsTokenReady(messaging);
      if (defaultTargetPlatform == TargetPlatform.iOS && !isReady) {
        _pendingFamilyIdsToSync.add(idFamilia);
        return;
      }
      await messaging.subscribeToTopic('family_$idFamilia');
      _subscribedFamilyIds.add(idFamilia);
      debugPrint(
        '[PUSH_NOTIF LOG] Suscrito exitosamente al topic: family_$idFamilia',
      );
    } catch (e) {
      debugPrint('[PUSH_NOTIF LOG] Error al suscribirse al topic familiar: $e');
    }
  }

  /// Desuscribe el dispositivo de un topic familiar específico
  static Future<void> unsubscribeFromFamily(String? idFamilia) async {
    if (kIsWeb ||
        !_isFirebaseInitialized ||
        idFamilia == null ||
        idFamilia.isEmpty) {
      return;
    }

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.unsubscribeFromTopic('family_$idFamilia');
      _subscribedFamilyIds.remove(idFamilia);
      debugPrint(
        '[PUSH_NOTIF LOG] Desuscrito de topic familiar: family_$idFamilia',
      );
    } catch (e) {
      debugPrint('[PUSH_NOTIF LOG] Error al desuscribirse de topic: $e');
    }
  }

  /// Desuscribe el dispositivo de todos los topics familiares activos (ej. al cerrar sesión)
  static Future<void> unsubscribeAllFamilies() async {
    if (kIsWeb || !_isFirebaseInitialized) return;

    try {
      final messaging = FirebaseMessaging.instance;
      for (final famId in _subscribedFamilyIds.toList()) {
        await messaging.unsubscribeFromTopic('family_$famId');
      }
      _subscribedFamilyIds.clear();
      debugPrint('[PUSH_NOTIF LOG] Desuscrito de todas las familias.');
    } catch (e) {
      debugPrint(
        '[PUSH_NOTIF LOG] Error al desuscribir de todas las familias: $e',
      );
    }
  }

  /// Alias de compatibilidad hacia atrás
  static Future<void> unsubscribeCurrentFamily() async {
    await unsubscribeAllFamilies();
  }

  /// Envía la petición HTTPS al script PHP en Hostinger para disparar el mensaje push a la familia
  static Future<bool> sendListProductsAddedNotification({
    required String idFamilia,
    String? nbFamilia,
    required String idListaCompra,
    required String nbLista,
    required String senderUserId,
    required String senderName,
  }) async {
    if (NotificationConfig.endpointUrl.isEmpty) {
      debugPrint('[PUSH_NOTIF LOG] Endpoint de notificaciones no configurado.');
      return false;
    }

    final String familySuffix =
        (nbFamilia != null && nbFamilia.trim().isNotEmpty)
        ? ' (Familia: ${nbFamilia.trim()})'
        : '';

    final payload = {
      'id_familia': idFamilia,
      'nb_familia': nbFamilia?.trim() ?? '',
      'id_lista': idListaCompra,
      'nb_lista': nbLista,
      'sender_user_id': senderUserId,
      'sender_name': senderName,
      'title': 'Lista de Compras',
      'body':
          '$senderName ha agregado productos a la lista "$nbLista"$familySuffix',
    };

    try {
      debugPrint(
        '[PUSH_NOTIF LOG] Enviando petición push a ${NotificationConfig.endpointUrl}...',
      );
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
        debugPrint(
          '[PUSH_NOTIF LOG] Push enviado con éxito a la familia (FCM distribuirá a Android y Apple iOS): ${response.body}',
        );
        return true;
      } else {
        debugPrint(
          '[PUSH_NOTIF LOG] Error del servidor PHP (${response.statusCode}): ${response.body}',
        );
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
    String? nbFamilia,
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

    final String familySuffix =
        (nbFamilia != null && nbFamilia.trim().isNotEmpty)
        ? ' (Familia: ${nbFamilia.trim()})'
        : '';

    final String bodyText =
        (productName != null && productName.trim().isNotEmpty)
        ? '$senderName ha marcado "$productName" como comprado en "$nbLista"$familySuffix'
        : '$senderName ha marcado productos como comprados en "$nbLista"$familySuffix';

    final payload = {
      'id_familia': idFamilia,
      'nb_familia': nbFamilia?.trim() ?? '',
      'id_lista': idListaCompra,
      'nb_lista': nbLista,
      'sender_user_id': senderUserId,
      'sender_name': senderName,
      'title': 'Lista de Compras',
      'body': bodyText,
    };

    try {
      debugPrint(
        '[PUSH_NOTIF LOG] Enviando petición push de compra a ${NotificationConfig.endpointUrl}...',
      );
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
        debugPrint(
          '[PUSH_NOTIF LOG] Push de compra enviado con éxito a la familia (FCM distribuirá a Android y Apple iOS): ${response.body}',
        );
        return true;
      } else {
        debugPrint(
          '[PUSH_NOTIF LOG] Error del servidor PHP (${response.statusCode}): ${response.body}',
        );
        return false;
      }
    } catch (e) {
      debugPrint(
        '[PUSH_NOTIF LOG] Excepción al enviar notificación push de compra: $e',
      );
      return false;
    }
  }
}
