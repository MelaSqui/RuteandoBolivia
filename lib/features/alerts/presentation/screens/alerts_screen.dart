import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:ruteando_bolivia/features/alerts/data/alerts_repository.dart';
import 'package:ruteando_bolivia/features/alerts/presentation/widgets/alert_card.dart';
import 'package:ruteando_bolivia/theme/app_theme.dart';
import 'package:ruteando_bolivia/features/routes/utils/route_utils.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final _repo = AlertsRepository();
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _events = [];
  bool _isLoading = true;
  String? _error;
  String _query = '';
  LatLng? _userLocation;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      try {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
          Position? position = await Geolocator.getLastKnownPosition();
          if (position == null) {
            position = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.low,
            ).timeout(const Duration(seconds: 2));
          }
          _userLocation = LatLng(position.latitude, position.longitude);
        }
      } catch (_) {
        _userLocation = null;
      }

      final data = await _repo.fetchRoadEvents();
      setState(() {
        _events = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final activeEvents = _events.where((e) {
      final rawData = e['raw_data'];
      Map<String, dynamic>? raw;
      if (rawData is Map<String, dynamic>) {
        raw = rawData;
      } else if (rawData is String) {
        try {
          raw = json.decode(rawData) as Map<String, dynamic>;
        } catch (_) {}
      }
      final sigue = int.tryParse(raw?['votos_sigue']?.toString() ?? '0') ?? 0;
      final despejado = int.tryParse(raw?['votos_despejado']?.toString() ?? '0') ?? 0;
      return !(despejado >= 1 && despejado > sigue);
    }).toList();

    if (_query.isEmpty) return activeEvents;
    final q = _query.toLowerCase();
    return activeEvents.where((e) {
      return (e['ruta'] ?? '').toString().toLowerCase().contains(q) ||
          (e['seccion'] ?? '').toString().toLowerCase().contains(q) ||
          (e['departamento'] ?? '').toString().toLowerCase().contains(q) ||
          (e['evento'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  List<Map<String, dynamic>> get _sortedFiltered {
    final list = _filtered;
    if (_userLocation == null) return list;

    final sorted = List<Map<String, dynamic>>.from(list);
    sorted.sort((a, b) {
      final aLat = double.tryParse(a['latitud_inicio']?.toString() ?? '');
      final aLng = double.tryParse(a['longitud_inicio']?.toString() ?? '');
      final bLat = double.tryParse(b['latitud_inicio']?.toString() ?? '');
      final bLng = double.tryParse(b['longitud_inicio']?.toString() ?? '');

      if (aLat == null || aLng == null) return 1;
      if (bLat == null || bLng == null) return -1;

      final aDist = RouteUtils.calculateDistance(_userLocation!, LatLng(aLat, aLng));
      final bDist = RouteUtils.calculateDistance(_userLocation!, LatLng(bLat, bLng));

      return aDist.compareTo(bDist);
    });
    return sorted;
  }

  List<Map<String, dynamic>> get _nearbyEvents {
    if (_userLocation == null) return [];
    return _sortedFiltered.where((e) {
      final lat = double.tryParse(e['latitud_inicio']?.toString() ?? '');
      final lng = double.tryParse(e['longitud_inicio']?.toString() ?? '');
      if (lat == null || lng == null) return false;
      final dist = RouteUtils.calculateDistance(_userLocation!, LatLng(lat, lng));
      return dist <= 20.0;
    }).toList();
  }

  List<Map<String, dynamic>> get _otherEvents {
    if (_userLocation == null) return _sortedFiltered;
    final nearbyIds = _nearbyEvents.map((e) => e['id']).toSet();
    return _sortedFiltered.where((e) => !nearbyIds.contains(e['id'])).toList();
  }

  Map<String, List<Map<String, dynamic>>> get _groupedOthers {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final ev in _otherEvents) {
      final dept = (ev['departamento'] ?? 'OTROS').toString().toUpperCase();
      result.putIfAbsent(dept, () => []).add(ev);
    }
    return result;
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
          SafeArea(
            child: Column(
              children: [
                _AppBar(isDark: isDark, theme: theme),
                _SearchBar(
                  controller: _searchController,
                  query: _query,
                  isDark: isDark,
                  theme: theme,
                  onChanged: (v) => setState(() => _query = v),
                  onClear: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
                Expanded(child: _buildBody(theme, isDark)),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadEvents,
        backgroundColor: AppTheme.positive,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_alert_rounded),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, bool isDark) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: AppTheme.positive));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 52, color: AppTheme.danger),
              const SizedBox(height: 14),
              Text(
                'No se pudo cargar las alertas',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _loadEvents,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 60, color: AppTheme.positive),
            const SizedBox(height: 16),
            Text(
              _query.isEmpty ? 'Sin alertas activas' : 'Sin resultados',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _query.isEmpty
                  ? 'Las carreteras están transitables'
                  : 'Intenta con otro término',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    final nearby = _nearbyEvents;
    final groupedOthers = _groupedOthers;
    final items = <({String? dept, Map<String, dynamic>? event})>[];

    if (nearby.isNotEmpty) {
      items.add((dept: 'CERCANOS A TI', event: null));
      for (final ev in nearby) {
        items.add((dept: null, event: ev));
      }
    }

    for (final entry in groupedOthers.entries) {
      items.add((dept: entry.key, event: null));
      for (final ev in entry.value) {
        items.add((dept: null, event: ev));
      }
    }

    return RefreshIndicator(
      onRefresh: _loadEvents,
      color: AppTheme.positive,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          if (item.dept != null) {
            return _SectionHeader(label: item.dept!, theme: theme);
          }
          return AlertCard(
            key: ValueKey(item.event!['id']),
            event: item.event!,
            userLocation: _userLocation,
          );
        },
      ),
    );
  }
}

class _AppBar extends StatelessWidget {
  final bool isDark;
  final ThemeData theme;
  const _AppBar({required this.isDark, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Row(
        children: [
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
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final bool isDark;
  final ThemeData theme;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.query,
    required this.isDark,
    required this.theme,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: 'Buscar ciudad o carretera...',
            hintStyle: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              fontSize: 14,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            suffixIcon: query.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                    onPressed: onClear,
                  )
                : Icon(Icons.tune_rounded, color: AppTheme.positive),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final ThemeData theme;
  const _SectionHeader({required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppTheme.positive.withValues(alpha: 0.35))),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.positive,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: AppTheme.positive.withValues(alpha: 0.35))),
        ],
      ),
    );
  }
}
