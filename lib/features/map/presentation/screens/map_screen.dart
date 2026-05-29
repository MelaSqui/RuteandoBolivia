import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ruteando_bolivia/theme/app_theme.dart';

/// A single road event from the Supabase `road_events` table.
class RoadEvent {
  final int id;
  final String ruta;
  final String departamento;
  final String evento;
  final String restriccion;
  final String? desvio;
  final String? trabajos;
  final double? lat;
  final double? lng;
  final String? horaReporte;
  final String categoria; // computed

  RoadEvent({
    required this.id,
    required this.ruta,
    required this.departamento,
    required this.evento,
    required this.restriccion,
    this.desvio,
    this.trabajos,
    this.lat,
    this.lng,
    this.horaReporte,
    required this.categoria,
  });

  factory RoadEvent.fromJson(Map<String, dynamic> json) {
    final evento = (json['evento'] ?? '').toString().toUpperCase();
    String categoria;
    if (evento.contains('BLOQUEO')) {
      categoria = 'Bloqueo';
    } else if (evento.contains('DERRUMBE') || evento.contains('BARRO') || evento.contains('INUNDACION')) {
      categoria = 'Derrumbe / Clima';
    } else if (evento.contains('CONSTRUCCION') || evento.contains('MANTENIMIENTO')) {
      categoria = 'Obras Viales';
    } else if (evento == 'NINGUN EVENTO' || evento.isEmpty) {
      // Check restriccion
      final restriccion = (json['restriccion_vehicular'] ?? '').toString().toUpperCase();
      if (restriccion.contains('NO CIRCULAR')) {
        categoria = 'Bloqueo';
      } else if (restriccion.contains('PRECAUCIÓN') || restriccion.contains('PRECAUCION')) {
        categoria = 'Precaución';
      } else {
        categoria = 'Precaución';
      }
    } else {
      categoria = 'Otro';
    }

    return RoadEvent(
      id: json['id'] as int,
      ruta: json['ruta']?.toString() ?? '',
      departamento: json['departamento']?.toString() ?? '',
      evento: json['evento']?.toString() ?? 'Sin evento',
      restriccion: json['restriccion_vehicular']?.toString() ?? '',
      desvio: json['transitable_con_desvio']?.toString(),
      trabajos: json['trabajos_conservacion']?.toString(),
      lat: (json['latitud_inicio'] as num?)?.toDouble(),
      lng: (json['longitud_inicio'] as num?)?.toDouble(),
      horaReporte: json['hora_reporte']?.toString(),
      categoria: categoria,
    );
  }
}

class MapaTransitabilidad extends StatefulWidget {
  const MapaTransitabilidad({super.key});

  @override
  State<MapaTransitabilidad> createState() => _MapaTransitabilidadState();
}

class _MapaTransitabilidadState extends State<MapaTransitabilidad> {
  final LatLng _boliviaCenter = const LatLng(-16.2902, -63.5887);
  final SupabaseClient _supabase = Supabase.instance.client;

  List<RoadEvent> _allEvents = [];
  bool _isLoading = true;

  // Filter states - all start enabled
  final Map<String, bool> _filters = {
    'Bloqueo': true,
    'Derrumbe / Clima': true,
    'Obras Viales': true,
    'Precaución': true,
    'Otro': true,
  };

  // Category visual config
  static const Map<String, _CategoryStyle> _categoryStyles = {
    'Bloqueo': _CategoryStyle(Colors.red, Icons.block_rounded),
    'Derrumbe / Clima': _CategoryStyle(Colors.orange, Icons.landslide_rounded),
    'Obras Viales': _CategoryStyle(Colors.amber, Icons.construction_rounded),
    'Precaución': _CategoryStyle(Colors.blue, Icons.warning_amber_rounded),
    'Otro': _CategoryStyle(Colors.grey, Icons.info_outline_rounded),
  };

  @override
  void initState() {
    super.initState();
    _fetchEvents();
  }

  Future<void> _fetchEvents() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase
          .from('road_events')
          .select('id, ruta, departamento, evento, restriccion_vehicular, transitable_con_desvio, trabajos_conservacion, latitud_inicio, longitud_inicio, hora_reporte')
          .order('id', ascending: false);

