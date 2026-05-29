import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

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

  /// Fetches route alternatives between origin and destination from OSRM.
  Future<List<Map<String, dynamic>>> getRouteAlternatives(LatLng origin, LatLng destination) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=geojson&alternatives=true',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List routes = data['routes'] ?? [];

        return routes.map<Map<String, dynamic>>((route) {
          final geometry = route['geometry'] ?? {};
          final List rawCoords = geometry['coordinates'] ?? [];
          final List<LatLng> polylinePoints = rawCoords.map<LatLng>((coord) {
            return LatLng(
              double.parse(coord[1].toString()), // Latitude is index 1
              double.parse(coord[0].toString()), // Longitude is index 0
            );
          }).toList();

          final double distanceKm = (route['distance'] as num? ?? 0.0) / 1000.0;
          final double durationMin = (route['duration'] as num? ?? 0.0) / 60.0;

          // Extraer resumen de carreteras principales
          final List legs = route['legs'] ?? [];
          String roadSummary = 'Ruta Alternativa';
          if (legs.isNotEmpty) {
            final leg = legs[0];
            roadSummary = leg['summary'] ?? 'Carretera principal';
            if (roadSummary.trim().isEmpty) {
              roadSummary = 'Vía Secundaria';
            }
          }

          return {
            'polyline': polylinePoints,
            'distance_km': distanceKm,
            'duration_min': durationMin,
            'summary': roadSummary,
          };
        }).toList();
      }
    } catch (e) {
      print('OSRM Routing Error: $e');
    }
    return [];
  }
}
