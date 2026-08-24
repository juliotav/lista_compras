// ignore_for_file: avoid_print, depend_on_referenced_packages
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final inputPath = 'assets/images/app_icon.png';
  final bytes = File(inputPath).readAsBytesSync();
  final original = img.decodePng(bytes);

  if (original == null) {
    print("Error leyendo $inputPath");
    return;
  }

  // Crear un lienzo cuadrado blanco de 512x512
  final size = 512;
  final canvas = img.Image(width: size, height: size);

  // Llenar lienzo con fondo blanco completamente opaco
  img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 255));

  // Dibujar un círculo blanco con borde sutil o sombra limpia
  img.fillCircle(
    canvas,
    x: size ~/ 2,
    y: size ~/ 2,
    radius: (size ~/ 2) - 4,
    color: img.ColorRgba8(255, 255, 255, 255),
  );

  // Redimensionar el icono original para centrarlo dentro del círculo con margen interno
  final iconScaled = img.copyResize(original, width: 360, height: 360);

  // Superponer el icono en el centro del fondo blanco
  img.compositeImage(
    canvas,
    iconScaled,
    dstX: (size - iconScaled.width) ~/ 2,
    dstY: (size - iconScaled.height) ~/ 2,
  );

  final encodedPng = img.encodePng(canvas);

  final targets = [
    'android/app/src/main/res/drawable/ic_notification.png',
    'android/app/src/main/res/drawable-v21/ic_notification.png',
    'android/app/src/main/res/mipmap-mdpi/ic_notification.png',
    'android/app/src/main/res/mipmap-hdpi/ic_notification.png',
    'android/app/src/main/res/mipmap-xhdpi/ic_notification.png',
    'android/app/src/main/res/mipmap-xxhdpi/ic_notification.png',
    'android/app/src/main/res/mipmap-xxxhdpi/ic_notification.png',
  ];

  for (var target in targets) {
    final file = File(target);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(encodedPng);
    print("Creado icono con fondo blanco en: $target");
  }

  print("¡Todos los íconos de notificación con fondo blanco fueron generados exitosamente!");
}
