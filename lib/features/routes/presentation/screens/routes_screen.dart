import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:ruteando_bolivia/theme/app_theme.dart';
import 'package:ruteando_bolivia/features/routes/data/services/route_service.dart';
import 'package:ruteando_bolivia/features/routes/utils/route_utils.dart';
import 'package:ruteando_bolivia/features/discovery/data/services/gemini_service.dart';

class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key});

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  final RouteService _routeService = RouteService();
  final GeminiService _geminiService = GeminiService();
  final SupabaseClient _supabase = Supabase.instance.client;

  // Initial center on Bolivia
  final LatLng _boliviaCenter = const LatLng(-16.2902, -63.5887);

  LatLng? _originCoords;
  String _originName = 'Mi Ubicación actual';
  LatLng? _destinationCoords;
  String _destinationName = '';

  final TextEditingController _destinationController = TextEditingController();
  final FocusNode _destinationFocusNode = FocusNode();
  List<Map<String, dynamic>> _suggestions = [];
  bool _isSearching = false;
  Timer? _debounce;

  bool _isLoadingRoutes = false;
  List<Map<String, dynamic>> _routeAlternatives = [];
  List<List<Map<String, dynamic>>> _roadblocksPerRoute = [];
  int _selectedRouteIndex = 0;
  List<Map<String, dynamic>> _activeRoadblocks = [];

  String _aiRecommendation = '';
  bool _isLoadingAI = false;
  bool _hasSearched = false;

  // Quick Questions
  final List<String> _quickQuestions = [
    '¿Cuál es el tramo exacto bloqueado?',
    '¿Hay desvíos recomendados?',
    '¿Qué vehículos pueden pasar?',
  ];
  String? _customAiAnswer;
  bool _isLoadingCustomAiAnswer = false;

  // Pulse animation for AI Copiloto
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initOriginLocation();
    _fetchActiveRoadblocks();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _destinationController.dispose();
    _destinationFocusNode.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _fetchActiveRoadblocks() async {
    try {
      final response = await _supabase
          .from('road_events')
          .select('id, ruta, departamento, evento, restriccion_vehicular, transitable_con_desvio, latitud_inicio, longitud_inicio, raw_data');
      if (response != null) {
        setState(() {
          _activeRoadblocks = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Error fetching roadblocks: $e');
    }
  }

  Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }

      if (permission == LocationPermission.deniedForever) return null;

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 4),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _initOriginLocation() async {
    try {
      final position = await _getCurrentLocation();
      if (position != null && mounted) {
        setState(() {
          _originCoords = LatLng(position.latitude, position.longitude);
          _originName = 'Mi Ubicación actual';
        });
      } else {
        if (mounted) {
          setState(() {
            // Fallback: Centro neurálgico vial en Cochabamba, Bolivia
            _originCoords = const LatLng(-17.3935, -66.1570);
            _originName = 'Cochabamba (Centro)';
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _originCoords = const LatLng(-17.3935, -66.1570);
          _originName = 'Cochabamba (Centro)';
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (query.trim().isEmpty) {
        setState(() {
          _suggestions = [];
        });
        return;
      }
      setState(() => _isSearching = true);
      final list = await _routeService.searchPlaces(query);
      if (mounted) {
        setState(() {
          _suggestions = list;
          _isSearching = false;
        });
      }
    });
  }

  Future<void> _calculateRoutes(LatLng destCoords, String destName) async {
    setState(() {
      _isLoadingRoutes = true;
      _isLoadingAI = true;
      _destinationCoords = destCoords;
      _destinationName = destName;
      _hasSearched = true;
      _suggestions = [];
      _selectedRouteIndex = 0;
      _aiRecommendation = '';
      _customAiAnswer = null;
    });

    _destinationController.text = destName.split(',').first;
    _destinationFocusNode.unfocus();

    // Fetch roadblocks if not already done
    if (_activeRoadblocks.isEmpty) {
      await _fetchActiveRoadblocks();
    }

    if (_originCoords == null) {
      await _initOriginLocation();
    }

    final origin = _originCoords ?? const LatLng(-17.3935, -66.1570);
    final routes = await _routeService.getRouteAlternatives(origin, destCoords);

    if (routes.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoadingRoutes = false;
          _isLoadingAI = false;
          _routeAlternatives = [];
          _roadblocksPerRoute = [];
          _aiRecommendation = 'No se encontraron alternativas de ruta. Comprueba tu conexión o ingresa otro destino.';
        });
      }
      return;
    }

    // Detect intersections with active roadblocks
    final List<List<Map<String, dynamic>>> roadblocksPerRoute = [];
    for (var route in routes) {
      final List<LatLng> polyline = route['polyline'] as List<LatLng>;
      final collisions = RouteUtils.detectRoadblockCollisions(polyline, _activeRoadblocks);
      roadblocksPerRoute.add(collisions);
    }

    // ── RECÁLCULO INTELIGENTE ──
    // Si TODAS las rutas directas están bloqueadas, buscar desvíos por pueblos intermedios
    final bool allRoutesBlocked = roadblocksPerRoute.every((blocks) => blocks.isNotEmpty);

    List<Map<String, dynamic>> finalRoutes = List.from(routes);
    List<List<Map<String, dynamic>>> finalRoadblocks = List.from(roadblocksPerRoute);

    if (allRoutesBlocked) {
      debugPrint('[Ruteando] Todas las rutas directas bloqueadas — iniciando recálculo inteligente...');

      // Mostrar estado intermedio al usuario mientras se recalcula
      if (mounted) {
        setState(() {
          _routeAlternatives = finalRoutes;
          _roadblocksPerRoute = finalRoadblocks;
          _aiRecommendation = '⏳ Todas las rutas directas están bloqueadas. Buscando desvíos inteligentes por pueblos intermedios...';
        });
      }

      // Buscar pueblos intermedios cercanos a la ruta
      final waypoints = await _routeService.findIntermediateWaypoints(origin, destCoords);
      debugPrint('[Ruteando] Waypoints intermedios encontrados: ${waypoints.map((w) => w['name']).toList()}');

      for (var wp in waypoints) {
        final wpCoords = LatLng(wp['latitude'] as double, wp['longitude'] as double);
        final wpName = wp['name'] as String;

        final detourRoute = await _routeService.getRouteViaWaypoint(origin, wpCoords, destCoords);
        if (detourRoute != null) {
          // Verificar si esta ruta alternativa es realmente diferente de las existentes
          final detourPolyline = detourRoute['polyline'] as List<LatLng>;
          final bool isDuplicate = finalRoutes.any((existingRoute) {
            final existingPoly = existingRoute['polyline'] as List<LatLng>;
            // Compare midpoints — if they're very close, routes are likely the same
            if (existingPoly.isEmpty || detourPolyline.isEmpty) return false;
            final existingMid = existingPoly[existingPoly.length ~/ 2];
            final detourMid = detourPolyline[detourPolyline.length ~/ 2];
            return RouteUtils.calculateDistance(existingMid, detourMid) < 2.0; // < 2km apart = duplicate
          });

          if (!isDuplicate) {
            // Etiquetar la ruta con el nombre del pueblo por donde pasa
            detourRoute['summary'] = 'Desvío vía $wpName';
            detourRoute['is_detour'] = true;

            // Detectar bloqueos en esta ruta alternativa
            final detourCollisions = RouteUtils.detectRoadblockCollisions(detourPolyline, _activeRoadblocks);

            finalRoutes.add(detourRoute);
            finalRoadblocks.add(detourCollisions);

            debugPrint('[Ruteando] Desvío vía $wpName: ${detourRoute['distance_km']}km, ${detourCollisions.length} bloqueos');
          }
        }
      }

      // Reordenar: rutas libres primero, luego bloqueadas
      final combined = List.generate(finalRoutes.length, (i) => {
        'route': finalRoutes[i],
        'blocks': finalRoadblocks[i],
      });
      combined.sort((a, b) {
        final aBlocked = (a['blocks'] as List).isNotEmpty ? 1 : 0;
        final bBlocked = (b['blocks'] as List).isNotEmpty ? 1 : 0;
        return aBlocked.compareTo(bBlocked);
      });

      finalRoutes = combined.map((c) => c['route'] as Map<String, dynamic>).toList();
      finalRoadblocks = combined.map((c) => c['blocks'] as List<Map<String, dynamic>>).toList();
    }

    if (!mounted) return;

    setState(() {
      _routeAlternatives = finalRoutes;
      _roadblocksPerRoute = finalRoadblocks;
      _isLoadingRoutes = false;
      _selectedRouteIndex = 0;
    });

    // Fit map to show the first (best) route
    if (finalRoutes.isNotEmpty) {
      _fitMapToRoute(finalRoutes[0]['polyline'] as List<LatLng>);
    }

    // AI Safety Analysis
    try {
      final advice = await _geminiService.analyzeRouteSafety(
        origin: _originName,
        destination: _destinationName,
        routeAlternatives: finalRoutes,
        roadblocksPerRoute: finalRoadblocks,
      );
      if (mounted) {
        setState(() {
          _aiRecommendation = advice;
          _isLoadingAI = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _aiRecommendation = 'El copiloto Ruteando AI está temporalmente fuera de línea. Estado vial disponible en el mapa.';
          _isLoadingAI = false;
        });
      }
    }
  }

  void _fitMapToRoute(List<LatLng> points) {
    if (points.isEmpty) return;

    double minLat = points[0].latitude;
    double maxLat = points[0].latitude;
    double minLng = points[0].longitude;
    double maxLng = points[0].longitude;

    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final double centerLat = (minLat + maxLat) / 2;
    final double centerLng = (minLng + maxLng) / 2;

    final double latDiff = maxLat - minLat;
    final double lngDiff = maxLng - minLng;
    final double maxDiff = latDiff > lngDiff ? latDiff : lngDiff;

    double zoom = 7.0;
    if (maxDiff > 0) {
      // Scale zoom mathematically
      zoom = (11.5 - (maxDiff * 1.65).abs().toInt()).clamp(6.0, 13.0).toDouble();
    }

    _mapController.move(LatLng(centerLat, centerLng), zoom);
  }

  Future<void> _askCustomQuestion(String question) async {
    if (_routeAlternatives.isEmpty) return;
    setState(() {
      _isLoadingCustomAiAnswer = true;
      _customAiAnswer = '';
    });

    try {
      final route = _routeAlternatives[_selectedRouteIndex];
      final roadblocks = _roadblocksPerRoute[_selectedRouteIndex];
      final summary = route['summary'] ?? 'Ruta principal';
      final dist = (route['distance_km'] as double?)?.toStringAsFixed(1) ?? '0.0';
      final dur = (route['duration_min'] as double?)?.toStringAsFixed(0) ?? '0';

      final routeState = roadblocks.isEmpty 
          ? 'TOTALMENTE TRANSITABLE (libre de bloqueos)' 
          : 'BLOQUEADA / CON OBSTRUCCIONES (${roadblocks.length} incidentes detectados)';

      final blockDetailsText = roadblocks.map((r) {
        return '- ${r['evento'] ?? 'Bloqueo'} en Ruta ${r['ruta'] ?? ''} (${r['departamento'] ?? ''}). Desvío: ${r['transitable_con_desvio'] ?? 'No especificado'}.';
      }).join('\n');

      final systemPrompt = '''
Eres "Ruteando AI", un copiloto inteligente de viaje para Bolivia.
El usuario está consultando sobre la Ruta seleccionada (${_selectedRouteIndex + 1}) para viajar de $_originName a $_destinationName.
DETALLES DE ESTA RUTA:
- Vía: $summary
- Distancia: $dist km
- Duración estimada: $dur minutos
- Estado vial actual: $routeState

EVENTOS DE BLOQUEO DETECTADOS EN ESTA RUTA:
$blockDetailsText

PREGUNTA DEL CONDUCTOR:
"$question"

Responde en español de forma sumamente concisa (máximo 3 oraciones cortas y directas), recomendando qué hacer, usando un tono de copiloto amigable y usando un emoji descriptivo.
''';

      // Usar Gemini Service instance para hacer el llamado directo
      final response = await _geminiService.analyzeRouteSafety(
        origin: _originName,
        destination: _destinationName,
        routeAlternatives: [_routeAlternatives[_selectedRouteIndex]],
        roadblocksPerRoute: [_roadblocksPerRoute[_selectedRouteIndex]],
      );

      // Enviar pregunta detallada a Gemini a través de un chat express
      // Para simplificar y reutilizar el SDK de GenerativeModel
      final apiKey = const String.fromEnvironment('GEMINI_API_KEY');
      final model = GenerativeModel(
        model: 'gemini-3.5-flash',
        apiKey: apiKey,
      );

      final responseCustom = await model.generateContent([Content.text(systemPrompt)]);
      if (mounted) {
        setState(() {
          _customAiAnswer = responseCustom.text ?? 'No tengo información específica sobre esa consulta.';
          _isLoadingCustomAiAnswer = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _customAiAnswer = 'Lo siento, no pude procesar la consulta en este momento.';
          _isLoadingCustomAiAnswer = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Roadblocks intersecting the currently selected route
    final selectedRouteRoadblocks = _roadblocksPerRoute.isNotEmpty && _selectedRouteIndex < _roadblocksPerRoute.length
        ? _roadblocksPerRoute[_selectedRouteIndex]
        : [];

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── MAP BACKGROUND ──
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _boliviaCenter,
              initialZoom: 6.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.ruteandobolivia',
              ),
              // Draw polylines for route alternatives
              if (_routeAlternatives.isNotEmpty)
                PolylineLayer(
                  polylines: List<Polyline<Object>>.generate(_routeAlternatives.length, (index) {
                    final route = _routeAlternatives[index];
                    final roadblocks = _roadblocksPerRoute[index];
                    final bool isSelected = index == _selectedRouteIndex;
                    final bool isBlocked = roadblocks.isNotEmpty;

                    Color routeColor;
                    if (isBlocked) {
                      routeColor = isSelected ? AppTheme.danger : AppTheme.danger.withOpacity(0.35);
                    } else {
                      routeColor = isSelected ? AppTheme.positive : AppTheme.positive.withOpacity(0.35);
                    }

                    return Polyline<Object>(
                      points: route['polyline'] as List<LatLng>,
                      color: routeColor,
                      strokeWidth: isSelected ? 6.5 : 3.5,
                      borderColor: isSelected ? Colors.white.withOpacity(0.8) : Colors.transparent,
                      borderStrokeWidth: isSelected ? 1.5 : 0.0,
                    );
                  }),
                ),

              // Roadblock Markers (only show markers of roadblocks intersecting our current alternatives)
              MarkerLayer(
                markers: [
                  // Draw User Origin
                  if (_originCoords != null)
                    Marker(
                      point: _originCoords!,
                      width: 44,
                      height: 44,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.climate,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.climate.withOpacity(0.4),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.my_location_rounded, color: Colors.white, size: 18),
                      ),
                    ),

                  // Draw Roadblocks
                  ..._activeRoadblocks.map((roadblock) {
                    final double? lat = double.tryParse(roadblock['latitud_inicio']?.toString() ?? '');
                    final double? lng = double.tryParse(roadblock['longitud_inicio']?.toString() ?? '');

                    if (lat == null || lng == null) return const Marker(point: LatLng(0,0), child: SizedBox());

                    // Check if this roadblock affects current selected route
                    final bool affectsSelectedRoute = selectedRouteRoadblocks.any((r) => r['id'] == roadblock['id']);

                    return Marker(
                      point: LatLng(lat, lng),
                      width: affectsSelectedRoute ? 42 : 32,
                      height: affectsSelectedRoute ? 42 : 32,
                      child: GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${roadblock['evento'] ?? 'Bloqueo'} en Ruta ${roadblock['ruta'] ?? ''}: ${roadblock['restriccion_vehicular'] ?? ''}',
                              ),
                              backgroundColor: AppTheme.danger,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          decoration: BoxDecoration(
                            color: affectsSelectedRoute ? AppTheme.danger : AppTheme.warning.withOpacity(0.8),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: affectsSelectedRoute ? Colors.white : Colors.white.withOpacity(0.8),
                              width: affectsSelectedRoute ? 2.5 : 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: affectsSelectedRoute
                                    ? AppTheme.danger.withOpacity(0.5)
                                    : AppTheme.warning.withOpacity(0.3),
                                blurRadius: affectsSelectedRoute ? 12 : 6,
                                spreadRadius: affectsSelectedRoute ? 2 : 1,
                              ),
                            ],
                          ),
                          child: Icon(
                            affectsSelectedRoute ? Icons.block_rounded : Icons.warning_rounded,
                            color: Colors.white,
                            size: affectsSelectedRoute ? 20 : 15,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),

          // ── FLOATING PREMIUM GLASSMORPHIC SEARCH BAR ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    isDark ? Colors.black.withOpacity(0.85) : Colors.white.withOpacity(0.85),
                    isDark ? Colors.black.withOpacity(0.0) : Colors.white.withOpacity(0.0),
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header title
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [AppTheme.positive, AppTheme.positive.withOpacity(0.7)],
                              ),
                            ),
                            child: const Icon(Icons.directions_rounded, color: Colors.white, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Ruteando Bolivia',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: AppTheme.positive,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const Spacer(),
                          if (_isLoadingRoutes)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.positive),
                            )
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Glassmorphic floating card containing inputs
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.black.withOpacity(0.4) : Colors.white.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 20,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Origin read-only
                                Row(
                                  children: [
                                    const Icon(Icons.circle, color: AppTheme.climate, size: 12),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _originName,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.white70 : Colors.black87,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.gps_fixed_rounded, size: 18, color: AppTheme.climate),
                                      onPressed: _initOriginLocation,
                                      tooltip: 'Recargar GPS',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 6.0),
                                  child: Divider(height: 1, color: Colors.white24),
                                ),

                                // Destination field
                                Row(
                                  children: [
                                    const Icon(Icons.location_on_rounded, color: AppTheme.danger, size: 16),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextField(
                                        controller: _destinationController,
                                        focusNode: _destinationFocusNode,
                                        style: theme.textTheme.bodyLarge?.copyWith(fontSize: 14),
                                        decoration: InputDecoration(
                                          hintText: 'Buscar ciudad o destino...',
                                          hintStyle: TextStyle(
                                            color: isDark ? Colors.white38 : Colors.black38,
                                            fontSize: 14,
                                          ),
                                          border: InputBorder.none,
                                          filled: false,
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                        onChanged: _onSearchChanged,
                                      ),
                                    ),
                                    if (_destinationController.text.isNotEmpty)
                                      IconButton(
                                        icon: const Icon(Icons.clear_rounded, size: 16, color: Colors.grey),
                                        onPressed: () {
                                          setState(() {
                                            _destinationController.clear();
                                            _destinationCoords = null;
                                            _destinationName = '';
                                            _suggestions = [];
                                            _hasSearched = false;
                                            _routeAlternatives = [];
                                            _roadblocksPerRoute = [];
                                          });
                                        },
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Search Suggestions Overlay List
                      if (_isSearching || _suggestions.isNotEmpty)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(top: 8),
                          constraints: const BoxConstraints(maxHeight: 220),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF161B22) : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              )
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: _isSearching
                                ? const Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Center(
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.positive),
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: _suggestions.length,
                                    separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.white12),
                                    itemBuilder: (context, index) {
                                      final sug = _suggestions[index];
                                      final displayName = sug['name'].toString();
                                      final shortName = displayName.split(',').first;
                                      final extra = displayName.contains(',') 
                                          ? displayName.substring(displayName.indexOf(',') + 1).trim()
                                          : 'Bolivia';

                                      return ListTile(
                                        dense: true,
                                        leading: const Icon(Icons.place_rounded, color: AppTheme.positive, size: 18),
                                        title: Text(
                                          shortName,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                        subtitle: Text(
                                          extra,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                                        ),
                                        onTap: () {
                                          final lat = sug['latitude'] as double;
                                          final lon = sug['longitude'] as double;
                                          _calculateRoutes(LatLng(lat, lon), displayName);
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── FLOATING GPS BUTTON ──
          Positioned(
            right: 16,
            bottom: _hasSearched ? 320 : 32,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
              foregroundColor: AppTheme.positive,
              onPressed: () {
                if (_originCoords != null) {
                  _mapController.move(_originCoords!, 12);
                } else {
                  _initOriginLocation();
                }
              },
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.gps_fixed_rounded),
            ),
          ),

          // ── BOTTOM DRAGGABLE SCROLL PANEL (Ruta & AI) ──
          if (_hasSearched)
            DraggableScrollableSheet(
              initialChildSize: 0.35,
              minChildSize: 0.22,
              maxChildSize: 0.85,
              snap: true,
              builder: (context, scrollController) {
                final bool activeRouteIsBlocked = _roadblocksPerRoute.isNotEmpty && 
                    _selectedRouteIndex < _roadblocksPerRoute.length &&
                    _roadblocksPerRoute[_selectedRouteIndex].isNotEmpty;

                return ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF141822).withOpacity(0.85) : Colors.white.withOpacity(0.9),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(30),
                          topRight: Radius.circular(30),
                        ),
                        border: Border.all(
                          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 30,
                            offset: const Offset(0, -5),
                          )
                        ],
                      ),
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        children: [
                          // Sheet Handle
                          Center(
                            child: Container(
                              width: 50,
                              height: 5,
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.4),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),

                          // Header status badge
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Alternativas de Ruteo',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: activeRouteIsBlocked 
                                      ? AppTheme.danger.withOpacity(0.15) 
                                      : AppTheme.positive.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: activeRouteIsBlocked ? AppTheme.danger : AppTheme.positive,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      activeRouteIsBlocked ? Icons.block_rounded : Icons.verified_user_rounded,
                                      color: activeRouteIsBlocked ? AppTheme.danger : AppTheme.positive,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      activeRouteIsBlocked ? 'CON BLOQUEOS' : 'RUTA LIBRE',
                                      style: TextStyle(
                                        color: activeRouteIsBlocked ? AppTheme.danger : AppTheme.positive,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Horizontal scroll route alternatives selector
                          SizedBox(
                            height: 105,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _routeAlternatives.length,
                              itemBuilder: (context, index) {
                                final route = _routeAlternatives[index];
                                final blocks = _roadblocksPerRoute[index];
                                final isSelected = index == _selectedRouteIndex;
                                final bool hasBlocks = blocks.isNotEmpty;

                                final double km = route['distance_km'] as double;
                                final double mins = route['duration_min'] as double;
                                final String timeString = mins >= 60
                                    ? '${(mins / 60).floor()}h ${(mins % 60).round()}m'
                                    : '${mins.round()} min';

                                final bool isDetour = route['is_detour'] == true;

                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedRouteIndex = index;
                                      _customAiAnswer = null; // Clear previous custom QA
                                    });
                                    _fitMapToRoute(route['polyline'] as List<LatLng>);
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    width: 180,
                                    margin: const EdgeInsets.only(right: 12, bottom: 8),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? (hasBlocks ? AppTheme.danger.withOpacity(0.08) : AppTheme.positive.withOpacity(0.08))
                                          : (isDark ? AppTheme.darkCard : Colors.white),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isSelected
                                            ? (hasBlocks ? AppTheme.danger : AppTheme.positive)
                                            : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                                        width: isSelected ? 2 : 1,
                                      ),
                                      boxShadow: [
                                        if (isSelected)
                                          BoxShadow(
                                            color: (hasBlocks ? AppTheme.danger : AppTheme.positive).withOpacity(0.15),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          )
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                route['summary'] ?? 'Vía Alternativa',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                                              ),
                                            ),
                                            Icon(
                                              isDetour
                                                  ? Icons.alt_route_rounded
                                                  : (hasBlocks ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded),
                                              color: isDetour
                                                  ? AppTheme.climate
                                                  : (hasBlocks ? AppTheme.warning : AppTheme.positive),
                                              size: 16,
                                            ),
                                          ],
                                        ),
                                        Text(
                                          '${km.toStringAsFixed(1)} km · $timeString',
                                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                                        ),
                                        Row(
                                          children: [
                                            if (isDetour) ...[
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                margin: const EdgeInsets.only(right: 6),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.climate.withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Text(
                                                  'DESVÍO',
                                                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppTheme.climate),
                                                ),
                                              ),
                                            ],
                                            Text(
                                              hasBlocks ? '${blocks.length} bloqueos' : 'Transitable',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                                color: hasBlocks ? AppTheme.danger : AppTheme.positive,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ──── COPILOTO RUTEANDO AI WIDGET ────
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: isDark
                                      ? [const Color(0xFF132030), const Color(0xFF0C1420)]
                                      : [const Color(0xFFEFF6FF), const Color(0xFFDBEAFE)],
                                ),
                                border: Border.all(
                                  color: isDark ? const Color(0xFF1D3557) : const Color(0xFFBFDBFE),
                                  width: 1.5,
                                ),
                              ),
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // AI Title & Glowing Avatar
                                  Row(
                                    children: [
                                      Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          ScaleTransition(
                                            scale: _pulseAnimation,
                                            child: Container(
                                              width: 38,
                                              height: 38,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: AppTheme.positive.withOpacity(0.2),
                                              ),
                                            ),
                                          ),
                                          Container(
                                            width: 30,
                                            height: 30,
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: LinearGradient(
                                                colors: [AppTheme.positive, AppTheme.climate],
                                              ),
                                            ),
                                            child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 18),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Copiloto Ruteando AI',
                                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                                          ),
                                          Row(
                                            children: [
                                              Container(
                                                width: 6,
                                                height: 6,
                                                decoration: const BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: AppTheme.positive,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                _isLoadingAI ? 'Pensando...' : 'Asistente de viaje activo',
                                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                                              ),
                                            ],
                                          )
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),

                                  // AI Text Box
                                  if (_isLoadingAI)
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _shimmerLine(width: double.infinity),
                                        const SizedBox(height: 8),
                                        _shimmerLine(width: 240),
                                        const SizedBox(height: 8),
                                        _shimmerLine(width: 180),
                                      ],
                                    )
                                  else ...[
                                    Text(
                                      _aiRecommendation,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.45,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 14),

                                    // Quick questions title
                                    const Text(
                                      'Pregúntale al copiloto AI:',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey),
                                    ),
                                    const SizedBox(height: 8),

                                    // Quick questions scrollable chips
                                    SizedBox(
                                      height: 38,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: _quickQuestions.length,
                                        itemBuilder: (context, index) {
                                          final question = _quickQuestions[index];
                                          return Padding(
                                            padding: const EdgeInsets.only(right: 8.0),
                                            child: ActionChip(
                                              label: Text(question),
                                              labelStyle: TextStyle(
                                                fontSize: 11,
                                                color: isDark ? Colors.white70 : Colors.black87,
                                              ),
                                              backgroundColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                              side: BorderSide(
                                                color: isDark ? Colors.white10 : Colors.black12,
                                              ),
                                              onPressed: () => _askCustomQuestion(question),
                                            ),
                                          );
                                        },
                                      ),
                                    ),

                                    // Render custom AI answer block
                                    if (_isLoadingCustomAiAnswer || _customAiAnswer != null) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: Colors.white12),
                                        ),
                                        child: _isLoadingCustomAiAnswer
                                            ? Row(
                                                children: [
                                                  const SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.positive),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Text(
                                                    'Consultando copiloto...',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontStyle: FontStyle.italic,
                                                      color: isDark ? Colors.white70 : Colors.black87,
                                                    ),
                                                  )
                                                ],
                                              )
                                            : Text(
                                                _customAiAnswer!,
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  height: 1.4,
                                                  fontWeight: FontWeight.w500,
                                                  color: isDark ? Colors.white : Colors.black87,
                                                ),
                                              ),
                                      ),
                                    ],
                                  ]
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 80), // spacer for list bottom scrolling
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _shimmerLine({required double width}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: 12,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
