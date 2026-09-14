// ignore_for_file: avoid_print, depend_on_referenced_packages
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final appIconDir = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
  final filesToProcess = <String>['assets/images/app_icon.png'];

  if (appIconDir.existsSync()) {
    for (final entity in appIconDir.listSync()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
        filesToProcess.add(entity.path);
      }
    }
  }

  for (final filePath in filesToProcess) {
    final file = File(filePath);
    if (!file.existsSync()) continue;

    final bytes = file.readAsBytesSync();
    final original = img.decodePng(bytes);
    if (original == null) continue;

    final noAlphaImage = img.Image(
      width: original.width,
      height: original.height,
      numChannels: 3,
    );

    // Fondo blanco sólido (sin canal alfa)
    img.fill(noAlphaImage, color: img.ColorRgb8(255, 255, 255));

    for (final pixel in original) {
      noAlphaImage.setPixelRgb(pixel.x, pixel.y, pixel.r, pixel.g, pixel.b);
    }

    final encoded = img.encodePng(noAlphaImage);
    file.writeAsBytesSync(encoded);
    print('Canal alfa removido: $filePath (${noAlphaImage.width}x${noAlphaImage.height})');
  }

  print('\n¡Todos los iconos de iOS han sido convertidos a RGB puro sin canal alfa!');
}
