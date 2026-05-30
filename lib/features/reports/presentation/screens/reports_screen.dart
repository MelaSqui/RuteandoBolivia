import 'dart:ui';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ruteando_bolivia/theme/app_theme.dart';
import 'package:ruteando_bolivia/features/reports/domain/models/report_category.dart';
import 'package:ruteando_bolivia/features/reports/domain/models/mock_photo.dart';
import 'package:ruteando_bolivia/features/reports/presentation/widgets/interactive_scale.dart';
import 'package:ruteando_bolivia/features/reports/presentation/widgets/category_chip.dart';
import 'package:ruteando_bolivia/features/reports/presentation/widgets/animated_photo_card.dart';
import 'package:ruteando_bolivia/features/reports/presentation/widgets/add_photo_card.dart';
import 'package:ruteando_bolivia/features/discovery/data/services/gemini_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  final _descriptionController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  int? _selectedCategoryIndex;
  bool _isSubmitting = false;
  bool _isGeminiApiKeyMissing = false;

  late AnimationController _animController;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;

  final List<ReportCategory> _categories = [
    const ReportCategory(
      label: 'Bloqueo',
      icon: Icons.block_flipped,
      color: AppTheme.warning,
    ),
    const ReportCategory(
      label: 'Accidente',
      icon: Icons.car_crash_outlined,
      color: AppTheme.danger,
    ),
    const ReportCategory(
      label: 'Clima',
      icon: Icons.wb_cloudy_outlined,
      color: AppTheme.climate,
    ),
    const ReportCategory(
      label: 'Estado de Ruta',
      icon: Icons.warning_amber_rounded,
      color: AppTheme.caution,
    ),
  ];

  final ImagePicker _picker = ImagePicker();
  final List<MockPhoto> _selectedPhotos = [];

  bool _isGpsLoading = false;
  bool _hasGpsPermission = true;
  String _detectedLocationName = 'Buscando ubicación actual (GPS)...';
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
    _requestGpsLocation();
    _checkApiKey();
  }

  void _checkApiKey() {
    const apiKey = String.fromEnvironment('GEMINI_API_KEY');
    if (apiKey.isEmpty) {
      setState(() {
        _isGeminiApiKeyMissing = true;
      });
      debugPrint('WARNING: GEMINI_API_KEY no esta configurada.');
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _requestGpsLocation() async {
    if (!mounted) return;
    setState(() {
      _isGpsLoading = true;
      _detectedLocationName = 'Accediendo al sensor GPS...';
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _isGpsLoading = false;
          _hasGpsPermission = false;
          _detectedLocationName = 'Servicio de ubicación desactivado.';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _isGpsLoading = false;
            _hasGpsPermission = false;
            _detectedLocationName = 'Permiso de ubicación denegado.';
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _isGpsLoading = false;
          _hasGpsPermission = false;
          _detectedLocationName = 'Permisos de GPS denegados permanentemente.';
        });
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _latitude = position.latitude;
      _longitude = position.longitude;

      setState(() {
        _hasGpsPermission = true;
        _isGpsLoading = false;
        _detectedLocationName = 'Buscando dirección de la vía...';
      });

      _reverseGeocode(_latitude!, _longitude!);
    } catch (e) {
      setState(() {
        _isGpsLoading = false;
        _detectedLocationName = 'Error al obtener ubicación GPS: $e';
      });
    }
  }

  void _setFallbackCoordinates(double lat, double lon) {
    if (mounted) {
      setState(() {
        _detectedLocationName = 'Ubicación GPS (${lat.toStringAsFixed(5)}°, ${lon.toStringAsFixed(5)}°)';
      });
    }
  }

  Future<void> _reverseGeocode(double lat, double lon) async {
    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon&zoom=16&addressdetails=1');
      final response = await http.get(
        url,
        headers: {'User-Agent': 'RuteandoBoliviaApp/1.0 (careo.gemini)'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final displayName = data['display_name'] as String?;
        if (displayName != null && displayName.isNotEmpty) {
          final address = data['address'] as Map<String, dynamic>?;
          String formattedAddress = displayName;
          if (address != null) {
            final road = address['road'] ?? address['suburb'] ?? address['neighbourhood'];
            final city = address['city'] ?? address['town'] ?? address['village'] ?? address['county'];
            final state = address['state'] ?? address['region'];
            if (road != null && city != null) {
              formattedAddress = '$road, $city';
              if (state != null) formattedAddress += ', $state';
            }
          }

          if (mounted) {
            setState(() {
              _detectedLocationName = formattedAddress;
            });
          }
          return;
        }
      }
      _setFallbackCoordinates(lat, lon);
    } catch (e) {
      print('Nominatim Geocoding Error: $e');
      _setFallbackCoordinates(lat, lon);
    }
  }

  Future<void> _pickAndVerifyImage() async {
    if (_selectedCategoryIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Por favor, selecciona una categoria para tu reporte antes de añadir una foto.'),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }
    if (_descriptionController.text.trim().length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Por favor, escribe una descripcion detallada (minimo 8 caracteres) antes de añadir una foto.'),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }
    if (_selectedPhotos.length >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Has alcanzado el limite de 4 fotografias para el reporte.'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Seleccionar evidencia vial',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'La imagen pasara por una validacion de Inteligencia Artificial para evitar spam.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSourceButton(
                    context: context,
                    icon: Icons.camera_alt_rounded,
                    label: 'Camara',
                    color: AppTheme.positive,
                    onTap: () => Navigator.pop(context, ImageSource.camera),
                  ),
                  _buildSourceButton(
                    context: context,
                    icon: Icons.photo_library_rounded,
                    label: 'Galeria / PC',
                    color: AppTheme.climate,
                    onTap: () => Navigator.pop(context, ImageSource.gallery),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (source == null) return;

    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );

      if (image == null) return;

      final Uint8List imageBytes = await image.readAsBytes();
      final String mimeType = image.mimeType ?? 'image/jpeg';
      final String fileName = image.name;

      if (!mounted) return;

      final category = _selectedCategoryIndex != null ? _categories[_selectedCategoryIndex!].label : '';
      final description = _descriptionController.text;

      _showVerificationModal(imageBytes, mimeType, fileName, category, description);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al seleccionar imagen: $e'),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Widget _buildSourceButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InteractiveScale(
      onTap: onTap,
      child: Container(
        width: 130,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.12 : 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withOpacity(isDark ? 0.25 : 0.35),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVerificationModal(Uint8List imageBytes, String mimeType, String fileName, String category, String description) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _AIVerificationDialog(
          imageBytes: imageBytes,
          mimeType: mimeType,
          fileName: fileName,
          category: category,
          description: description,
          onSuccess: (MockPhoto verifiedPhoto) {
            setState(() {
              _selectedPhotos.add(verifiedPhoto);
            });
          },
        );
      },
    );
  }

  void _removePhoto(String id) {
    setState(() {
      _selectedPhotos.removeWhere((photo) => photo.id == id);
    });
  }

  Future<void> _submitReport() async {
    if (_selectedCategoryIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Por favor, selecciona una categoria para tu reporte.'),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final categoryLabel = _categories[_selectedCategoryIndex!].label;
      final description = _descriptionController.text.trim();
      final now = DateTime.now().toIso8601String();

      // Parse department from location name
      final locationName = _detectedLocationName;
      String departamento = 'La Paz';
      final deptos = ['La Paz', 'Cochabamba', 'Santa Cruz', 'Oruro', 'Potosi', 'Potosí', 'Tarija', 'Beni', 'Pando', 'Chuquisaca'];
      for (var dep in deptos) {
        if (locationName.toLowerCase().contains(dep.toLowerCase())) {
          departamento = dep;
          break;
        }
      }

      String ruta = 'Local';
      final routeRegExp = RegExp(r'(?:ruta|rn|r|n)\s*([0-9]+)', caseSensitive: false);
      final match = routeRegExp.firstMatch(locationName);
      if (match != null) {
        ruta = match.group(1) ?? 'Local';
      } else {
        final numRegExp = RegExp(r'\b([0-9]{1,2})\b');
        final numMatch = numRegExp.firstMatch(locationName);
        if (numMatch != null) {
          ruta = numMatch.group(1) ?? 'Local';
        }
      }

      final Map<String, dynamic> rawDataMap = {
        'inicio_seccion': locationName,
        'fin_seccion': locationName,
        'descr_sector': 'Reporte de Usuario',
        'categoria_ia': categoryLabel,
        'descripcion_usuario': description,
      };

      final Map<String, dynamic> insertData = {
        'ruta': ruta,
        'departamento': departamento,
        'evento': '$categoryLabel: $description',
        'restriccion_vehicular': categoryLabel == 'Bloqueo'
            ? 'NO CIRCULAR'
            : (categoryLabel == 'Accidente' ? 'TRANSITO CON PRECAUCION' : 'PRECAUCION'),
        'transitable_con_desvio': 'NO',
        'trabajos_conservacion': 'NINGUNO',
        'latitud_inicio': _latitude ?? -16.2902,
        'longitud_inicio': _longitude ?? -63.5887,
        'hora_reporte': now,
        'raw_data': rawDataMap,
      };

      await Supabase.instance.client
          .from('road_events')
          .insert(insertData);

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });

      // Limpiar formulario
      _descriptionController.clear();
      setState(() {
        _selectedCategoryIndex = null;
        _selectedPhotos.clear();
      });

      // Mostrar bottom sheet de exito con animacion
      _showSuccessSheet();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al enviar el reporte: $e'),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _showSuccessSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        return Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
            border: Border.all(
              color: theme.colorScheme.outline,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 24,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 28),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.positive.withValues(alpha: 0.2),
                      AppTheme.positive.withValues(alpha: 0.08),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  size: 48,
                  color: AppTheme.positive,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '¡Reporte Enviado!',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Tu contribucion ha sido registrada y ayudara a mantener informados a otros viajeros en tiempo real.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              InteractiveScale(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.positive, AppTheme.positiveVariant],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.positive.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Entendido',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Section card builder ───
  Widget _buildSectionCard({
    required ThemeData theme,
    required bool isDark,
    required int stepNumber,
    required String title,
    required IconData icon,
    required Color accentColor,
    required Widget child,
    String? subtitle,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.9),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section header with step number
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          accentColor,
                          accentColor.withValues(alpha: 0.7),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$stepNumber',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(icon, size: 20, color: accentColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 40),
                  child: Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
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
          // ─── Background ───
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

          // ─── Content ───
          SafeArea(
            child: Column(
              children: [
                // ─── Static Header (Logo + Title) ───
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
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
                              theme.colorScheme.primary.withValues(alpha: 0.7),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withValues(alpha: 0.35),
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
                ),

                const SizedBox(height: 8),

                // ─── Scrollable Form Content ───
                Expanded(
                  child: FadeTransition(
                    opacity: _fadeIn,
                    child: SlideTransition(
                      position: _slideUp,
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ─── Page title & description ───
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: AppTheme.danger.withValues(alpha: isDark ? 0.15 : 0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.emergency_rounded,
                                                size: 14,
                                                color: AppTheme.danger,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                'NUEVO REPORTE',
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  color: AppTheme.danger,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 11,
                                                  letterSpacing: 0.8,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Reportar Incidente',
                                      style: theme.textTheme.displaySmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 26,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Informa a la comunidad sobre el estado de la transitabilidad. Cada reporte cuenta.',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 24),

                              // ─── Step 1: Category ───
                              _buildSectionCard(
                                theme: theme,
                                isDark: isDark,
                                stepNumber: 1,
                                title: 'Categoria',
                                icon: Icons.category_rounded,
                                accentColor: AppTheme.warning,
                                subtitle: 'Selecciona el tipo de incidente',
                                child: Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: List.generate(_categories.length, (index) {
                                    final category = _categories[index];
                                    final isSelected = _selectedCategoryIndex == index;
                                    return CategoryChip(
                                      category: category,
                                      isSelected: isSelected,
                                      isDisabled: _selectedPhotos.isNotEmpty,
                                      onTap: () {
                                        if (_selectedPhotos.isNotEmpty) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: const Text('No puedes cambiar la categoria con fotos asociadas. Elimina las fotos primero.'),
                                              backgroundColor: AppTheme.danger,
                                              behavior: SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            ),
                                          );
                                          return;
                                        }
                                        setState(() {
                                          _selectedCategoryIndex = index;
                                        });
                                      },
                                    );
                                  }),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // ─── Step 2: Description ───
                              _buildSectionCard(
                                theme: theme,
                                isDark: isDark,
                                stepNumber: 2,
                                title: 'Descripcion',
                                icon: Icons.edit_note_rounded,
                                accentColor: AppTheme.climate,
                                subtitle: 'Detalla lo ocurrido en la ruta',
                                child: TextFormField(
                                  controller: _descriptionController,
                                  maxLines: 4,
                                  readOnly: _selectedPhotos.isNotEmpty,
                                  onTap: () {
                                    if (_selectedPhotos.isNotEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: const Text('No puedes editar la descripcion con fotos asociadas. Elimina las fotos primero.'),
                                          backgroundColor: AppTheme.danger,
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      );
                                    }
                                  },
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurface,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Ej: Bloqueo de transportistas en km 45, derrumbe parcial...',
                                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                                      color: isDark
                                          ? AppTheme.darkTextSecondary.withValues(alpha: 0.6)
                                          : AppTheme.lightTextSecondary.withValues(alpha: 0.7),
                                    ),
                                    alignLabelWithHint: true,
                                    contentPadding: const EdgeInsets.all(16),
                                    filled: true,
                                    fillColor: isDark
                                        ? Colors.black.withValues(alpha: 0.2)
                                        : Colors.white.withValues(alpha: 0.6),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide(
                                        color: theme.colorScheme.outline.withValues(alpha: 0.5),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide(
                                        color: theme.colorScheme.outline.withValues(alpha: 0.5),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide(
                                        color: AppTheme.climate,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Por favor introduce una breve descripcion.';
                                    }
                                    if (value.trim().length < 8) {
                                      return 'La descripcion debe ser mas detallada.';
                                    }
                                    return null;
                                  },
                                ),
                              ),

                              const SizedBox(height: 16),

                              // ─── Step 3: Photos ───
                              _buildSectionCard(
                                theme: theme,
                                isDark: isDark,
                                stepNumber: 3,
                                title: 'Evidencia',
                                icon: Icons.camera_alt_rounded,
                                accentColor: AppTheme.positive,
                                subtitle: 'Adjunta fotografias del incidente (opcional)',
                                child: SizedBox(
                                  height: 110,
                                  child: ListView(
                                    scrollDirection: Axis.horizontal,
                                    physics: const BouncingScrollPhysics(),
                                    children: [
                                      ..._selectedPhotos.map((photo) {
                                        return AnimatedPhotoCard(
                                          key: ValueKey(photo.id),
                                          photo: photo,
                                          onDelete: () => _removePhoto(photo.id),
                                        );
                                      }),
                                      AddPhotoCard(onTap: _pickAndVerifyImage),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // ─── Step 4: Location ───
                              _buildSectionCard(
                                theme: theme,
                                isDark: isDark,
                                stepNumber: 4,
                                title: 'Ubicacion',
                                icon: Icons.location_on_rounded,
                                accentColor: AppTheme.caution,
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.black.withValues(alpha: 0.2)
                                        : Colors.white.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: theme.colorScheme.outline.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              AppTheme.climate.withValues(alpha: 0.15),
                                              AppTheme.climate.withValues(alpha: 0.05),
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: _isGpsLoading
                                            ? const SizedBox(
                                                width: 22,
                                                height: 22,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: AppTheme.climate,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.my_location_rounded,
                                                size: 22,
                                                color: AppTheme.climate,
                                              ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _isGpsLoading ? 'Detectando ubicacion...' : 'Ubicacion detectada',
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              _detectedLocationName,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (!_isGpsLoading) ...[
                                        InteractiveScale(
                                          onTap: _requestGpsLocation,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: _hasGpsPermission
                                                  ? AppTheme.positive.withValues(alpha: 0.12)
                                                  : AppTheme.warning.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (_hasGpsPermission) ...[
                                                  Container(
                                                    width: 6,
                                                    height: 6,
                                                    decoration: const BoxDecoration(
                                                      color: AppTheme.positive,
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 5),
                                                  Text(
                                                    'GPS',
                                                    style: theme.textTheme.bodySmall?.copyWith(
                                                      color: AppTheme.positive,
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ] else ...[
                                                  const Icon(
                                                    Icons.sync_problem_rounded,
                                                    size: 12,
                                                    color: AppTheme.warning,
                                                  ),
                                                  const SizedBox(width: 5),
                                                  Text(
                                                    'Reintentar',
                                                    style: theme.textTheme.bodySmall?.copyWith(
                                                      color: AppTheme.warning,
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 28),

                              // ─── Submit Button ───
                              InteractiveScale(
                                onTap: _isSubmitting ? null : _submitReport,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                      colors: _isSubmitting
                                          ? [
                                              AppTheme.positive.withValues(alpha: 0.4),
                                              AppTheme.positiveVariant.withValues(alpha: 0.4),
                                            ]
                                          : [
                                              AppTheme.positive,
                                              AppTheme.positiveVariant,
                                            ],
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: _isSubmitting
                                        ? []
                                        : [
                                            BoxShadow(
                                              color: AppTheme.positive.withValues(alpha: 0.35),
                                              blurRadius: 16,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (_isSubmitting)
                                        const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2.5,
                                          ),
                                        )
                                      else ...[
                                        const Icon(
                                          Icons.send_rounded,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          'Enviar Reporte',
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
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

class _AIVerificationDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final String mimeType;
  final String fileName;
  final String category;
  final String description;
  final Function(MockPhoto) onSuccess;

  const _AIVerificationDialog({
    required this.imageBytes,
    required this.mimeType,
    required this.fileName,
    required this.category,
    required this.description,
    required this.onSuccess,
  });

  @override
  State<_AIVerificationDialog> createState() => _AIVerificationDialogState();
}

class _AIVerificationDialogState extends State<_AIVerificationDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _scannerController;
  String _statusMessage = 'Inicializando verificacion...';
  bool _isChecking = true;
  bool _isValid = false;
  double _confidence = 0.0;
  String _reason = '';
  String _category = 'Desconocido';

  final List<String> _loadingMessages = [
    'Conectando con Ruteando AI...',
    'Analizando composicion de imagen...',
    'Buscando elementos de infraestructura vial...',
    'Evaluando relevancia de obstrucciones o da;os...',
    'Comprobando integridad y descartando spam...',
    'Finalizando analisis de evidencia...',
  ];
  int _messageIndex = 0;

  @override
  void initState() {
    super.initState();
    _scannerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _startMessageRotation();
    _performVerification();
  }

  void _startMessageRotation() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 1800));
      if (!mounted || !_isChecking) return false;
      setState(() {
        _messageIndex = (_messageIndex + 1) % _loadingMessages.length;
        _statusMessage = _loadingMessages[_messageIndex];
      });
      return true;
    });
  }

  Future<void> _performVerification() async {
    final startTime = DateTime.now();

    final result = await GeminiService().verifyImage(
      widget.imageBytes,
      widget.mimeType,
      widget.category,
      widget.description,
    );

    final elapsed = DateTime.now().difference(startTime);
    if (elapsed.inMilliseconds < 2200) {
      await Future.delayed(Duration(milliseconds: 2200 - elapsed.inMilliseconds));
    }

    if (!mounted) return;

    setState(() {
      _isChecking = false;
      _isValid = result['is_valid'] ?? false;
      _confidence = result['confidence'] ?? 0.0;
      _reason = result['reason'] ?? 'Sin descripcion de la IA.';
      _category = result['category'] ?? 'Desconocido';
    });

    if (_isValid) {
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;

      Color tintColor = const Color(0xFF38BDF8);
      IconData icon = Icons.image_outlined;

      switch (_category) {
        case 'Bloqueo':
          tintColor = AppTheme.warning;
          icon = Icons.alt_route_rounded;
          break;
        case 'Accidente':
          tintColor = AppTheme.danger;
          icon = Icons.report_problem_rounded;
          break;
        case 'Clima':
          tintColor = AppTheme.climate;
          icon = Icons.cloud_queue_rounded;
          break;
        case 'Estado de Ruta':
          tintColor = AppTheme.caution;
          icon = Icons.broken_image_rounded;
          break;
      }

      final verifiedPhoto = MockPhoto(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: widget.fileName,
        tintColor: tintColor,
        icon: icon,
        imageBytes: widget.imageBytes,
        isVerified: true,
        aiConfidence: _confidence,
        aiReason: _reason,
      );

      Navigator.pop(context);
      widget.onSuccess(verifiedPhoto);
    }
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard.withOpacity(0.9) : AppTheme.lightCard.withOpacity(0.95),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.black12,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isChecking) ...[
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTheme.climate.withOpacity(0.5),
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.memory(
                          widget.imageBytes,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _scannerController,
                      builder: (context, child) {
                        return Positioned(
                          top: 4 + (_scannerController.value * 128),
                          left: 4,
                          right: 4,
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppTheme.climate,
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.climate.withOpacity(0.8),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.climate, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.psychology_outlined,
                        size: 24,
                        color: AppTheme.climate,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Verificando Evidencia',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 36,
                  child: Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppTheme.climate,
                  ),
                ),
              ] else if (_isValid) ...[
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.positive.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.verified_rounded,
                    size: 56,
                    color: AppTheme.positive,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '¡Evidencia Aprobada!',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.positive,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Confianza de la IA: ${_confidence.toInt()}%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _reason,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.gpp_bad_outlined,
                    size: 56,
                    color: AppTheme.danger,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Imagen No Admitida',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.danger,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'El motor de IA determino que esta imagen no corresponde a un reporte vial de transitabilidad.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ),
                if (_reason.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Razon IA: $_reason',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                InteractiveScale(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.danger,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        'Entendido',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
