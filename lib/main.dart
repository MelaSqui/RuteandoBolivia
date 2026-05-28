import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'screens/auth/login_screen.dart';

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
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const AuthGate(),
    );
  }
}

/// AuthGate: Escucha el estado de autenticación de Supabase.
/// - Si hay sesión activa (token guardado localmente), va directo al mapa.
/// - Si no hay sesión, muestra el Login.
/// - La sesión persiste automáticamente gracias a supabase_flutter,
///   así que el usuario solo inicia sesión UNA VEZ.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // Mientras se resuelve la sesión, mostramos un splash sutil
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashScreen();
        }

        // Si hay sesión activa, ir al mapa
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          return const MapaTransitabilidad();
        }

        // Si no hay sesión, mostrar Login
        return const LoginScreen();
      },
    );
  }
}

/// Splash screen minimal mientras se verifica la sesión
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF0A0E14),
                    const Color(0xFF0F1923),
                  ]
                : [
                    const Color(0xFFE0F2FE),
                    const Color(0xFFF0FDF4),
                  ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withOpacity(0.7),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.route_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Ruteando Bolivia',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
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
