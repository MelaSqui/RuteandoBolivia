import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ruteando_bolivia/theme/app_theme.dart';

class AlertCard extends StatefulWidget {
  final Map<String, dynamic> event;
  const AlertCard({super.key, required this.event});

  @override
  State<AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<AlertCard> {
  int _sigueCount = 0;
  int _despejadoCount = 0;
  bool? _userVote; // null=sin voto, true=sigue, false=despejado

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
                _Badge(color: style.color, icon: style.icon, label: style.label),
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
                    icon: Icons.thumb_up_rounded,
                    label: 'Sigue ahí',
                    count: _sigueCount,
                    color: AppTheme.positive,
                    isActive: _userVote == true,
                    isDark: isDark,
                    onTap: () => setState(() {
                      if (_userVote == true) {
                        _sigueCount--;
                        _userVote = null;
                      } else {
                        if (_userVote == false) _despejadoCount--;
                        _sigueCount++;
                        _userVote = true;
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _VoteButton(
                    icon: Icons.thumb_down_rounded,
                    label: 'Despejado',
                    count: _despejadoCount,
                    color: AppTheme.danger,
                    isActive: _userVote == false,
                    isDark: isDark,
                    onTap: () => setState(() {
                      if (_userVote == false) {
                        _despejadoCount--;
                        _userVote = null;
                      } else {
                        if (_userVote == true) _sigueCount--;
                        _despejadoCount++;
                        _userVote = false;
                      }
                    }),
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isActive
              ? color.withValues(alpha: 0.15)
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? color.withValues(alpha: 0.4) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: isActive ? color : idle),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isActive ? color : idle,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
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
