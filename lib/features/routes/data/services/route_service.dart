import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RouteService {
  /// Searches for places in Bolivia using Nominatim OpenStreetMap API.
  Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=5&countrycodes=bo',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'RuteandoBoliviaApp/1.0 (careo.gemini)'},
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map<Map<String, dynamic>>((item) {
          return {
            'name': item['display_name'] ?? 'Sin nombre',
            'latitude': double.tryParse(item['lat']?.toString() ?? '') ?? 0.0,
            'longitude': double.tryParse(item['lon']?.toString() ?? '') ?? 0.0,
          };
        }).toList();
      }
    } catch (e) {
      print('Nominatim Place Search Error: $e');
    }
    return [];
  }

  /// Fetches the optimal route from our custom Dijkstra-in-memory backend.
  Future<List<Map<String, dynamic>>> getRouteAlternatives(LatLng origin, LatLng destination) async {
    try {
      // Usar la misma base URL que se usa para otras peticiones del backend
      // Se asume que el backend está corriendo localmente o en un servidor configurado
      // Puedes ajustar esta URL a la URL de producción de tu backend
      final String baseUrl = const String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:3000');
      final url = Uri.parse('$baseUrl/api/route/calculate?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}');
      
      // Asumiendo que el supabase token está guardado o se maneja un proxy
      final session = Supabase.instance.client.auth.currentSession;
      final token = session?.accessToken;

      final response = await http.get(url, headers: {
        'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List routes = data['routes'] ?? [];
        
        return routes.map<Map<String, dynamic>>((route) {
          final List polylineRaw = route['polyline'] ?? [];
          final polyline = polylineRaw.map<LatLng>((p) => LatLng(p['latitude'], p['longitude'])).toList();
          
          return {
            'polyline': polyline,
            'distance_km': route['distance_km'] ?? 0.0,
            'duration_min': route['duration_min'] ?? 0.0,
            'summary': route['summary'] ?? 'Ruta Óptima',
          };
        }).toList();
      } else {
        print('Backend Routing Error: ${response.body}');
      }
    } catch (e) {
      print('Backend Routing Exception: $e');
    }
    return [];
  }
}
