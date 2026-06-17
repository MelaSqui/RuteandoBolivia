import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../theme/app_theme.dart';
import '../../../../services/theme_service.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  final bool isActive;
  const ProfileScreen({super.key, this.isActive = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  Map<String, dynamic>? _profile;
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    _loadProfile();
  }

  @override
  void didUpdateWidget(ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _loadProfile();
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      // Use maybeSingle() which returns the record directly (or null) in current supabase client
      final Object? result = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (result == null) {
        // no profile found
      } else if (result is Map<String, dynamic>) {
        _profile = Map<String, dynamic>.from(result);
      } else if (result is List && result.isNotEmpty) {
        final first = result.first;
        if (first is Map<String, dynamic>) {
          _profile = Map<String, dynamic>.from(first);
        }
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: AppTheme.danger),
            SizedBox(width: 12),
            Text('Cerrar sesión'),
          ],
        ),
        content: const Text(
          '¿Estás seguro de que deseas cerrar tu sesión?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await Supabase.instance.client.auth.signOut();
    }
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : 'V';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = Supabase.instance.client.auth.currentUser;

    final dynamic nameSource =
        _profile?['full_name'] ?? user?.userMetadata?['display_name'];
    final String displayName = nameSource?.toString() ?? 'Viajero';

    final dynamic bioSource = _profile?['bio'];
    final String bio = bioSource?.toString() ?? 'Explorador de Bolivia 🇧🇴';

    final dynamic avatarSource = _profile?['avatar_url'];
    final String? avatarUrl =
        avatarSource == null ? null : avatarSource.toString();

    final routesCount = _profile?['routes_count']?.toString() ?? '0';
    final reportsCount = _profile?['reports_count']?.toString() ?? '0';

    return Scaffold(
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                color: theme.colorScheme.primary,
                strokeWidth: 2.5,
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadProfile,
              color: theme.colorScheme.primary,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                // ── Hero Header ──
                SliverToBoxAdapter(
                  child: _buildHeroHeader(
                    theme,
                    isDark,
                    displayName,
                    bio,
                    user?.email ?? '',
                    avatarUrl,
                  ),
                ),

                // ── Stats Row ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            icon: Icons.route_rounded,
                            label: 'Rutas',
                            value: routesCount,
                            gradient: const [
                              Color(0xFF22C55E),
                              Color(0xFF16A34A),
                            ],
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.flag_rounded,
                            label: 'Reportes',
                            value: reportsCount,
                            gradient: const [
                              Color(0xFFF97316),
                              Color(0xFFEA580C),
                            ],
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.star_rounded,
                            label: 'Nivel',
                            value: _computeLevel(
                              int.tryParse(routesCount) ?? 0,
                              int.tryParse(reportsCount) ?? 0,
                            ),
                            gradient: const [
                              Color(0xFF38BDF8),
                              Color(0xFF0EA5E9),
                            ],
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Menu Sections ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionHeader(title: 'Mi Cuenta', theme: theme),
                        const SizedBox(height: 8),
                        _MenuCard(
                          isDark: isDark,
                          theme: theme,
                          children: [
                            _MenuItem(
                              icon: Icons.edit_rounded,
                              iconColor: AppTheme.positive,
                              title: 'Editar perfil',
                              subtitle: 'Nombre, foto y biografía',
                              onTap: () async {
                                final result = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        EditProfileScreen(profile: _profile),
                                  ),
                                );
                                if (result == true && mounted) {
                                  _loadProfile();
                                }
                              },
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),
                        _SectionHeader(title: 'Preferencias', theme: theme),
                        const SizedBox(height: 8),
                        _MenuCard(
                          isDark: isDark,
                          theme: theme,
                          children: [
                            _ThemeMenuItem(isDark: isDark, theme: theme),
                          ],
                        ),

                        const SizedBox(height: 20),
                        _SectionHeader(title: 'Información', theme: theme),
                        const SizedBox(height: 8),
                        _MenuCard(
                          isDark: isDark,
                          theme: theme,
                          children: [
                            _MenuItem(
                              icon: Icons.info_outline_rounded,
                              iconColor: AppTheme.climate,
                              title: 'Acerca de',
                              subtitle: 'Ruteando Bolivia v1.0',
                              onTap: () {},
                            ),
                            _MenuDivider(isDark: isDark),
                            _MenuItem(
                              icon: Icons.shield_outlined,
                              iconColor: const Color(0xFF8B5CF6),
                              title: 'Privacidad',
                              subtitle: 'Políticas y términos',
                              onTap: () {},
                            ),
                          ],
                        ),

                        const SizedBox(height: 28),

                        // ── Sign Out ──
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton.icon(
                            onPressed: () => _signOut(context),
                            icon: const Icon(Icons.logout_rounded, size: 20),
                            label: const Text(
                              'Cerrar sesión',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.danger,
                              side: BorderSide(
                                color: AppTheme.danger.withOpacity(0.4),
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildHeroHeader(
    ThemeData theme,
    bool isDark,
    String displayName,
    String bio,
    String email,
    String? avatarUrl,
  ) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        bottom: 28,
        left: 24,
        right: 24,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.6, 1.0],
          colors: isDark
              ? [
                  const Color(0xFF0D1B2A),
                  const Color(0xFF112240),
                  theme.scaffoldBackgroundColor,
                ]
              : [
                  const Color(0xFFE0F2FE),
                  const Color(0xFFF0FDF4),
                  theme.scaffoldBackgroundColor,
                ],
        ),
      ),
      child: Column(
        children: [
          // Avatar with glow
          AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.positive
                          .withOpacity(_glowAnimation.value * 0.35),
                      blurRadius: 28,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: child,
              );
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.positive,
                    AppTheme.climate,
                  ],
                ),
              ),
              child: CircleAvatar(
                radius: 48,
                backgroundColor:
                    isDark ? AppTheme.darkCard : AppTheme.lightCard,
                backgroundImage:
                    avatarUrl != null && avatarUrl.isNotEmpty
                        ? NetworkImage(avatarUrl)
                        : null,
                child: avatarUrl == null || avatarUrl.isEmpty
                    ? Text(
                        _getInitials(displayName),
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.positive,
                        ),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            displayName,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 24,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            email,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.55),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.positive.withOpacity(isDark ? 0.15 : 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              bio,
              style: TextStyle(
                color: AppTheme.positive,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _computeLevel(int routes, int reports) {
    final total = routes + reports;
    if (total >= 50) return 'Pro';
    if (total >= 20) return 'Experto';
    if (total >= 5) return 'Activo';
    return 'Nuevo';
  }
}

// ── Stat Card ──
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final List<Color> gradient;
  final bool isDark;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.gradient,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: gradient[0].withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.55),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section Header ──
