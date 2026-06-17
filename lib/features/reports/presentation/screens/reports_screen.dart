import 'dart:ui';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:ruteando_bolivia/features/routes/utils/route_utils.dart';
import 'package:ruteando_bolivia/theme/app_theme.dart';
import 'package:ruteando_bolivia/features/reports/domain/models/report_category.dart';
import 'package:ruteando_bolivia/features/reports/domain/models/mock_photo.dart';
import 'package:ruteando_bolivia/features/reports/presentation/widgets/interactive_scale.dart';
import 'package:ruteando_bolivia/features/reports/presentation/widgets/category_chip.dart';
import 'package:ruteando_bolivia/features/reports/presentation/widgets/animated_photo_card.dart';
import 'package:ruteando_bolivia/features/reports/presentation/widgets/add_photo_card.dart';
import 'package:ruteando_bolivia/features/reports/presentation/widgets/ai_verification_dialog.dart';

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

      Position? position;

      // 1. Intentar obtener la última ubicación conocida (es casi instantáneo)
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          position = lastKnown;
          _latitude = lastKnown.latitude;
          _longitude = lastKnown.longitude;
          setState(() {
            _hasGpsPermission = true;
            _detectedLocationName = 'Ubicación rápida obtenida. Actualizando...';
          });
          _reverseGeocode(_latitude!, _longitude!);
        }
      } catch (e) {
        debugPrint('Error obteniendo last known position: $e');
      }

      // 2. Intentar obtener la ubicación actual con alta precisión (GPS) y un tiempo límite corto
      try {
        final currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 6),
        );
        position = currentPosition;
      } catch (e) {
        debugPrint('Error/Timeout con precisión alta: $e. Intentando precisión baja/red...');
        // 3. Si falla/da timeout (por estar en interiores), intentar con precisión baja (red/wifi)
        try {
          final networkPosition = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
            timeLimit: const Duration(seconds: 4),
          );
          position = networkPosition;
        } catch (innerE) {
          debugPrint('Error/Timeout también con precisión baja: $innerE');
        }
      }

      if (position != null) {
        _latitude = position.latitude;
        _longitude = position.longitude;

        setState(() {
          _hasGpsPermission = true;
          _isGpsLoading = false;
          _detectedLocationName = 'Buscando dirección de la vía...';
        });

        _reverseGeocode(_latitude!, _longitude!);
      } else {
        // Si no se obtuvo ninguna ubicación
        setState(() {
          _isGpsLoading = false;
          if (_latitude != null && _longitude != null) {
            // Mantener la última conocida si existe
            _detectedLocationName = 'Dirección basada en última ubicación conocida...';
            _reverseGeocode(_latitude!, _longitude!);
          } else {
            _detectedLocationName = 'No se pudo obtener señal GPS. Toca para reintentar.';
          }
        });
      }
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

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
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
          content: Text('Error al capturar imagen: $e'),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _showVerificationModal(Uint8List imageBytes, String mimeType, String fileName, String category, String description) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AIVerificationDialog(
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

      // 1. Verificar duplicados a menos de 100 metros (0.1 km)
      final userLat = _latitude;
      final userLng = _longitude;
      if (userLat != null && userLng != null) {
        final userLatLng = LatLng(userLat, userLng);
        
        final responseEvents = await Supabase.instance.client
            .from('road_events')
            .select('id, evento, latitud_inicio, longitud_inicio, raw_data');

        Map<String, dynamic>? existingConflict;
        for (final item in responseEvents as List) {
          final e = item as Map<String, dynamic>;
          final double? lat = double.tryParse(e['latitud_inicio']?.toString() ?? '');
          final double? lng = double.tryParse(e['longitud_inicio']?.toString() ?? '');
          if (lat == null || lng == null) continue;

          final rawData = e['raw_data'];
          Map<String, dynamic>? raw;
          if (rawData is Map<String, dynamic>) {
            raw = rawData;
          } else if (rawData is String) {
            try {
              raw = jsonDecode(rawData) as Map<String, dynamic>;
            } catch (_) {}
          }

          final sigue = int.tryParse(raw?['votos_sigue']?.toString() ?? '0') ?? 0;
          final despejado = int.tryParse(raw?['votos_despejado']?.toString() ?? '0') ?? 0;
          final isActive = !(despejado >= 1 && despejado > sigue);
          if (!isActive) continue;

          final dist = RouteUtils.calculateDistance(userLatLng, LatLng(lat, lng));
          if (dist <= 0.1) { // 100 metros
            existingConflict = e;
            break;
          }
        }

        if (existingConflict != null) {
          if (!mounted) return;
          setState(() {
            _isSubmitting = false;
          });

          final rawData = existingConflict['raw_data'];
          Map<String, dynamic>? raw;
          if (rawData is Map<String, dynamic>) {
            raw = rawData;
          } else if (rawData is String) {
            try {
              raw = jsonDecode(rawData) as Map<String, dynamic>;
            } catch (_) {}
          }
          final String existingCategory = raw?['categoria_ia']?.toString() ?? 'Incidente vial';
          final String existingDescription = existingConflict['evento'] ?? 'Incidente vial activo';

          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 28),
                  SizedBox(width: 12),
                  Text('Reporte Duplicado'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ya existe un reporte de tipo "$existingCategory" registrado a menos de 100 metros de tu ubicación actual:',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      existingDescription,
                      style: const TextStyle(
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Para evitar duplicar pines e interferir en la lectura del mapa, no se permite crear otro reporte en esta misma zona. Puedes apoyar o votar sobre la vigencia de esta alerta desde el mapa principal o la lista de alertas.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.positive,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendido'),
                ),
              ],
            ),
          );
          return;
        }
      }

      // Obtener la descripcion reformulada por la IA si existe en alguna foto verificada
      String? reformulatedDescription;
      for (final photo in _selectedPhotos) {
        if (photo.description != null && photo.description!.trim().isNotEmpty) {
          reformulatedDescription = photo.description!.trim();
          break;
        }
      }

      final String finalEventDescription = reformulatedDescription ?? description;

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
        if (reformulatedDescription != null)
          'descripcion_reformulada': reformulatedDescription,
      };

      final Map<String, dynamic> insertData = {
        'ruta': ruta,
        'departamento': departamento,
        'evento': '$categoryLabel: $finalEventDescription',
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

      // Incrementar el conteo de reportes en el perfil del usuario
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser != null) {
        try {
          final profileRes = await Supabase.instance.client
              .from('profiles')
              .select('reports_count')
              .eq('id', currentUser.id)
              .maybeSingle();

          if (profileRes != null) {
            final int currentCount = (profileRes['reports_count'] as num?)?.toInt() ?? 0;
            await Supabase.instance.client
                .from('profiles')
                .update({'reports_count': currentCount + 1})
                .eq('id', currentUser.id);
          }
        } catch (profileError) {
          debugPrint('Error updating user reports count: $profileError');
        }
      }

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

