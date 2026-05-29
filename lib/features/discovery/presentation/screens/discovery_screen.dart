import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../data/repositories/discovery_repository.dart';
import '../../data/services/gemini_service.dart';
import '../../domain/entities/tourist_destination.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:ruteando_bolivia/theme/app_theme.dart';
class DiscoveryScreen extends StatefulWidget {
  final VoidCallback onNavigateToMap;

  const DiscoveryScreen({
    super.key,
    required this.onNavigateToMap,
  });

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen>
    with TickerProviderStateMixin {
  final DiscoveryRepository _repository = DiscoveryRepository();
  List<TouristDestination> _destinations = [];
  List<String> _blockedRoutes = [];
  bool _isLoading = true;
  int _selectedIndex = 0;

  LatLng _userLocation = const LatLng(-17.3895, -66.1568);
  String _userLocationName = 'Cochabamba (Por defecto)';
  bool _hasGpsPermission = false;
  bool _isGpsLoading = false;

  // Controladores de animación
  late AnimationController _headerAnimController;
  late AnimationController _cardsAnimController;
  late Animation<double> _headerFadeAnim;
  late Animation<Offset> _headerSlideAnim;
  late Animation<double> _cardsFadeAnim;
  late Animation<Offset> _cardsSlideAnim;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _fetchData();
    _requestGpsLocation();
  }

