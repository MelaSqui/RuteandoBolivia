import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../theme/app_theme.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic>? profile;

  const EditProfileScreen({super.key, this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen>
    with SingleTickerProviderStateMixin {
  late TextEditingController _fullNameController;
  late TextEditingController _bioController;
  bool _saving = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  XFile? _selectedImage;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(
      text: widget.profile?['full_name'] as String? ?? '',
    );
    _bioController = TextEditingController(
      text: widget.profile?['bio'] as String? ?? '',
    );
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    _animController.forward();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _bioController.dispose();
    _animController.dispose();
    super.dispose();
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : 'V';
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = image;
      });
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text('Error: Usuario no autenticado'),
              ],
            ),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return;
    }

    try {
      String? newAvatarUrl;

      // Si el usuario seleccionó una imagen, la subimos al storage primero
      if (_selectedImage != null) {
        final bytes = await _selectedImage!.readAsBytes();
        final fileExt = _selectedImage!.name.split('.').last.isNotEmpty
            ? _selectedImage!.name.split('.').last
            : 'png';
        final fileName = '${user.id}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

        // Subir a Supabase Storage (asegúrate de tener un bucket llamado 'avatars' público)
        await Supabase.instance.client.storage
            .from('avatars')
            .uploadBinary(
              fileName,
              bytes,
              fileOptions: FileOptions(
                  contentType: _selectedImage!.mimeType ?? 'image/$fileExt'),
            );

        newAvatarUrl = Supabase.instance.client.storage
            .from('avatars')
            .getPublicUrl(fileName);
      }

      final updateData = {
        'full_name': _fullNameController.text,
        'bio': _bioController.text,
      };

      if (newAvatarUrl != null) {
        updateData['avatar_url'] = newAvatarUrl;
      }

      await Supabase.instance.client
          .from('profiles')
          .update(updateData)
          .eq('id', user.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text('Perfil actualizado exitosamente'),
              ],
            ),
            backgroundColor: AppTheme.positive,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        Navigator.of(context).pop(true); // Return true to indicate changes
      }
    } catch (e) {
      debugPrint('Error saving profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('Error al guardar: $e')),
              ],
            ),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }

    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = Supabase.instance.client.auth.currentUser;
    final currentName = _fullNameController.text.isNotEmpty
        ? _fullNameController.text
        : (user?.userMetadata?['display_name']?.toString() ?? 'Viajero');

    final dynamic avatarSource = widget.profile?['avatar_url'];
    final String? avatarUrl =
        avatarSource == null ? null : avatarSource.toString();

    ImageProvider? imageProvider;
    if (_selectedImage != null) {
      imageProvider = NetworkImage(_selectedImage!.path);
    } else if (avatarUrl != null && avatarUrl.isNotEmpty) {
      imageProvider = NetworkImage(avatarUrl);
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.black.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.arrow_back_rounded,
              color: theme.colorScheme.onSurface,
              size: 22,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Editar Perfil',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _saving ? null : _saveProfile,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.positive,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.positive,
                      ),
                    )
                  : const Text(
                      'Guardar',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── Avatar Section ──
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _pickImage,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
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
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.positive.withOpacity(0.25),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor:
                              isDark ? AppTheme.darkCard : AppTheme.lightCard,
                          backgroundImage: imageProvider,
                          child: imageProvider == null
                              ? Text(
                                  _getInitials(currentName),
                                  style: const TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.positive,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.positive,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                isDark ? AppTheme.darkCard : AppTheme.lightCard,
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.positive.withOpacity(0.3),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Toca para cambiar foto',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.4),
                    fontSize: 12,
                  ),
                ),

                const SizedBox(height: 32),

                // ── Form Fields ──
                _FormSection(
                  isDark: isDark,
                  theme: theme,
                  children: [
                    _FormField(
                      controller: _fullNameController,
                      label: 'Nombre Completo',
                      hint: 'Tu nombre completo',
                      icon: Icons.person_rounded,
                      iconColor: AppTheme.positive,
                      isDark: isDark,
                      theme: theme,
                    ),
                    _FormFieldDivider(isDark: isDark),
                    _FormField(
                      controller: _bioController,
                      label: 'Biografía',
                      hint: 'Cuéntanos sobre ti...',
                      icon: Icons.edit_note_rounded,
                      iconColor: AppTheme.climate,
                      isDark: isDark,
                      theme: theme,
                      maxLines: 3,
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // ── Info Card ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.climate.withOpacity(isDark ? 0.08 : 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color:
                          AppTheme.climate.withOpacity(isDark ? 0.15 : 0.12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: AppTheme.climate,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Tu perfil es visible para otros usuarios de Ruteando Bolivia.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.climate,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Form Section Container ──
class _FormSection extends StatelessWidget {
  final bool isDark;
  final ThemeData theme;
  final List<Widget> children;

  const _FormSection({
    required this.isDark,
    required this.theme,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          width: 1,
        ),
      ),
      child: Column(children: children),
    );
  }
}

// ── Form Field ──
class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final Color iconColor;
  final bool isDark;
  final ThemeData theme;
  final int maxLines;

  const _FormField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.iconColor,
    required this.isDark,
    required this.theme,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment:
            maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(top: maxLines > 1 ? 4 : 0),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  maxLines: maxLines,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.3),
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    filled: false,
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

// ── Form Divider ──
class _FormFieldDivider extends StatelessWidget {
  final bool isDark;
  const _FormFieldDivider({required this.isDark});

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
