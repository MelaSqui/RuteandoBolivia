import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final patternAsset = isDark
        ? 'assets/patterns/oscuro.png'
        : 'assets/patterns/claro.png';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Ruteando Bolivia'),
        backgroundColor: theme.colorScheme.surface,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(color: theme.colorScheme.surface),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: isDark ? 0.08 : 0.05,
              child: Image.asset(
                patternAsset,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.colorScheme.surface.withOpacity(0.0),
                    theme.colorScheme.surface.withOpacity(0.16),
                  ],
                ),
              ),
            ),
          ),
          FlutterMap(
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
        ],
      ),
    );
  }
}
