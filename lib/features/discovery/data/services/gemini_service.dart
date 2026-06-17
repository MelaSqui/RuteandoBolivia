import 'dart:convert';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

class GeminiService {
  static GeminiService? _instance;
  late final GenerativeModel _model;
  final SupabaseClient _supabase = Supabase.instance.client;

  GeminiService._internal() {
    const apiKey = String.fromEnvironment('GEMINI_API_KEY');
    _model = GenerativeModel(
      model: 'gemini-3.5-flash',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.7,
        maxOutputTokens: 8192,
      ),
    );
  }

  factory GeminiService() {
    _instance ??= GeminiService._internal();
    return _instance!;
  }

  /// Fetches active road events from Supabase and formats them as a compact string to save AI tokens.
  Future<String> _fetchFilteredRoadEventsContext(String destinationDepartment, List<String> requiredHighways) async {
    try {
      final response = await _supabase
          .from('road_events')
          .select('ruta, departamento, evento, restriccion_vehicular, transitable_con_desvio');

      // Filtrar eventos para no enviar toda la base de datos.
      final filteredEvents = (response as List).where((e) {
        final ruta = e['ruta']?.toString() ?? '';
        final depto = e['departamento']?.toString() ?? '';
        return requiredHighways.contains(ruta) || depto == destinationDepartment;
      }).toList();

      if (filteredEvents.isEmpty) {
        return 'No hay eventos relevantes reportados para las rutas hacia este destino.';
      }

      // Convertir a texto compacto en lugar de JSON para ahorrar tokens
      final eventsText = filteredEvents.map((e) {
        return '- Ruta ${e['ruta']} (${e['departamento']}): ${e['evento']}. Desvío: ${e['transitable_con_desvio']}.';
      }).join('\n');

      return eventsText;
    } catch (e) {
      return 'Sin información disponible de eventos.';
    }
  }

  /// Creates a persistent chat session with the AI, sending the context only once.
  Future<ChatSession> createChatSession({
    required String destinationName,
    required String destinationDepartment,
    required double destinationLat,
    required double destinationLng,
    required List<String> requiredHighways,
    required bool isBlocked,
    required String userLocationName,
  }) async {
    final roadEventsText = await _fetchFilteredRoadEventsContext(destinationDepartment, requiredHighways);

    final systemPrompt = '''
Eres "Ruteando AI", un asistente inteligente de viaje para Bolivia.
Tu trabajo es ayudar al viajero a entender el estado de las carreteras hacia su destino.

DATOS FILTRADOS DE LA ABC (Eventos relevantes para el viaje):
$roadEventsText

CONTEXTO DEL VIAJERO:
- Ubicación actual: $userLocationName
- Destino: $destinationName ($destinationDepartment)
- Rutas necesarias: ${requiredHighways.join(', ')}
- Estado general para el destino: ${isBlocked ? 'BLOQUEADO' : 'LIBRE'}

INSTRUCCIONES:
1. Responde de forma amigable y concisa.
2. Usa la información de DATOS FILTRADOS para dar detalles sobre bloqueos o desvíos si los hay en las rutas necesarias.
3. Sugiere alternativas lógicas si hay bloqueos.
4. No uses emojis.
''';

    // Se envía el prompt como primer mensaje de usuario y una respuesta de aceptación para iniciar el historial
    return _model.startChat(history: [
      Content('user', [TextPart(systemPrompt)]),
      Content('model', [TextPart('¡Entendido! Soy Ruteando AI y estoy listo para ayudar al viajero con información precisa y actualizada.')]),
    ]);
  }

  /// Verifies an image with Gemini AI, falling back to Groq Llama 3.2 Vision if Gemini fails or is not configured.
  Future<Map<String, dynamic>> verifyImage(
      Uint8List bytes, String mimeType, String category, String description,
      {Map<String, String>? exifMetadata}) async {
    try {
      const apiKey = String.fromEnvironment('GEMINI_API_KEY');
      if (apiKey.isEmpty) {
        // Intentar usar Groq de frente si está configurada la llave
        const groqKey = String.fromEnvironment('GROQ_API_KEY');
        if (groqKey.isNotEmpty) {
          return await _verifyImageWithGroq(bytes, mimeType, category, description, exifMetadata: exifMetadata);
        }

        return {
          'is_valid': true,
          'confidence': 100.0,
          'category': category.isNotEmpty ? category : 'Bloqueo',
          'reason': 'Modo Demo (Sin API Key): Autoverificado sin analisis real.'
        };
      }

      String metadataText = "No disponibles o no detectados (posible imagen guardada, captura de pantalla o modificada).";
      if (exifMetadata != null && exifMetadata.isNotEmpty) {
        metadataText = exifMetadata.entries.map((e) => "- ${e.key}: ${e.value}").join('\n');
      }

      final prompt = '''
Analiza esta imagen para un reporte de transitabilidad y estado de carreteras en Bolivia.
El usuario ha seleccionado la categoria "$category" y ha proporcionado la siguiente descripcion:
"$description"

METADATOS DE LA FOTO (EXIF):
$metadataText

Debes validar de manera estricta si la imagen corresponde a la categoria y descripcion reportadas.
Especificamente:
- Si la categoria es "Bloqueo", la imagen DEBE mostrar activamente un bloqueo de carretera (personas obstruyendo la via, barricadas, piedras, tierra, troncos u objetos bloqueando el paso). Un trafico urbano pesado o semaforos en rojo NO califican como bloqueo. Si la imagen muestra una carretera libre y transitable sin obstaculos, debes marcar "is_valid" como false.
- Si la categoria es "Accidente", la imagen DEBE mostrar un accidente de transito real, colision, vehiculo danado o volcado en la via.
- Si la categoria es "Clima", la imagen DEBE mostrar condiciones de clima adversas (lluvia, niebla, nieve, inundacion).
- Si la categoria es "Estado de Ruta", la imagen DEBE mostrar danos en la via (derrumbes, baches, deslizamientos).

Reglas de validacion estrictas contra pruebas (Adversarial Testing) y ANTI-FRAUDE:
- La imagen DEBE ser una fotografia real tomada directamente en un entorno real.
- RECHAZA COMPLETAMENTE "fotos de fotos" (re-fotografías de una foto física) y "fotos de pantallas" (re-fotografías tomadas a una pantalla de celular, monitor, TV, tablet, etc.). Identifica signos típicos de fotos de pantallas: patrones de moiré (interferencia de líneas/ondas/cuadrícula de píxeles), reflejos del vidrio de la pantalla, marcos o bordes físicos de dispositivos electrónicos, o desenfoque por píxeles visibles de pantalla.
- Si los METADATOS DE LA FOTO (EXIF) están vacíos o indican un software de edición (como Photoshop, GIMP) Y observas indicios de re-fotografía, rechaza inmediatamente.
- Rechaza dibujos, caricaturas, renders, capturas de mapas, juguetes/miniaturas o imagenes creadas digitalmente.
- Coherencia Geografica/Contextual: La imagen debe ser coherente con Bolivia. Si muestra de forma obvia una gran metropoli extranjera (ej: Nueva York, Miami, Tokio), letreros en ingles/chino, canales (ej: Venecia) u otros elementos ajenos a Bolivia, debes marcar "is_valid" como false.
- Coherencia de Descripcion: La imagen debe corresponder directamente a la descripcion provista.
- Si la imagen muestra selfies, caras de cerca, comida, interiores de casas, memes o capturas de pantalla, "is_valid" debe ser false.

Debes responder UNICAMENTE con un objeto JSON valido con la siguiente estructura (sin formato markdown ni texto adicional, solo el JSON):
{
  "is_valid": true o false,
  "confidence": un numero de 0 a 100 indicando la seguridad de tu analisis,
  "category": "$category",
  "reason": "Una explicacion en espanol de lo que observas en la imagen y por que se acepta o se rechaza (maximo 30 palabras).",
  "descripcion_reformulada": "Si 'is_valid' es true, una descripcion reformulada del incidente basada en la imagen y comentario del usuario. Debe ser formal, profesional y muy breve (maximo 10 palabras) en espanol, similar al estilo de los reportes oficiales (ej. 'Bloqueo con piedras y ramas', 'Derrumbe de tierra sobre la calzada'). Si 'is_valid' es false, coloca null."
}
''';

      final response = await _model.generateContent([
        Content.multi([
          TextPart(prompt),
          DataPart(mimeType, bytes),
        ])
      ]);

      final responseText = response.text;
      if (responseText == null) {
        return {
          'is_valid': false,
          'confidence': 0.0,
          'category': 'Desconocido',
          'reason': 'No se obtuvo respuesta del modelo de IA.'
        };
      }

      // Limpiar posibles bloques de codigo markdown si los hay (e.g. ```json ... ```)
      String cleanJson = responseText.trim();
      if (cleanJson.startsWith('```json')) {
        cleanJson = cleanJson.substring(7);
      }
      if (cleanJson.endsWith('```')) {
        cleanJson = cleanJson.substring(0, cleanJson.length - 3);
      }
      cleanJson = cleanJson.trim();

      final parsed = jsonDecode(cleanJson) as Map<String, dynamic>;
      return {
        'is_valid': parsed['is_valid'] ?? false,
        'confidence': (parsed['confidence'] as num?)?.toDouble() ?? 0.0,
        'category': parsed['category'] ?? 'Desconocido',
        'reason': parsed['reason'] ?? 'Sin descripcion.',
        'descripcion_reformulada': parsed['descripcion_reformulada'] as String?,
      };
    } catch (e) {
      // Intentar fallback automático con Groq
      try {
        return await _verifyImageWithGroq(bytes, mimeType, category, description, exifMetadata: exifMetadata);
      } catch (groqError) {
        String userFriendlyReason = 'Error de análisis: No se pudo verificar la imagen ($e)';
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('503') || errStr.contains('unavailable') || errStr.contains('high demand') || errStr.contains('spike')) {
          userFriendlyReason = 'El servicio de IA de Google está temporalmente saturado debido a una alta demanda. Por favor, reintenta enviar tu reporte en unos minutos.';
        } else if (errStr.contains('api_key') || errStr.contains('api key') || errStr.contains('api key not found')) {
          userFriendlyReason = 'Error de configuración: Clave de API de Gemini no válida o ausente.';
        } else if (errStr.contains('400') || errStr.contains('invalid argument')) {
          userFriendlyReason = 'Error de formato: Los datos de la imagen o texto enviados a la IA no son válidos.';
        }

        return {
          'is_valid': false,
          'confidence': 0.0,
          'category': category.isNotEmpty ? category : 'Desconocido',
          'reason': '$userFriendlyReason (Backup Groq falló también: $groqError)',
        };
      }
    }
  }

  /// Helper para verificar la imagen de reporte con Groq (Llama 3.2 Vision)
  Future<Map<String, dynamic>> _verifyImageWithGroq(
      Uint8List bytes, String mimeType, String category, String description,
      {Map<String, String>? exifMetadata}) async {
    const groqKey = String.fromEnvironment('GROQ_API_KEY');

    String metadataText = "No disponibles o no detectados (posible imagen guardada, captura de pantalla o modificada).";
    if (exifMetadata != null && exifMetadata.isNotEmpty) {
      metadataText = exifMetadata.entries.map((e) => "- ${e.key}: ${e.value}").join('\n');
    }

    final base64Image = base64Encode(bytes);
    final prompt = '''
Analiza esta imagen para un reporte de transitabilidad y estado de carreteras en Bolivia.
El usuario ha seleccionado la categoria "$category" y ha proporcionado la siguiente descripcion:
"$description"

METADATOS DE LA FOTO (EXIF):
$metadataText

Debes validar de manera estricta si la imagen corresponde a la categoria y descripcion reportadas.
Especificamente:
- Si la categoria es "Bloqueo", la imagen DEBE mostrar activamente un bloqueo de carretera (personas obstruyendo la via, barricadas, piedras, tierra, troncos u objetos bloqueando el paso). Un trafico urbano pesado o semaforos en rojo NO califican como bloqueo. Si la imagen muestra una carretera libre y transitable sin obstaculos, debes marcar "is_valid" como false.
- Si la categoria es "Accidente", la imagen DEBE mostrar un accidente de transito real, colision, vehiculo danado o volcado en la via.
- Si la categoria es "Clima", la imagen DEBE mostrar condiciones de clima adversas (lluvia, niebla, nieve, inundacion).
- Si la categoria es "Estado de Ruta", la imagen DEBE mostrar danos en la via (derrumbes, baches, deslizamientos).

Reglas de validacion estrictas contra pruebas (Adversarial Testing) y ANTI-FRAUDE:
- La imagen DEBE ser una fotografia real tomada directamente en un entorno real.
- RECHAZA COMPLETAMENTE "fotos de fotos" (re-fotografías de una foto física) y "fotos de pantallas" (re-fotografías tomadas a una pantalla de celular, monitor, TV, tablet, etc.). Identifica signos típicos de fotos de pantallas: patrones de moiré (interferencia de líneas/ondas/cuadrícula de píxeles), reflejos del vidrio de la pantalla, marcos o bordes físicos de dispositivos electrónicos, o desenfoque por píxeles visibles de pantalla.
- Si los METADATOS DE LA FOTO (EXIF) están vacíos o indican un software de edición Y observas indicios de re-fotografía, rechaza inmediatamente.
- Rechaza dibujos, caricaturas, renders, capturas de mapas, juguetes/miniaturas o imagenes creadas digitalmente.
- Coherencia Geografica/Contextual: La imagen debe ser coherente con Bolivia. Si muestra de forma obvia una gran metropoli extranjera (ej: Nueva York, Miami, Tokio), letreros en ingles/chino, canales (ej: Venecia) u otros elementos ajenos a Bolivia, debes marcar "is_valid" como false.

Debes responder UNICAMENTE con un objeto JSON valido con la siguiente estructura (sin formato markdown ni texto adicional, solo el JSON):
{
  "is_valid": true o false,
  "confidence": un numero de 0 a 100 indicando la seguridad de tu analisis,
  "category": "$category",
  "reason": "Una explicacion en espanol de lo que observas en la imagen y por que se acepta o se rechaza (maximo 30 palabras).",
  "descripcion_reformulada": "Si 'is_valid' es true, una descripcion reformulada del incidente basada en la imagen y comentario del usuario. Debe ser formal, profesional y muy breve (maximo 10 palabras) en espanol, similar al estilo de los reportes oficiales (ej. 'Bloqueo con piedras y ramas', 'Derrumbe de tierra sobre la calzada'). Si 'is_valid' es false, coloca null."
}
''';

    final body = jsonEncode({
      "model": "meta-llama/llama-4-scout-17b-16e-instruct",
      "messages": [
        {
          "role": "user",
          "content": [
            {
              "type": "text",
              "text": prompt,
            },
            {
              "type": "image_url",
              "image_url": {
                "url": "data:$mimeType;base64,$base64Image",
              },
            }
          ]
        }
      ],
      "response_format": {
        "type": "json_object"
      }
    });

    final response = await http.post(
      Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $groqKey',
      },
      body: body,
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      final content = jsonResponse['choices'][0]['message']['content'].toString().trim();
      final parsed = jsonDecode(content) as Map<String, dynamic>;
      return {
        'is_valid': parsed['is_valid'] ?? false,
        'confidence': (parsed['confidence'] as num?)?.toDouble() ?? 0.0,
        'category': parsed['category'] ?? category,
        'reason': parsed['reason'] ?? 'Sin descripcion de Groq.',
        'descripcion_reformulada': parsed['descripcion_reformulada'] as String?,
      };
    } else {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  /// Analyzes route alternatives and roadblocks to provide intelligent travel advice.
  Future<String> analyzeRouteSafety({
    required String origin,
    required String destination,
    required List<Map<String, dynamic>> routeAlternatives,
    required List<List<Map<String, dynamic>>> roadblocksPerRoute,
  }) async {
    try {
      final buffer = StringBuffer();
      buffer.writeln('VIAJE PLANEADO: De $origin a $destination');
      buffer.writeln('\nALTERNATIVAS DE RUTA DETECTADAS:');

      for (int i = 0; i < routeAlternatives.length; i++) {
        final route = routeAlternatives[i];
        final roadblocks = roadblocksPerRoute[i];
        final summary = route['summary'] ?? 'Via secundaria';
        final dist = (route['distance_km'] as double?)?.toStringAsFixed(1) ?? '0.0';
        final dur = (route['duration_min'] as double?)?.toStringAsFixed(0) ?? '0';

        buffer.writeln('Ruta ${i + 1} ($summary):');
        buffer.writeln('- Distancia: $dist km');
        buffer.writeln('- Duracion: $dur minutos');

        if (roadblocks.isEmpty) {
          buffer.writeln('- Estado: TOTALMENTE TRANSITABLE (0 bloqueos activos)');
        } else {
          buffer.writeln('- Estado: BLOQUEADA / CON OBSTRUCCIONES (${roadblocks.length} incidentes)');
          for (var r in roadblocks) {
            final raw = r['raw_data'];
            Map<String, dynamic>? rawData;
            if (raw is Map<String, dynamic>) {
              rawData = raw;
            } else if (raw is String) {
              try {
                rawData = jsonDecode(raw) as Map<String, dynamic>;
              } catch (_) {}
            }

            final evento = r['evento'] ?? 'Incidente vial';
            final inicio = rawData != null ? (rawData['inicio_seccion'] ?? '') : '';
            final fin = rawData != null ? (rawData['fin_seccion'] ?? '') : '';
            String sectorText = '';
            if (inicio.isNotEmpty && fin.isNotEmpty) {
              sectorText = ' en tramo $inicio - $fin';
            }

            buffer.writeln('  * Incidente: $evento$sectorText.');
          }
        }
        buffer.writeln();
      }

      final prompt = '''
Eres "Ruteando AI", el copiloto inteligente de viaje para Bolivia.
Analiza la siguiente informacion de alternativas de ruteo e incidentes viales:

${buffer.toString()}

Escribe una recomendacion amigable, profesional y sumamente concisa (maximo dos parrafos cortos) en español boliviano sobre que ruta debe tomar el usuario y por que.
Reglas:
1. Se muy claro indicando cual de las rutas esta libre y es la mas recomendable.
2. Si todas estan bloqueadas, explicalo con tacto y sugiere extrema precaucion o esperar.
3. No uses emojis.
4. Evita tecnicismos y asume que eres un copiloto humano aconsejando a su conductor.
''';

      final response = await _model.generateContent([Content.text(prompt)]);
      return response.text ?? 'No se pudo obtener la recomendacion de viaje en este momento. Conduce con cuidado.';
    } catch (e) {
      print('Gemini Route Safety Analysis Error: $e');
      return 'Error al conectar con el asistente Ruteando AI. Por favor, revisa el estado del mapa y conduce con precaucion.';
    }
  }
}
