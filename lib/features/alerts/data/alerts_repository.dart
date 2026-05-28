import 'package:supabase_flutter/supabase_flutter.dart';

class AlertsRepository {
  final _client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> fetchRoadEvents() async {
    final response = await _client
        .from('road_events')
        .select()
        .order('hora_reporte', ascending: false);
    return List<Map<String, dynamic>>.from(response as List);
  }
}
