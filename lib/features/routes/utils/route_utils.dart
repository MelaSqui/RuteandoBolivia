import 'dart:math';
import 'package:latlong2/latlong.dart';

class RouteUtils {
  /// Calculates the Haversine distance in kilometers between two GPS coordinates.
  static double calculateDistance(LatLng p1, LatLng p2) {
    const double r = 6371.0; // Earth radius in km
    final double lat1Rad = p1.latitudeInRad;
    final double lat2Rad = p2.latitudeInRad;
    final double dLat = (p2.latitude - p1.latitude) * pi / 180.0;
    final double dLon = (p2.longitude - p1.longitude) * pi / 180.0;

    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return r * c;
  }

  /// Evaluates whether an incident point is within a threshold distance of any point along the route polyline.
  static bool isPointNearRoute(LatLng point, List<LatLng> polyline, double maxDistanceKm) {
    if (polyline.isEmpty) return false;

    // Para optimizar el rendimiento, primero realizamos un filtro rápido por caja delimitadora (Bounding Box)
    double minLat = polyline[0].latitude;
    double maxLat = polyline[0].latitude;
    double minLng = polyline[0].longitude;
    double maxLng = polyline[0].longitude;

    for (var p in polyline) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    // Expandir ligeramente la caja delimitadora (aproximadamente 0.02 grados es ~2.2 km)
    const double padding = 0.015;
    if (point.latitude < minLat - padding ||
        point.latitude > maxLat + padding ||
        point.longitude < minLng - padding ||
        point.longitude > maxLng + padding) {
      return false; // Totalmente fuera de la caja delimitadora, se descarta rápido
    }

    // Si pasa la caja, recorremos los puntos calculando la distancia Haversine exacta
    for (LatLng p in polyline) {
      final double distance = calculateDistance(point, p);
      if (distance <= maxDistanceKm) {
        return true;
      }
    }
    return false;
  }

  /// Returns the subset of roadblocks that geometrically intersect/obstruct the given route polyline.
  static List<Map<String, dynamic>> detectRoadblockCollisions(
    List<LatLng> polyline,
    List<Map<String, dynamic>> activeRoadblocks, {
    double thresholdKm = 1.2,
  }) {
    final List<Map<String, dynamic>> collisions = [];

    for (var roadblock in activeRoadblocks) {
      final double? lat = double.tryParse(roadblock['latitud_inicio']?.toString() ?? '');
      final double? lng = double.tryParse(roadblock['longitud_inicio']?.toString() ?? '');

      if (lat != null && lng != null) {
        final roadblockPos = LatLng(lat, lng);
        if (isPointNearRoute(roadblockPos, polyline, thresholdKm)) {
          collisions.add(roadblock);
        }
      }
    }

    return collisions;
  }
}
