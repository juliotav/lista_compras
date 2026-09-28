import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class EmailService {
  /// Clave API de Resend (Se puede configurar vía --dart-define=RESEND_API_KEY=tu_clave)
  static String resendApiKey = const String.fromEnvironment(
    'RESEND_API_KEY',
    defaultValue: "TU_RESEND_API_KEY_AQUI",
  );

  /// Correo emisor configurado en Resend (ej: "Lista de Compras (noreply@tudominio.com)")
  static String fromEmail = "Lista de Compras <noreply@sonorodevs.com>";

  /// Envía un correo con el PIN de restablecimiento de contraseña usando la API de Resend
  static Future<bool> sendResetPinEmail({
    required String toEmail,
    required String pinCode,
  }) async {
    if (resendApiKey == "TU_RESEND_API_KEY_AQUI" || resendApiKey.isEmpty) {
      debugPrint(
        "[EMAIL_SERVICE LOG] AVISO: resendApiKey no configurado. PIN generado para $toEmail: '$pinCode'",
      );
      // Retornamos true en modo de desarrollo/pruebas para que puedas probar la interfaz antes de pegar tu API Key real
      return true;
    }

    final url = Uri.parse('https://api.resend.com/emails');

    final htmlContent =
        '''
    <div style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; max-width: 500px; margin: 0 auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 12px; background-color: #ffffff;">
      <div style="text-align: center; margin-bottom: 20px;">
        <h2 style="color: #673ab7; margin: 0;">Lista de Compras</h2>
        <p style="color: #666666; font-size: 14px; margin-top: 4px;">Recuperación de Contraseña</p>
      </div>
      <div style="background-color: #f5f2ff; padding: 20px; border-radius: 8px; text-align: center; margin-bottom: 20px;">
        <p style="font-size: 14px; color: #333333; margin-bottom: 8px;">Tu código de verificación de 6 dígitos es:</p>
        <h1 style="color: #673ab7; letter-spacing: 6px; font-size: 32px; margin: 10px 0;">$pinCode</h1>
        <p style="font-size: 12px; color: #888888; margin-top: 8px;">Este código expira en 10 minutos.</p>
      </div>
      <p style="font-size: 13px; color: #555555;">Si no solicitaste este cambio, puedes ignorar este correo de forma segura.</p>
    </div>
    ''';

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $resendApiKey',
        },
        body: jsonEncode({
          'from': fromEmail,
          'to': [toEmail],
          'subject': 'Código de recuperación de contraseña: $pinCode',
          'html': htmlContent,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint(
          "[EMAIL_SERVICE LOG] Correo enviado exitosamente a $toEmail vía Resend.",
        );
        return true;
      } else {
        debugPrint(
          "[EMAIL_SERVICE LOG] Error enviando correo vía Resend (${response.statusCode}): ${response.body}",
        );
        return false;
      }
    } catch (e) {
      debugPrint("[EMAIL_SERVICE LOG] Excepción en EmailService: $e");
      return false;
    }
  }

  /// Envía un correo con el código de activación de cuenta usando la API de Resend
  static Future<bool> sendActivationCodeEmail({
    required String toEmail,
    required String pinCode,
    String? userName,
  }) async {
    if (resendApiKey == "TU_RESEND_API_KEY_AQUI" || resendApiKey.isEmpty) {
      debugPrint(
        "[EMAIL_SERVICE LOG] AVISO: resendApiKey no configurado. Código de activación generado para $toEmail: '$pinCode'",
      );
      return true;
    }

    final url = Uri.parse('https://api.resend.com/emails');
    final nameHeader = (userName != null && userName.trim().isNotEmpty)
        ? 'Hola ${userName.trim()},'
        : '¡Hola!';

    final htmlContent = '''
    <div style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; max-width: 500px; margin: 0 auto; padding: 24px; border: 1px solid #e0e0e0; border-radius: 16px; background-color: #ffffff;">
      <div style="text-align: center; margin-bottom: 24px;">
        <h2 style="color: #673ab7; margin: 0; font-size: 24px;">Lista lista</h2>
        <p style="color: #666666; font-size: 14px; margin-top: 4px;">Activación de tu cuenta</p>
      </div>
      <p style="font-size: 15px; color: #333333; margin-bottom: 12px;">$nameHeader</p>
      <p style="font-size: 14px; color: #555555; line-height: 1.5;">Gracias por registrarte. Para activar tu cuenta y comenzar a utilizar la app, ingresa el siguiente código de verificación:</p>
      <div style="background-color: #f5f2ff; padding: 20px; border-radius: 12px; text-align: center; margin: 24px 0; border: 1px dashed #673ab7;">
        <p style="font-size: 12px; color: #673ab7; margin-bottom: 6px; font-weight: bold; text-transform: uppercase; letter-spacing: 1px;">Código de Activación</p>
        <h1 style="color: #673ab7; letter-spacing: 8px; font-size: 34px; margin: 8px 0; font-weight: 800;">$pinCode</h1>
        <p style="font-size: 12px; color: #888888; margin-top: 6px;">Este código tiene una validez de 10 minutos.</p>
      </div>
      <p style="font-size: 13px; color: #777777; line-height: 1.4;">Si no reconoces este registro o no creaste una cuenta, puedes ignorar este correo de forma segura.</p>
    </div>
    ''';

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $resendApiKey',
        },
        body: jsonEncode({
          'from': fromEmail,
          'to': [toEmail],
          'subject': 'Código de activación de tu cuenta: $pinCode',
          'html': htmlContent,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint(
          "[EMAIL_SERVICE LOG] Correo de activación enviado con éxito a $toEmail vía Resend.",
        );
        return true;
      } else {
        debugPrint(
          "[EMAIL_SERVICE LOG] Error enviando correo de activación vía Resend (${response.statusCode}): ${response.body}",
        );
        return false;
      }
    } catch (e) {
      debugPrint("[EMAIL_SERVICE LOG] Excepción enviando correo de activación: $e");
      return false;
    }
  }
}
