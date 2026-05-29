import 'dart:convert';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
4. Usa emojis (⚠️, ✅, 🌧️, 🚗).
''';

    // Se envía el prompt como primer mensaje de usuario y una respuesta de aceptación para iniciar el historial
    return _model.startChat(history: [
      Content('user', [TextPart(systemPrompt)]),
      Content('model', [TextPart('¡Entendido! Soy Ruteando AI y estoy listo para ayudar al viajero con información precisa y actualizada.')]),
    ]);
  }

  /// Verifies an image with Gemini AI to determine if it represents a valid road incident.
  Future<Map<String, dynamic>> verifyImage(Uint8List bytes, String mimeType) async {
    try {
      final prompt = '''
Analiza esta imagen para un reporte de transitabilidad y estado de carreteras en Bolivia.
Debes responder ÚNICAMENTE con un objeto JSON válido con la siguiente estructura:
{
  "is_valid": true o false,
  "confidence": un número de 0 a 100 indicando la seguridad de tu análisis,
  "category": "Bloqueo", "Accidente", "Estado de Ruta", "Clima" o "Desconocido",
  "reason": "Una breve explicación en español de lo que detectaste (máximo 15 palabras)."
}

Reglas de validación:
- "is_valid" debe ser true solo si la imagen muestra una carretera, calle, ruta, vehículo accidentado, bloqueo de carreteras, baches, deslizamiento de tierra, derrumbe, inundación, clima extremo que afecte el tránsito vial, o señalización de tráfico.
- Si la imagen muestra selfies, caras de personas de cerca, comida, interiores de viviendas, memes, capturas de pantalla de chats o texto no relacionado, animales sin relación a la vía, etc., "is_valid" debe ser false.
- Sé estricto para evitar spam.
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

      // Limpiar posibles bloques de código markdown si los hay (e.g. ```json ... ```)
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
        'reason': parsed['reason'] ?? 'Sin descripción.',
      };
    } catch (e) {
      print('Error in Gemini Image Verification: \$e');
      return {
        'is_valid': false,
        'confidence': 0.0,
        'category': 'Desconocido',
        'reason': 'Error al procesar la verificación con IA: \$e'
      };
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
3. Usa emojis de manera inteligente (⚠️, 🚗, 🟢, 🛑).
4. Evita tecnicismos y asume que eres un copiloto humano aconsejando a su conductor.
''';

      final response = await _model.generateContent([Content.text(prompt)]);
      return response.text ?? 'No se pudo obtener la recomendacion de viaje en este momento. Conduce con cuidado.';
    } catch (e) {
      print('Gemini Route Safety Analysis Error: \$e');
      return 'Error al conectar con el asistente Ruteando AI. Por favor, revisa el estado del mapa y conduce con precaucion.';
    }
  }
}
