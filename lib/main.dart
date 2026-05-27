import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: 'https://kuqwxsjfidashrtwxslx.supabase.co',
    anonKey: 'sb_publishable_WrMRiFSODTPFYPuuQzIFzA_a7FUebpV',
  );

  runApp(const RuteandoBoliviaApp());
}

class RuteandoBoliviaApp extends StatelessWidget {
  const RuteandoBoliviaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ruteando Bolivia',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final patternAsset = isDark
        ? 'assets/patterns/roads_dark.svg'
        : 'assets/patterns/roads_light.svg';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Rutas y Bloqueos'),
        backgroundColor: theme.colorScheme.surface,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(color: theme.colorScheme.background),
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
                    theme.colorScheme.background.withOpacity(0.0),
                    theme.colorScheme.background.withOpacity(0.16),
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
