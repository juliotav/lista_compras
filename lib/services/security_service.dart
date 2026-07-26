import 'dart:convert';
import 'package:crypto/crypto.dart';

class PasswordSecurityResult {
  final bool minLength;
  final bool hasUppercase;
  final bool hasDigit;
  final bool hasSpecialChar;

  PasswordSecurityResult({
    required this.minLength,
    required this.hasUppercase,
    required this.hasDigit,
    required this.hasSpecialChar,
  });

  bool get isValid => minLength && hasUppercase && hasDigit && hasSpecialChar;

  double get score {
    int count = 0;
    if (minLength) count++;
    if (hasUppercase) count++;
    if (hasDigit) count++;
    if (hasSpecialChar) count++;
    return count / 4.0;
  }
}

class SecurityService {
  /// Evalúa si la contraseña cumple con los estándares modernos de seguridad
  static PasswordSecurityResult evaluatePassword(String password) {
    final minLength = password.length >= 8;
    final hasUppercase = password.contains(RegExp(r'[A-Z]'));
    final hasDigit = password.contains(RegExp(r'[0-9]'));
    final hasSpecialChar = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

    return PasswordSecurityResult(
      minLength: minLength,
      hasUppercase: hasUppercase,
      hasDigit: hasDigit,
      hasSpecialChar: hasSpecialChar,
    );
  }

  /// Hashea la contraseña con SHA-256 y un Salt para no guardarla en texto plano
  static String hashPassword(String password) {
    const salt = "ShoppingList_App_Secure_Salt_2026";
    final bytes = utf8.encode(password + salt);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
