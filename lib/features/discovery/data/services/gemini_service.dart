import 'dart:convert';
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
}
