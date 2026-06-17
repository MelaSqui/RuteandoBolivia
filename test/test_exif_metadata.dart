import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:exif/exif.dart';

void main() {
  test('Prueba de lectura de metadatos EXIF de una fotografia real', () async {
    // 1. Cargar el archivo de prueba descargado
    final file = File('test/DSCN0010.jpg');
    expect(await file.exists(), isTrue, reason: 'El archivo de prueba jpg debe existir');

    final bytes = await file.readAsBytes();
    
    // 2. Extraer metadatos usando la librería exif
    print('--- INICIANDO LECTURA DE EXIF ---');
    final tags = await readExifFromBytes(bytes);
    
    expect(tags.isNotEmpty, isTrue, reason: 'Debe encontrar etiquetas EXIF en la foto de prueba');
    print('Total de etiquetas EXIF encontradas: ${tags.length}');

    // 3. Extraer y mostrar metadatos clave para nuestro validador
    final exifMetadata = <String, String>{};
    if (tags.containsKey('Image Make')) {
      exifMetadata['Make'] = tags['Image Make']!.toString();
    }
    if (tags.containsKey('Image Model')) {
      exifMetadata['Model'] = tags['Image Model']!.toString();
    }
    if (tags.containsKey('Image DateTime')) {
      exifMetadata['DateTime'] = tags['Image DateTime']!.toString();
    }
    if (tags.containsKey('EXIF DateTimeOriginal')) {
      exifMetadata['DateTimeOriginal'] = tags['EXIF DateTimeOriginal']!.toString();
    }
    if (tags.containsKey('Image Software')) {
      exifMetadata['Software'] = tags['Image Software']!.toString();
    }

    print('\nMETADATOS PARSEADOS:');
    exifMetadata.forEach((key, value) {
      print('  $key: $value');
    });

    // Validar que se hayan recuperado etiquetas básicas de la cámara
    expect(exifMetadata.containsKey('Make'), isTrue, reason: 'Debe contener la marca de la cámara');
    expect(exifMetadata.containsKey('Model'), isTrue, reason: 'Debe contener el modelo de la cámara');
    expect(exifMetadata.containsKey('DateTimeOriginal'), isTrue, reason: 'Debe contener la fecha de captura original');

    print('\n--- EVALUANDO VALIDACIONES LOCALES ---');
    
    // Probar filtro de nombre de archivo (Screenshot)
    const mockFilenameScreenshot = 'Screenshot_20260617_185100.jpg';
    final isScreenshot = mockFilenameScreenshot.toLowerCase().contains('screenshot');
    print('Verificando nombre "$mockFilenameScreenshot" como captura: $isScreenshot');
    expect(isScreenshot, isTrue);

    // Probar filtro de tiempo (Diferencia de hora)
    if (exifMetadata.containsKey('DateTimeOriginal')) {
      final dtStr = exifMetadata['DateTimeOriginal']!;
      print('Procesando fecha de toma: $dtStr');
      try {
        final parts = dtStr.split(' ');
        final dateParts = parts[0].split(':');
        final timeParts = parts[1].split(':');
        
        final photoDate = DateTime(
          int.parse(dateParts[0]),
          int.parse(dateParts[1]),
          int.parse(dateParts[2]),
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
          int.parse(timeParts[2]),
        );
        
        final now = DateTime.now();
        final diff = now.difference(photoDate).abs();
        print('Diferencia de tiempo con respecto a hoy: ${diff.inDays} dias, ${diff.inHours % 24} horas, ${diff.inMinutes % 60} minutos');
        
        final isTooOld = diff.inMinutes > 30;
        print('¿Es una foto antigua (antigueedad > 30 mins)?: $isTooOld');
        // Dado que la foto es un recurso de prueba histórico, debe dar "isTooOld = true"
        expect(isTooOld, isTrue);
      } catch (e) {
        fail('Fallo al parsear la fecha de toma: $e');
      }
    }
  });
}
