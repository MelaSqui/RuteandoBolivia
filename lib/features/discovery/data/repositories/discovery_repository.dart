import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/tourist_destination.dart';

class DiscoveryRepository {
  final SupabaseClient _supabase;

  DiscoveryRepository({SupabaseClient? supabase}) 
      : _supabase = supabase ?? Supabase.instance.client;

  Future<List<TouristDestination>> getTouristDestinations() async {
    try {
      final response = await _supabase
          .from('tourist_destinations')
          .select()
          .order('name');
          
      return (response as List).map((json) => TouristDestination.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching destinations: $e');
      return [];
    }
  }

  /// Obtains the list of active blocked routes.
  /// Returns a list of required_highway IDs that are currently blocked.
  Future<List<String>> getActiveBlockades() async {
    try {
      // Find events that are blocks/intransitable
      // Depending on the scraper, we might check `transitable == false` or `evento ILIKE '%BLOQUEO%'`
      final response = await _supabase
          .from('road_events')
          .select('ruta')
          .or('evento.eq.BLOQUEO,restriccion_vehicular.eq.NO CIRCULAR');
      
      // Extract unique route IDs
      final Set<String> blockedRoutes = {};
      for (var row in response) {
        if (row['ruta'] != null) {
          blockedRoutes.add(row['ruta'].toString());
        }
      }
      
      return blockedRoutes.toList();
    } catch (e) {
      print('Error fetching active blockades: $e');
      return [];
    }
  }
}
