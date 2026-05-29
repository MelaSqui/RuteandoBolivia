import 'dart:convert';
import 'dart:math';
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
          return _parseOsrmRoute(route);
        }).toList();
      }
    } catch (e) {
      print('OSRM Routing Error: $e');
    }
    return [];
  }

  /// Fetches a single route passing through an intermediate waypoint (origin → waypoint → destination).
  Future<Map<String, dynamic>?> getRouteViaWaypoint(LatLng origin, LatLng waypoint, LatLng destination) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${origin.longitude},${origin.latitude};'
        '${waypoint.longitude},${waypoint.latitude};'
        '${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=geojson&alternatives=false',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List routes = data['routes'] ?? [];
        if (routes.isNotEmpty) {
          return _parseOsrmRoute(routes[0]);
        }
      }
    } catch (e) {
      print('OSRM Waypoint Routing Error: $e');
    }
    return null;
  }

  /// Searches for nearby intermediate towns/cities that can serve as waypoints
  /// for intelligent detour routing when direct routes are blocked.
  /// Uses Nominatim reverse geocoding to find towns near the midpoint of the route,
  /// offset in different compass directions to get genuinely different paths.
  Future<List<Map<String, dynamic>>> findIntermediateWaypoints(LatLng origin, LatLng destination) async {
    final List<Map<String, dynamic>> waypoints = [];

    // Calculate the midpoint between origin and destination
    final double midLat = (origin.latitude + destination.latitude) / 2;
    final double midLng = (origin.longitude + destination.longitude) / 2;

    // Calculate the distance between origin and destination to scale the offset
    final double latDiff = (destination.latitude - origin.latitude).abs();
    final double lngDiff = (destination.longitude - origin.longitude).abs();
    final double routeSpan = sqrt(latDiff * latDiff + lngDiff * lngDiff);

    // Scale offset: smaller routes get smaller offsets (min 0.08° ~9km, max 0.35° ~39km)
    final double offset = (routeSpan * 0.5).clamp(0.08, 0.35);

    // Calculate the perpendicular direction to the route vector
    final double dx = destination.longitude - origin.longitude;
    final double dy = destination.latitude - origin.latitude;
    // Perpendicular vectors: (-dy, dx) and (dy, -dx)
    final double len = sqrt(dx * dx + dy * dy);
    if (len == 0) return [];

    final double perpX = -dy / len;
    final double perpY = dx / len;

    // Search for towns offset perpendicularly from the route (both sides)
    final offsets = [
      {'lat': midLat + perpX * offset, 'lng': midLng + perpY * offset, 'dir': 'Desvío lateral 1'},
      {'lat': midLat - perpX * offset, 'lng': midLng - perpY * offset, 'dir': 'Desvío lateral 2'},
      // Also try a point closer to origin but offset
      {'lat': origin.latitude + (midLat - origin.latitude) * 0.4 + perpX * offset * 0.7, 
       'lng': origin.longitude + (midLng - origin.longitude) * 0.4 + perpY * offset * 0.7, 
       'dir': 'Desvío temprano'},
    ];

    for (var off in offsets) {
      try {
        final url = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?lat=${off['lat']}&lon=${off['lng']}'
          '&format=json&zoom=12&addressdetails=1',
        );
        final response = await http.get(
          url,
          headers: {'User-Agent': 'RuteandoBoliviaApp/1.0 (careo.gemini)'},
        ).timeout(const Duration(seconds: 3));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final double? lat = double.tryParse(data['lat']?.toString() ?? '');
          final double? lng = double.tryParse(data['lon']?.toString() ?? '');
          final address = data['address'] ?? {};
          String name = address['town'] ?? address['city'] ?? address['village'] ?? address['hamlet'] ?? '';

          if (lat != null && lng != null && name.isNotEmpty) {
            // Don't add duplicates
            if (!waypoints.any((w) => w['name'] == name)) {
              waypoints.add({
                'name': name,
                'latitude': lat,
                'longitude': lng,
                'direction': off['dir'],
              });
            }
          }
        }
      } catch (e) {
        print('Nominatim reverse search error: $e');
      }
    }

    return waypoints;
  }

  /// Parses a single OSRM route JSON object into our standard route format.
  Map<String, dynamic> _parseOsrmRoute(Map<String, dynamic> route) {
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
      // Combine all leg summaries for waypoint routes
      final summaries = legs
          .map<String>((leg) {
            final s = leg['summary']?.toString() ?? '';
            return s.trim().isEmpty ? 'Vía Secundaria' : s;
          })
          .toSet() // Remove duplicates
          .toList();
      roadSummary = summaries.join(' → ');
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
  }
}
