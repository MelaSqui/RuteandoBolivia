import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // TODO: Reemplazar con credenciales reales de Supabase
  // await Supabase.initialize(
  //   url: 'YOUR_SUPABASE_URL',
  //   anonKey: 'YOUR_SUPABASE_ANON_KEY',
  // );

  runApp(const RuteandoBoliviaApp());
}

class RuteandoBoliviaApp extends StatelessWidget {
  const RuteandoBoliviaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ruteando Bolivia',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MapaTransitabilidad(),
    );
  }
}

class MapaTransitabilidad extends StatefulWidget {
  const MapaTransitabilidad({super.key});

  @override
  State<MapaTransitabilidad> createState() => _MapaTransitabilidadState();
}

class _MapaTransitabilidadState extends State<MapaTransitabilidad> {
  // Centro de Bolivia (aproximado)
  final LatLng _boliviaCenter = const LatLng(-16.2902, -63.5887);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rutas y Bloqueos'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: _boliviaCenter,
          initialZoom: 6.0,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.ruteandobolivia',
          ),
          // Aquí agregaremos luego los marcadores que vengan de Supabase
        ],
      ),
    );
  }
}
