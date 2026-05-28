import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MapaTransitabilidad extends StatefulWidget {
  const MapaTransitabilidad({super.key});

  @override
  State<MapaTransitabilidad> createState() => _MapaTransitabilidadState();
}

class _MapaTransitabilidadState extends State<MapaTransitabilidad> {
  // Centro de Bolivia (aproximado)
  final LatLng _boliviaCenter = const LatLng(-16.2902, -63.5887);

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    // El AuthGate detectará el cambio y mostrará el Login automáticamente
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final patternAsset = isDark
        ? 'assets/patterns/roads_dark.svg'
        : 'assets/patterns/roads_light.svg';

    // Obtener info del usuario actual
    final user = Supabase.instance.client.auth.currentUser;
    final displayName =
        user?.userMetadata?['display_name'] as String? ?? 'Viajero';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('Hola, $displayName 👋'),
        backgroundColor: theme.colorScheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Cerrar sesión',
            onPressed: _signOut,
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(color: theme.colorScheme.surface),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: isDark ? 0.06 : 0.04,
              child: SvgPicture.asset(
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