      final events = (response as List)
          .map((e) => RoadEvent.fromJson(e))
          .where((e) => e.lat != null && e.lng != null)
          .toList();

      if (!mounted) return;
      setState(() {
        _allEvents = events;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  List<RoadEvent> get _filteredEvents {
    return _allEvents.where((e) => _filters[e.categoria] == true).toList();
  }

  void _showEventDetails(BuildContext context, RoadEvent event) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final style = _categoryStyles[event.categoria] ?? _categoryStyles['Otro']!;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            // Header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: style.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(style.icon, color: style.color, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.evento,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${_formatRuta(event.ruta)} · ${event.departamento}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _detailRow(Icons.traffic_rounded, 'Restricción', event.restriccion, isDark),
            if (event.desvio != null && event.desvio!.isNotEmpty)
              _detailRow(Icons.alt_route_rounded, 'Desvío', event.desvio!, isDark),
            if (event.trabajos != null && event.trabajos!.isNotEmpty)
              _detailRow(Icons.engineering_rounded, 'Trabajos', event.trabajos!, isDark),
            if (event.horaReporte != null)
              _detailRow(Icons.access_time_rounded, 'Último reporte', _formatDateTime(event.horaReporte!), isDark),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _formatRuta(String ruta) {
    try {
      final parsed = int.parse(ruta);
      return 'Ruta $parsed';
    } catch (_) {
      return 'Ruta $ruta';
    }
  }

  String _formatDateTime(String dateTime) {
    try {
      final dt = DateTime.parse(dateTime);
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateTime;
    }
  }

  Widget _detailRow(IconData icon, String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: isDark ? AppTheme.darkBackground : AppTheme.lightBackground),
          Positioned.fill(
            child: Opacity(
              opacity: isDark ? 0.65 : 0.45,
              child: Image.asset(
                isDark ? 'assets/patterns/oscuro.png' : 'assets/patterns/claro.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          Column(
            children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: AppTheme.positive,
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        width: 40,
                        height: 40,
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
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.route_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Ruteando Bolivia',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.positive,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, color: AppTheme.positive),
                        onPressed: _fetchEvents,
                        tooltip: 'Actualizar eventos',
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    // ──── Map ────
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
              MarkerLayer(
                markers: _filteredEvents.map((event) {
                  final style = _categoryStyles[event.categoria] ?? _categoryStyles['Otro']!;
                  return Marker(
                    point: LatLng(event.lat!, event.lng!),
                    width: 36,
                    height: 36,
                    child: GestureDetector(
                      onTap: () => _showEventDetails(context, event),
                      child: Container(
                        decoration: BoxDecoration(
                          color: style.color,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: style.color.withOpacity(0.4),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Icon(style.icon, color: Colors.white, size: 18),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          // ──── Filter Chips Row ────
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: _filters.keys.map((category) {
                  final isActive = _filters[category]!;
                  final style = _categoryStyles[category]!;
                  final count = _allEvents.where((e) => e.categoria == category).length;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: isActive,
                      onSelected: (selected) {
                        setState(() => _filters[category] = selected);
                      },
                      avatar: Icon(style.icon, size: 16,
                          color: isActive ? Colors.white : style.color),
                      label: Text(
                        '$category ($count)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isActive
                              ? Colors.white
                              : (isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                      selectedColor: style.color,
                      backgroundColor: isDark
                          ? const Color(0xFF1C2333).withOpacity(0.9)
                          : Colors.white.withOpacity(0.9),
                      checkmarkColor: Colors.white,
                      side: BorderSide(
                        color: isActive ? style.color : Colors.grey.withOpacity(0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 2,
                      shadowColor: style.color.withOpacity(0.3),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // ──── Loading indicator ────
          if (_isLoading)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF161B22) : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Cargando eventos viales...',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ──── Events count badge ────
          if (!_isLoading)
            Positioned(
              bottom: 24,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF161B22) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _filteredEvents.any((e) => e.categoria == 'Bloqueo')
                            ? Colors.red
                            : Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_filteredEvents.length} de ${_allEvents.length} eventos',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryStyle {
  final Color color;
  final IconData icon;
  const _CategoryStyle(this.color, this.icon);
}