class _SectionHeader extends StatelessWidget {
  final String title;
  final ThemeData theme;

  const _SectionHeader({required this.title, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurface.withOpacity(0.45),
        fontWeight: FontWeight.w700,
        fontSize: 12,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ── Menu Card ──
class _MenuCard extends StatelessWidget {
  final bool isDark;
  final ThemeData theme;
  final List<Widget> children;

  const _MenuCard({
    required this.isDark,
    required this.theme,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          width: 1,
        ),
      ),
      child: Column(children: children),
    );
  }
}

// ── Menu Item ──
class _MenuItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurface.withOpacity(0.3),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Menu Divider ──
class _MenuDivider extends StatelessWidget {
  final bool isDark;

  const _MenuDivider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Divider(
        height: 1,
        thickness: 1,
        color: isDark
            ? AppTheme.darkBorder.withOpacity(0.5)
            : AppTheme.lightBorder,
      ),
    );
  }
}

// ── Theme Menu Item ──
class _ThemeMenuItem extends StatelessWidget {
  final bool isDark;
  final ThemeData theme;

  const _ThemeMenuItem({required this.isDark, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.palette_rounded,
              color: Color(0xFF8B5CF6),
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Apariencia',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Modo claro, oscuro o sistema',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeService,
            builder: (context, currentTheme, _) {
              return Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.06)
                      : Colors.black.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ThemeButton(
                      icon: Icons.light_mode_rounded,
                      isSelected: currentTheme == ThemeMode.light,
                      onTap: () =>
                          themeService.setThemeMode(ThemeMode.light),
                    ),
                    _ThemeButton(
                      icon: Icons.dark_mode_rounded,
                      isSelected: currentTheme == ThemeMode.dark,
                      onTap: () =>
                          themeService.setThemeMode(ThemeMode.dark),
                    ),
                    _ThemeButton(
                      icon: Icons.settings_brightness_rounded,
                      isSelected: currentTheme == ThemeMode.system,
                      onTap: () =>
                          themeService.setThemeMode(ThemeMode.system),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Theme Toggle Button ──
class _ThemeButton extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeButton({
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.positive.withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 18,
          color: isSelected
              ? AppTheme.positive
              : Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withOpacity(0.35),
        ),
      ),
    );
  }
}
