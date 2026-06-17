import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ruteando_bolivia/theme/app_theme.dart';
import 'package:ruteando_bolivia/features/routes/utils/route_utils.dart';

class AlertCard extends StatefulWidget {
  final Map<String, dynamic> event;
  final LatLng? userLocation;
  const AlertCard({super.key, required this.event, this.userLocation});

  @override
  State<AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<AlertCard> {
  int _sigueCount = 0;
  int _despejadoCount = 0;
  bool? _userVote; // null=sin voto, true=sigue, false=despejado
  bool _isValidating = false;

  @override
  void initState() {
    super.initState();
    _loadVoteState();
  }

  Future<void> _loadVoteState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedVote = prefs.getString('vote_road_event_${widget.event['id']}');

    final rawData = widget.event['raw_data'];
    Map<String, dynamic>? raw;
    if (rawData is Map<String, dynamic>) {
      raw = rawData;
    } else if (rawData is String) {
      try {
        raw = jsonDecode(rawData) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _sigueCount = int.tryParse(raw?['votos_sigue']?.toString() ?? '0') ?? 0;
        _despejadoCount = int.tryParse(raw?['votos_despejado']?.toString() ?? '0') ?? 0;
        if (savedVote == 'sigue') {
          _userVote = true;
        } else if (savedVote == 'despejado') {
          _userVote = false;
        } else {
          _userVote = null;
        }
      });
    }
  }

  Future<bool> _isNearIncident() async {
    final double? lat = double.tryParse(widget.event['latitud_inicio']?.toString() ?? '');
    final double? lng = double.tryParse(widget.event['longitud_inicio']?.toString() ?? '');

    if (lat == null || lng == null) {
      // Si el incidente no tiene coordenadas, se asume transitable/permitido votar
      return true;
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnackBar('Por favor, activa el servicio de ubicación (GPS).');
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnackBar('Permiso de ubicación denegado.');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showSnackBar('Permisos de GPS denegados permanentemente.');
        return false;
      }

      // Obtener ubicación rápida
      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );

      final userCoords = LatLng(position.latitude, position.longitude);
      final incidentCoords = LatLng(lat, lng);

      final double distance = RouteUtils.calculateDistance(userCoords, incidentCoords);

      // Límite de 5 km a la redonda
      if (distance > 5.0) {
        _showSnackBar('No te encuentras en esta zona. Según tu ubicación (estás a ${distance.toStringAsFixed(1)} km), no puedes votar sobre el estado de este reporte.');
        return false;
      }

      return true;
    } catch (e) {
      _showSnackBar('No se pudo verificar tu ubicación actual. Por favor, asegúrate de activar tu GPS y otorgar permisos de ubicación.');
      return false;
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _submitVote(bool isSigue) async {
    if (_isValidating) return;

    setState(() {
      _isValidating = true;
    });

    final bool near = await _isNearIncident();
    if (!near) {
      if (mounted) {
        setState(() {
          _isValidating = false;
        });
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final originalUserVote = _userVote;
    int newSigue = _sigueCount;
    int newDespejado = _despejadoCount;
    String? newPrefsVote;

    if (isSigue) {
      if (originalUserVote == true) {
        newSigue--;
        newPrefsVote = null;
      } else {
        if (originalUserVote == false) newDespejado--;
        newSigue++;
        newPrefsVote = 'sigue';
      }
    } else {
      if (originalUserVote == false) {
        newDespejado--;
        newPrefsVote = null;
      } else {
        if (originalUserVote == true) newSigue--;
        newDespejado++;
        newPrefsVote = 'despejado';
      }
    }

    // Actualizar UI local inmediatamente para feedback rápido
    if (mounted) {
      setState(() {
        _sigueCount = newSigue;
        _despejadoCount = newDespejado;
        _userVote = newPrefsVote == 'sigue' ? true : (newPrefsVote == 'despejado' ? false : null);
      });
    }

    try {
      final client = Supabase.instance.client;

      // Obtener el raw_data actual de la base de datos para no sobreescribir otros campos
      final response = await client
          .from('road_events')
          .select('raw_data')
          .eq('id', widget.event['id'])
          .single();

      final rawData = response['raw_data'];
      Map<String, dynamic> raw = {};
      if (rawData is Map<String, dynamic>) {
        raw = Map<String, dynamic>.from(rawData);
      } else if (rawData is String) {
        try {
          raw = Map<String, dynamic>.from(jsonDecode(rawData));
        } catch (_) {}
      }

      raw['votos_sigue'] = newSigue;
      raw['votos_despejado'] = newDespejado;

      await client
          .from('road_events')
          .update({'raw_data': raw})
          .eq('id', widget.event['id']);

      if (newPrefsVote != null) {
        await prefs.setString('vote_road_event_${widget.event['id']}', newPrefsVote);
      } else {
        await prefs.remove('vote_road_event_${widget.event['id']}');
      }
    } catch (e) {
      // Revertir estado si falla la red
      _loadVoteState();
      _showSnackBar('Error de red al guardar el voto: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isValidating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final style = _eventStyle(widget.event['evento']);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: style.color, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Badge(color: style.color, icon: style.icon, label: style.label),
                    if (widget.userLocation != null) ...[
                      const SizedBox(width: 8),
                      _distanceBadge(widget.userLocation!),
                    ],
                  ],
                ),
                Text(
                  _timeAgo(widget.event['hora_reporte'] ?? widget.event['updated_at']),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _title(widget.event),
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            Text(
              _description(widget.event),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                height: 1.45,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _VoteButton(
                    icon: Icons.warning_rounded,
                    label: 'Sigue ahí',
                    count: _sigueCount,
                    color: AppTheme.danger,
                    isActive: _userVote == true,
                    isDark: isDark,
                    onTap: () => _submitVote(true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _VoteButton(
                    icon: Icons.check_circle_rounded,
                    label: 'Despejado',
                    count: _despejadoCount,
                    color: AppTheme.positive,
                    isActive: _userVote == false,
                    isDark: isDark,
                    onTap: () => _submitVote(false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  ({Color color, IconData icon, String label}) _eventStyle(dynamic raw) {
    final e = (raw ?? '').toString().toUpperCase();
    if (e.contains('BLOQUEO') || e.contains('CONFLICTO') || e.contains('SOCIAL')) {
      return (color: AppTheme.danger, icon: Icons.block_rounded, label: 'BLOQUEO SOCIAL');
    }
    if (e.contains('DERRUMBE') || e.contains('COLAPSO') || e.contains('CERRADO')) {
      return (color: AppTheme.warning, icon: Icons.warning_amber_rounded, label: 'DERRUMBE');
    }
    if (e.contains('NEBLINA') || e.contains('LLUVIA') || e.contains('NEVADA') || e.contains('CLIMA')) {
      return (color: AppTheme.climate, icon: Icons.cloud_rounded, label: 'NEBLINA DENSA');
    }
    if (e.contains('DESVIO') || e.contains('DESVÍO')) {
      return (color: AppTheme.caution, icon: Icons.alt_route_rounded, label: 'DESVÍO');
    }
    if (e.contains('RESTRICCI') || e.contains('PRECAUC')) {
      return (color: AppTheme.caution, icon: Icons.do_not_disturb_on_rounded, label: 'RESTRICCIÓN');
    }
    if (e.contains('TRABAJO') || e.contains('CONSERV') || e.contains('CONSTRUC')) {
      return (color: AppTheme.caution, icon: Icons.construction_rounded, label: 'EN CONSTRUCCIÓN');
    }
    return (color: AppTheme.warning, icon: Icons.info_rounded, label: 'ALERTA VIAL');
  }

  String _title(Map<String, dynamic> ev) {
    final rawData = ev['raw_data'];
    Map<String, dynamic>? raw;
    if (rawData is Map<String, dynamic>) {
      raw = rawData;
    } else if (rawData is String) {
      try {
        raw = jsonDecode(rawData) as Map<String, dynamic>;
      } catch (_) {}
    }

    final String rutaRaw = (ev['ruta'] ?? '').toString().trim();
    String rutaText = '';
    if (rutaRaw.isNotEmpty) {
      try {
        final parsedRuta = int.parse(rutaRaw);
        rutaText = 'Ruta $parsedRuta';
      } catch (_) {
        rutaText = 'Ruta $rutaRaw';
      }
    }

    if (raw != null) {
      final inicio = (raw['inicio_seccion'] ?? '').toString().trim();
      final fin = (raw['fin_seccion'] ?? '').toString().trim();
      final sector = (raw['descr_sector'] ?? '').toString().trim();

      String details = '';
      if (inicio.isNotEmpty && fin.isNotEmpty) {
        details = '$inicio - $fin';
      } else if (inicio.isNotEmpty) {
        details = inicio;
      } else if (fin.isNotEmpty) {
        details = fin;
      }

      if (sector.isNotEmpty) {
        if (details.isNotEmpty) {
          details = '$details ($sector)';
        } else {
          details = sector;
        }
      }

      if (details.isNotEmpty) {
        return rutaText.isNotEmpty ? '$rutaText: $details' : details;
      }
    }

    final seccion = (ev['seccion'] ?? '').toString().trim();
    if (rutaText.isEmpty && seccion.isEmpty) return 'Alerta vial';
    if (seccion.isEmpty) return rutaText;
    if (rutaText.isEmpty) return 'Sección $seccion';
    return '$rutaText, Sección $seccion';
  }

  String _description(Map<String, dynamic> ev) {
    final parts = <String>[];
    for (final key in ['evento', 'restriccion_vehicular', 'trabajos_conservacion', 'transitable_con_desvio']) {
      final val = (ev[key] ?? '').toString().trim();
      if (val.isNotEmpty && val.toUpperCase() != 'NO') parts.add(val);
    }
    return parts.join('. ');
  }

  String _timeAgo(dynamic raw) {
    if (raw == null) return '';
    try {
      final date = DateTime.parse(raw.toString()).toLocal();
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 1) return 'Ahora mismo';
      if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
      if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
      if (diff.inDays == 1) return 'Ayer';
      return 'Hace ${diff.inDays} días';
    } catch (_) {
      return '';
    }
  }

  Widget _distanceBadge(LatLng userLoc) {
    final double? lat = double.tryParse(widget.event['latitud_inicio']?.toString() ?? '');
    final double? lng = double.tryParse(widget.event['longitud_inicio']?.toString() ?? '');
    if (lat == null || lng == null) return const SizedBox.shrink();

    final double distance = RouteUtils.calculateDistance(userLoc, LatLng(lat, lng));
    final String text = distance < 1.0
        ? '${(distance * 1000).toStringAsFixed(0)} m'
        : '${distance.toStringAsFixed(1)} km';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.positive.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.navigation_rounded, color: AppTheme.positive, size: 10),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: AppTheme.positive,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  const _Badge({required this.color, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _VoteButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const _VoteButton({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final idle = isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.4);
    final foregroundColor = isActive ? Colors.white : idle;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isActive
              ? color
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? color.withValues(alpha: 0.2) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: foregroundColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: foregroundColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive ? Colors.white.withValues(alpha: 0.25) : color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isActive ? Colors.white : color,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
