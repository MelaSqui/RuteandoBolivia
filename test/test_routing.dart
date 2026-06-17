import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:ruteando_bolivia/features/routes/data/services/route_service.dart';

void main() {
  test('Test OSRM Routing and Waypoints', () async {
    final routeService = RouteService();

    // Coordinates for La Paz and Oruro, Bolivia
    final origin = LatLng(-16.5000, -68.1500); // La Paz
    final destination = LatLng(-17.9833, -67.1500); // Oruro

    print('--- TESTING PLACE SEARCH ---');
    final searchResults = await routeService.searchPlaces('La Paz');
    print('Search results for "La Paz":');
    for (var res in searchResults) {
      print('- Name: ${res['name']}, Lat: ${res['latitude']}, Lng: ${res['longitude']}');
    }

    print('\n--- TESTING DIRECT ROUTING ---');
    final routes = await routeService.getRouteAlternatives(origin, destination);
    print('Found ${routes.length} direct routes:');
    for (int i = 0; i < routes.length; i++) {
      final r = routes[i];
      final List poly = r['polyline'] as List;
      print('Route ${i + 1}:');
      print('  Summary: ${r['summary']}');
      print('  Distance: ${r['distance_km']} km');
      print('  Duration: ${r['duration_min']} mins');
      print('  Polyline Points: ${poly.length}');
      if (poly.isNotEmpty) {
        print('  First Point: ${poly.first}');
        print('  Last Point: ${poly.last}');
      }
    }
  });
}
