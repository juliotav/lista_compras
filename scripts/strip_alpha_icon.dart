// ignore_for_file: avoid_print, depend_on_referenced_packages
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  print('Iniciando procesamiento de iconos con fondo blanco puro y sin canal alfa...');

  // 1. Obtener la imagen fuente con transparencia original si existe app_icon_source.png,
  // o desde git si es necesario.
  final sourceFile = File('assets/images/app_icon_source.png');
  img.Image? originalTransparent;

  if (sourceFile.existsSync()) {
    originalTransparent = img.decodePng(sourceFile.readAsBytesSync());
  }

  if (originalTransparent == null) {
    // Si no existe localmente, intentar extraerlo de git commit 6c67f22
    final res = Process.runSync('git', ['show', '6c67f22:assets/images/app_icon.png']);
    if (res.exitCode == 0 && res.stdout is List<int>) {
      final bytes = res.stdout as List<int>;
      sourceFile.writeAsBytesSync(bytes);
      originalTransparent = img.decodePng(sourceFile.readAsBytesSync());
    }
  }

  if (originalTransparent == null) {
    print('Error: No se pudo obtener la imagen original con transparencia.');
    return;
  }

  print('Imagen original obtenida: ${originalTransparent.width}x${originalTransparent.height}');

  // 2. Crear el icono maestro 1024x1024 sobre fondo blanco sólido (sin canal alfa, 3 canales)
  final masterWhiteBg = img.Image(
    width: originalTransparent.width,
    height: originalTransparent.height,
    numChannels: 3,
  );
  // Llenar con blanco puro
  img.fill(masterWhiteBg, color: img.ColorRgb8(255, 255, 255));

  // Superponer el icono original con mezcla alfa suave
  img.compositeImage(masterWhiteBg, originalTransparent);

  // Guardar assets/images/app_icon.png
  final masterPng = img.encodePng(masterWhiteBg);
  File('assets/images/app_icon.png').writeAsBytesSync(masterPng);
  print('Icono maestro guardado en assets/images/app_icon.png (1024x1024, RGB sin alfa)');

  // 3. Procesar o regenerar todos los iconos de iOS en AppIcon.appiconset
  final appIconDir = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
  if (appIconDir.existsSync()) {
    for (final entity in appIconDir.listSync()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
        final currentIcon = img.decodePng(entity.readAsBytesSync());
        if (currentIcon == null) continue;

        // Redimensionar el master sobre fondo blanco a las dimensiones exactas de este icono
        final resized = img.copyResize(
          masterWhiteBg,
          width: currentIcon.width,
          height: currentIcon.height,
          interpolation: img.Interpolation.linear,
        );

        final noAlphaTarget = img.Image(
          width: currentIcon.width,
          height: currentIcon.height,
          numChannels: 3,
        );
        img.fill(noAlphaTarget, color: img.ColorRgb8(255, 255, 255));
        img.compositeImage(noAlphaTarget, resized);

        entity.writeAsBytesSync(img.encodePng(noAlphaTarget));
        print('Icono de iOS generado: ${entity.path} (${currentIcon.width}x${currentIcon.height})');
      }
    }
  }

  print('\n¡Todos los iconos de iOS han sido actualizados a fondo blanco puro sin canal alfa!');
}
