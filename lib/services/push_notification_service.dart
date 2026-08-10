import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/notification_config.dart';

/// Servicio singleton para la gestión de Notificaciones Push (FCM + Backend Hostinger PHP)
class PushNotificationService {
  static bool _isFirebaseInitialized = false;
  static String? _currentSubscribedFamilyId;

  /// Inicializa Firebase y solicita permisos en Android 13+ e iOS
  static Future<void> initialize() async {
    if (kIsWeb) return;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _isFirebaseInitialized = true;

      final messaging = FirebaseMessaging.instance;

      // Solicitar permisos de notificación (Requerido en iOS y Android 13+)
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint('[PUSH_NOTIF LOG] Estado de permisos de notificación: ${settings.authorizationStatus}');

      // Escuchar notificaciones recibidas con la app en primer plano
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('[PUSH_NOTIF LOG] Notificación recibida en primer plano: ${message.notification?.title} - ${message.notification?.body}');
      });

      // Obtener token FCM para depuración
      final token = await messaging.getToken();
      debugPrint('[PUSH_NOTIF LOG] Token FCM del dispositivo: $token');
    } catch (e) {
      debugPrint('[PUSH_NOTIF LOG] Firebase no inicializado o sin archivo de configuración: $e');
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
}