  void _setupAnimations() {
    _headerAnimController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _cardsAnimController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    _headerFadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _headerAnimController, curve: Curves.easeOut),
    );
    _headerSlideAnim = Tween<Offset>(
      begin: const Offset(0, -0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _headerAnimController, curve: Curves.easeOutCubic));

    _cardsFadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _cardsAnimController, curve: Curves.easeOut),
    );
    _cardsSlideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _cardsAnimController, curve: Curves.easeOutCubic));

    _headerAnimController.forward();
  }

  @override
  void dispose() {
    _headerAnimController.dispose();
    _cardsAnimController.dispose();
    super.dispose();
  }

  Future<void> _requestGpsLocation() async {
    setState(() => _isGpsLoading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() { _isGpsLoading = false; _hasGpsPermission = false; });
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() { _isGpsLoading = false; _hasGpsPermission = false; });
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() { _isGpsLoading = false; _hasGpsPermission = false; });
        return;
      }
      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
        _hasGpsPermission = true;
        _isGpsLoading = false;
        _userLocationName = 'Tu Ubicación Actual (GPS)';
      });
    } catch (e) {
      setState(() { _isGpsLoading = false; _hasGpsPermission = false; });
    }
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final futures = await Future.wait([
        _repository.getTouristDestinations(),
        _repository.getActiveBlockades(),
      ]);
      if (!mounted) return;
      setState(() {
        _destinations = futures[0] as List<TouristDestination>;
        _blockedRoutes = futures[1] as List<String>;
        _isLoading = false;
        _selectedIndex = 0;
      });
      _cardsAnimController.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  bool _isDestinationBlocked(TouristDestination destination) {
    final double distanceInKm = const Distance().as(
      LengthUnit.Kilometer,
      _userLocation,
      LatLng(destination.latitude, destination.longitude),
    );
    if (distanceInKm < 30.0) return false;
    return destination.requiredHighways.any((route) => _blockedRoutes.contains(route));
  }

  bool _isBlockedButLocal(TouristDestination destination) {
    final double distanceInKm = const Distance().as(
      LengthUnit.Kilometer,
      _userLocation,
      LatLng(destination.latitude, destination.longitude),
    );
    final hasHighwayBlock = destination.requiredHighways.any((route) => _blockedRoutes.contains(route));
    return hasHighwayBlock && (distanceInKm < 30.0);
  }

  void _openAiChatSheet(BuildContext context, TouristDestination destination, bool isBlocked) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AiChatBottomSheet(
        destination: destination,
        isBlocked: isBlocked,
        isDark: Theme.of(context).brightness == Brightness.dark,
        userLocationName: _userLocationName,
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
          SafeArea(
            child: RefreshIndicator(
          onRefresh: _fetchData,
          color: theme.colorScheme.primary,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              // ──────── HEADER ────────
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _headerFadeAnim,
                  child: SlideTransition(
                    position: _headerSlideAnim,
                    child: _buildHeader(theme, isDark),
                  ),
                ),
              ),

              // ──────── Estadísticas de viaje rápidas ────────
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _headerFadeAnim,
                  child: _buildQuickStats(theme, isDark),
                ),
              ),

              // ──────── SECCIÓN TÍTULO CARRUSEL ────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 22,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Destinos Recomendados',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_destinations.length} lugares',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ──────── CARRUSEL ────────
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_destinations.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.landscape_outlined,
                            size: 64, color: Colors.grey.withOpacity(0.4)),
                        const SizedBox(height: 16),
                        const Text('No se encontraron destinos.'),
                      ],
                    ),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: FadeTransition(
                    opacity: _cardsFadeAnim,
                    child: SlideTransition(
                      position: _cardsSlideAnim,
                      child: SizedBox(
                        height: 390,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                          itemCount: _destinations.length,
                          itemBuilder: (context, index) {
                            final destination = _destinations[index];
                            final isBlockedForMe = _isDestinationBlocked(destination);
                            final isBlockedButLocal = _isBlockedButLocal(destination);
                            final isSelected = index == _selectedIndex;
                            return GestureDetector(
                              onTap: () => setState(() => _selectedIndex = index),
                              child: Padding(
                                padding: const EdgeInsets.only(right: 18),
                                child: _DestinationCard(
                                  destination: destination,
                                  isBlocked: isBlockedForMe,
                                  isBlockedButLocal: isBlockedButLocal,
                                  isDark: isDark,
                                  isSelected: isSelected,
                                  index: index,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),

                // ──────── SELECTOR INDICADOR ────────
                SliverToBoxAdapter(
                  child: FadeTransition(
                    opacity: _cardsFadeAnim,
                    child: _buildSelectedDestinationInfo(theme, isDark),
                  ),
                ),

                // ──────── BOTONES DE ACCIÓN ────────
                SliverToBoxAdapter(
                  child: FadeTransition(
                    opacity: _cardsFadeAnim,
                    child: _buildActionButtons(theme, isDark),
                  ),
                ),

              ],
            ],
          ),
        ),
      ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
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
                        Expanded(
                          child: Text(
                            'Ruteando Bolivia',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.positive,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Explora destinos turísticos y conoce el estado de las carreteras en tiempo real',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? Colors.white.withOpacity(0.5)
                            : const Color(0xFF64748B),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Badge GPS
              GestureDetector(
                onTap: _requestGpsLocation,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: _hasGpsPermission
                        ? LinearGradient(
                            colors: [
                              theme.colorScheme.primary.withOpacity(0.18),
                              theme.colorScheme.primary.withOpacity(0.08),
                            ],
                          )
                        : null,
                    color: _hasGpsPermission
                        ? null
                        : (isDark ? const Color(0xFF1C2333) : Colors.white),
                    border: Border.all(
                      color: _hasGpsPermission
                          ? theme.colorScheme.primary.withOpacity(0.35)
                          : (isDark
                              ? Colors.white.withOpacity(0.08)
                              : const Color(0xFFE2E8F0)),
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: _hasGpsPermission
                            ? theme.colorScheme.primary.withOpacity(0.12)
                            : Colors.black.withOpacity(0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isGpsLoading)
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      else
                        Icon(
                          _hasGpsPermission
                              ? Icons.my_location_rounded
                              : Icons.location_off_rounded,
                          size: 18,
                          color: _hasGpsPermission
                              ? theme.colorScheme.primary
                              : Colors.grey,
                        ),
                      const SizedBox(height: 4),
                      Text(
                        _hasGpsPermission
                            ? 'GPS\nActivo'
                            : (_isGpsLoading ? 'Buscando' : 'Sin GPS'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          color: _hasGpsPermission
                              ? theme.colorScheme.primary
                              : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats(ThemeData theme, bool isDark) {
    final blockedCount = _destinations
        .where((d) => _isDestinationBlocked(d))
        .length;
    final clearCount = _destinations.length - blockedCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Row(
        children: [
          _StatChip(
            label: 'Destinos',
            value: _destinations.isEmpty ? '—' : '${_destinations.length}',
            icon: Icons.place_rounded,
            color: theme.colorScheme.primary,
            isDark: isDark,
          ),
          const SizedBox(width: 10),
          _StatChip(
            label: 'Rutas Libres',
            value: _destinations.isEmpty ? '—' : '$clearCount',
            icon: Icons.check_circle_outline_rounded,
            color: const Color(0xFF22C55E),
            isDark: isDark,
          ),
          const SizedBox(width: 10),
          _StatChip(
            label: 'Bloqueadas',
            value: _destinations.isEmpty ? '—' : '$blockedCount',
            icon: Icons.block_rounded,
            color: const Color(0xFFEF4444),
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedDestinationInfo(ThemeData theme, bool isDark) {
    if (_destinations.isEmpty) return const SizedBox.shrink();
    final dest = _destinations[_selectedIndex];
    final isBlocked = _isDestinationBlocked(dest);
    final isLocal = _isBlockedButLocal(dest);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Container(
          key: ValueKey(_selectedIndex),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161B27) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.06)
                  : const Color(0xFFE2E8F0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isBlocked
                      ? const Color(0xFFEF4444).withOpacity(0.12)
                      : isLocal
                          ? const Color(0xFF22C55E).withOpacity(0.12)
                          : theme.colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isBlocked
                      ? Icons.warning_amber_rounded
                      : isLocal
                          ? Icons.verified_rounded
                          : Icons.explore_rounded,
                  color: isBlocked
                      ? const Color(0xFFEF4444)
                      : isLocal
                          ? const Color(0xFF22C55E)
                          : theme.colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dest.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          size: 12,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          dest.department,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isBlocked
                                ? const Color(0xFFEF4444).withOpacity(0.1)
                                : const Color(0xFF22C55E).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            isBlocked ? 'Ruta Bloqueada' : 'Ruta Libre',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isBlocked
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFF22C55E),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        children: [
          Expanded(
            child: _ActionButton(
              onPressed: _destinations.isEmpty
                  ? null
                  : () {
                      final activeDest = _destinations[_selectedIndex];
                      final isBlocked = _isDestinationBlocked(activeDest);
                      _openAiChatSheet(context, activeDest, isBlocked);
                    },
              backgroundColor: isDark
                  ? const Color(0xFF1E293B)
                  : const Color(0xFF0F172A),
              icon: Icons.assistant_rounded,
              iconColor: Colors.cyanAccent,
              label: 'PREGUNTAR IA',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ActionButton(
              onPressed: widget.onNavigateToMap,
              backgroundColor: theme.colorScheme.primary,
              icon: Icons.map_rounded,
              iconColor: Colors.white,
              label: 'VER MAPA',
              shadowColor: theme.colorScheme.primary.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════
//  WIDGETS DE APOYO
// ══════════════════════════════════════════════════

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isDark;

  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161B27) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.06)
                : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: color,
                height: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? Colors.white.withOpacity(0.4)
                    : Colors.black.withOpacity(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color? shadowColor;

  const _ActionButton({
    required this.onPressed,
    required this.backgroundColor,
    required this.icon,
    required this.iconColor,
    required this.label,
    this.shadowColor,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressController.forward(),
      onTapUp: (_) {
        _pressController.reverse();
        widget.onPressed?.call();
      },
      onTapCancel: () => _pressController.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: widget.shadowColor ?? Colors.black.withOpacity(0.25),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 18, color: widget.iconColor),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
//  TARJETA DE DESTINO
// ══════════════════════════════════════════════════

class _DestinationCard extends StatelessWidget {
  final TouristDestination destination;
  final bool isBlocked;
  final bool isBlockedButLocal;
  final bool isDark;
  final bool isSelected;
  final int index;

  const _DestinationCard({
    required this.destination,
    required this.isBlocked,
    required this.isBlockedButLocal,
    required this.isDark,
    required this.isSelected,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: 260,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: isDark ? const Color(0xFF1C2333) : Colors.white,
        border: Border.all(
          color: isSelected
              ? theme.colorScheme.primary
              : Colors.transparent,
          width: isSelected ? 2.5 : 0,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? theme.colorScheme.primary.withOpacity(0.28)
                : Colors.black.withOpacity(isDark ? 0.35 : 0.08),
            blurRadius: isSelected ? 24 : 14,
            spreadRadius: isSelected ? 1 : 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Imagen o placeholder
            if (destination.imageUrl != null && destination.imageUrl!.isNotEmpty)
              Image.network(
                destination.imageUrl!,
                fit: BoxFit.cover,
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return _buildPlaceholder(theme);
                },
                errorBuilder: (_, __, ___) => _buildPlaceholder(theme),
              )
            else
              _buildPlaceholder(theme),

            // Gradiente negro abajo para texto
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.92),
                  ],
                  stops: const [0.35, 1.0],
                ),
              ),
            ),

            // Gradiente superior sutil para badges
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.25),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.4],
                ),
              ),
            ),

            // Contenido de texto
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nivel de dificultad
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _difficultyColor(destination.difficultyLevel)
                          .withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _difficultyColor(destination.difficultyLevel)
                            .withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      destination.difficultyLevel,
                      style: TextStyle(
                        color: _difficultyColor(destination.difficultyLevel),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),

                  // Departamento
                  Row(
                    children: [
                      Icon(Icons.location_on_rounded,
                          size: 13, color: Colors.white70),
                      const SizedBox(width: 3),
                      Text(
                        destination.department,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),

                  // Nombre del destino
                  Text(
                    destination.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      height: 1.2,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Descripción
                  Text(
                    destination.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            // Badge bloqueada
            if (isBlocked)
              Positioned(
                top: 14,
                right: 14,
                child: _Badge(
                  label: 'Ruta Bloqueada',
                  icon: Icons.warning_rounded,
                  color: const Color(0xFFEF4444),
                ),
              ),

            // Badge acceso local libre
            if (isBlockedButLocal)
              Positioned(
                top: 14,
                right: 14,
                child: _Badge(
                  label: 'Acceso Local',
                  icon: Icons.verified_rounded,
                  color: const Color(0xFF22C55E),
                ),
              ),

            // Indicador seleccionado
            if (isSelected)
              Positioned(
                top: 14,
                left: 14,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    color: const Color(0xFF0D1117),
                    size: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _difficultyColor(String level) {
    switch (level) {
      case 'Fácil':
        return const Color(0xFF22C55E);
      case 'Moderado':
        return const Color(0xFFF59E0B);
      case 'Difícil':
        return const Color(0xFFEF4444);
      default:
        return Colors.grey;
    }
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary.withOpacity(0.12),
            theme.colorScheme.primary.withOpacity(0.04),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Patrón de fondo decorativo
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPatternPainter(
                color: theme.colorScheme.primary.withOpacity(0.06),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.landscape_rounded,
                  size: 52,
                  color: theme.colorScheme.primary.withOpacity(0.3),
                ),
                const SizedBox(height: 10),
                Text(
                  'Sin imagen',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.primary.withOpacity(0.4),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _Badge({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.85),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 12),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridPatternPainter extends CustomPainter {
  final Color color;
  _GridPatternPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const spacing = 28.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════
//  CHAT IA
// ══════════════════════════════════════════════════

class _AiChatBottomSheet extends StatefulWidget {
  final TouristDestination destination;
  final bool isBlocked;
  final bool isDark;
  final String userLocationName;

  const _AiChatBottomSheet({
    required this.destination,
    required this.isBlocked,
    required this.isDark,
    required this.userLocationName,
  });

  @override
  State<_AiChatBottomSheet> createState() => _AiChatBottomSheetState();
}

class _AiChatBottomSheetState extends State<_AiChatBottomSheet> {
  final List<Map<String, String>> _messages = [];
  final GeminiService _gemini = GeminiService();
  final TextEditingController _textController = TextEditingController();
  bool _isTyping = false;
  ChatSession? _chatSession;

  @override
  void initState() {
    super.initState();
    _messages.add({
      'role': 'ai',
      'text':
          '¡Hola viajero! Soy Ruteando AI 🤖. Detecto que tu ubicación es: ${widget.userLocationName}.\n\nTengo acceso en tiempo real a los datos de transitabilidad de la ABC. Pregúntame lo que quieras sobre la ruta hacia ${widget.destination.name}.',
    });
    _initChatSession();
  }

  Future<void> _initChatSession() async {
    try {
      _chatSession = await _gemini.createChatSession(
        destinationName: widget.destination.name,
        destinationDepartment: widget.destination.department,
        destinationLat: widget.destination.latitude,
        destinationLng: widget.destination.longitude,
        requiredHighways: widget.destination.requiredHighways,
        isBlocked: widget.isBlocked,
        userLocationName: widget.userLocationName,
      );
    } catch (e) {
      debugPrint('Error al inicializar sesión de IA: $e');
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _isTyping = true;
      _textController.clear();
    });

    try {
      if (_chatSession == null) {
        await _initChatSession();
      }
      
      if (_chatSession == null) {
        throw Exception("No se pudo iniciar la sesión con la IA.");
      }

      final response = await _chatSession!.sendMessage(Content.text(text));
      final aiResponse = response.text ?? 'No pude generar una respuesta.';

      if (!mounted) return;
      setState(() {
        _messages.add({'role': 'ai', 'text': aiResponse});
        _isTyping = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'role': 'ai',
          'text': '❌ Error al consultar la IA. Verifica tu conexión a internet e intenta de nuevo.'
        });
        _isTyping = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final suggestions = [
      '¿Cómo está el camino hoy?',
      '¿Qué clima se reporta?',
      '¿Hay rutas alternativas?',
    ];

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1117) : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 14),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.35),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.cyan.withOpacity(0.2),
                        Colors.blue.withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.assistant_rounded,
                      color: Colors.cyan, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ruteando AI',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'Consulta sobre ${widget.destination.name}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: isDark ? Colors.white54 : Colors.black45),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Divider(
              height: 1,
              color: isDark
                  ? Colors.white.withOpacity(0.07)
                  : Colors.black.withOpacity(0.07)),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isAi = message['role'] == 'ai';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisAlignment:
                        isAi ? MainAxisAlignment.start : MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isAi) ...[
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.cyan.withOpacity(0.12),
                          child: const Icon(Icons.assistant_rounded,
                              size: 14, color: Colors.cyan),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isAi
                                ? (isDark
                                    ? Colors.white.withOpacity(0.05)
                                    : Colors.grey.withOpacity(0.09))
                                : theme.colorScheme.primary,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(isAi ? 4 : 16),
                              bottomRight: Radius.circular(isAi ? 16 : 4),
                            ),
                          ),
                          child: Text(
                            message['text'] ?? '',
                            style: TextStyle(
                              color: isAi
                                  ? (isDark ? Colors.white : Colors.black87)
                                  : Colors.white,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (_isTyping)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.cyan),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Ruteando AI está analizando datos de la ABC...',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontStyle: FontStyle.italic, color: Colors.grey),
                  ),
                ],
              ),
            ),
          if (!_isTyping && _messages.length <= 1)
            SizedBox(
              height: 52,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                itemCount: suggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = suggestions[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      onPressed: () => _sendMessage(suggestion),
                      backgroundColor:
                          isDark ? const Color(0xFF1C2333) : const Color(0xFFF1F5F9),
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      label: Text(
                        suggestion,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          // ──── Campo de texto para escribir ────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? Colors.white.withOpacity(0.06)
                      : Colors.black.withOpacity(0.06),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    enabled: !_isTyping,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Escribe tu pregunta...',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.white30 : Colors.black38,
                        fontSize: 14,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? Colors.white.withOpacity(0.05)
                          : Colors.grey.withOpacity(0.08),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (text) {
                      if (text.trim().isNotEmpty && !_isTyping) {
                        _sendMessage(text);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.cyan.shade400,
                        Colors.blue.shade600,
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
                    onPressed: _isTyping
                        ? null
                        : () {
                            if (_textController.text.trim().isNotEmpty) {
                              _sendMessage(_textController.text);
                            }
                          },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

