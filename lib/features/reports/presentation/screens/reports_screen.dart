import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:ruteando_bolivia/theme/app_theme.dart';
import 'package:ruteando_bolivia/features/reports/domain/models/report_category.dart';
import 'package:ruteando_bolivia/features/reports/domain/models/report_photo.dart';
import 'package:ruteando_bolivia/features/reports/presentation/widgets/interactive_scale.dart';
import 'package:ruteando_bolivia/features/reports/presentation/widgets/category_chip.dart';
import 'package:ruteando_bolivia/features/reports/presentation/widgets/animated_photo_card.dart';
import 'package:ruteando_bolivia/features/reports/presentation/widgets/add_photo_card.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _descriptionController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  int? _selectedCategoryIndex;
  bool _isSubmitting = false;
  bool _isGeminiApiKeyMissing = false;

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

  final List<ReportPhoto> _selectedPhotos = [];
  final ImagePicker _picker = ImagePicker();
  
  Position? _currentPosition;
  bool _isLoadingLocation = false;
  String _locationError = '';

  @override
  void initState() {
    super.initState();
    _determinePosition();
    _descriptionController.addListener(_onDescriptionChanged);
    _checkApiKey();
  }

  void _checkApiKey() {
    const apiKey = String.fromEnvironment('GEMINI_API_KEY');
    if (apiKey.isEmpty) {
      setState(() {
        _isGeminiApiKeyMissing = true;
      });
      debugPrint('WARNING: GEMINI_API_KEY is not defined in environment variables.');
    }
  }

  void _onDescriptionChanged() {
    // Re-evaluar de forma reactiva el estado para habilitar/deshabilitar la carga de fotos
    setState(() {});
  }

  @override
  void dispose() {
    _descriptionController.removeListener(_onDescriptionChanged);
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _determinePosition() async {
    if (!mounted) return;
    setState(() {
      _isLoadingLocation = true;
      _locationError = '';
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationError = 'El servicio de GPS esta desactivado.';
          _isLoadingLocation = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _locationError = 'Permiso de GPS denegado.';
            _isLoadingLocation = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locationError = 'Permisos de GPS denegados permanentemente.';
          _isLoadingLocation = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        _isLoadingLocation = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locationError = 'Error al obtener GPS: $e';
        _isLoadingLocation = false;
      });
    }
  }

  void _onAddPhotoTap() {
    if (_selectedCategoryIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, selecciona una categoria para tu reporte antes de añadir una foto.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }
    if (_descriptionController.text.trim().length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, escribe una descripcion detallada (minimo 8 caracteres) antes de añadir una foto.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }
    _showImageSourceBottomSheet();
  }

  void _showImageSourceBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            border: Border.all(
              color: theme.colorScheme.outline,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 50,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Selecciona el origen de la foto',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ImageSourceButton(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camara',
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.camera);
                    },
                  ),
                  _ImageSourceButton(
                    icon: Icons.photo_library_rounded,
                    label: 'Galeria',
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.gallery);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 70,
      );
      if (image != null) {
        if (!mounted) return;
        if (_selectedPhotos.length >= 4) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Has alcanzado el limite de 4 fotografias para el reporte.'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }

        final reportPhoto = ReportPhoto(
          file: image,
          isValidating: true,
        );

        setState(() {
          _selectedPhotos.add(reportPhoto);
        });

        // Disparar validacion en background
        _validatePhotoWithGemini(reportPhoto);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al seleccionar la imagen: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  Future<void> _validatePhotoWithGemini(ReportPhoto reportPhoto) async {
    const apiKey = String.fromEnvironment('GEMINI_API_KEY');
    if (apiKey.isEmpty) {
      debugPrint('WARNING: GEMINI_API_KEY no esta configurada. Omitiendo validacion de IA.');
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      setState(() {
        reportPhoto.isValidating = false;
        reportPhoto.isValid = true;
      });
      return;
    }

    try {
      debugPrint('Iniciando analisis de imagen con Gemini...');
      final bytes = await reportPhoto.file.readAsBytes();
      final category = _selectedCategoryIndex != null ? _categories[_selectedCategoryIndex!].label : '';
      final description = _descriptionController.text;

      final content = [
        Content.multi([
          TextPart('''
          Eres un asistente experto en seguridad vial y control de transito en Bolivia.
          Analiza la siguiente imagen de un reporte vial y determina si es coherente con la categoria del incidente y la descripcion del usuario.

          Categoria seleccionada: "$category"
          Descripcion del usuario: "$description"

          Instrucciones de evaluacion:
          1. Se estricto. La imagen debe mostrar evidencia clara y directa del incidente reportado en la categoria y descripcion.
          2. Si la categoria es "Bloqueo", la imagen debe mostrar elementos que obstruyan el libre transito (barricadas, piedras, llantas, debrises, manifestantes, o calles totalmente cerradas). Si la calle o carretera se ve transitable, libre, despejada o limpia de obstaculos, debes marcar el reporte como NO valido.
          3. Si la categoria es "Accidente", la imagen debe mostrar vehiculos colisionados, personal de emergencia o danos viales resultantes de un siniestro.
          4. Si la categoria es "Clima", la imagen debe evidenciar factores de clima adversos (lluvia intensa, granizo, neblina densa, inundacion).
          5. Si la categoria es "Estado de Ruta", la imagen debe mostrar baches, asfalto danado, derrumbes o tierra inestable.
          6. Si la imagen muestra una situacion normal, transito fluido, una calle limpia o no tiene relacion con lo descrito, determina que es NO valido.

          Responde unicamente en formato JSON estricto:
          {
            "valido": true o false,
            "motivo": "Explicacion concisa de por que es valido o el motivo del rechazo en espanol"
          }

          No uses bloques de codigo markdown. Responde solo con el JSON crudo.
          '''),
          DataPart('image/jpeg', bytes),
        ])
      ];

      final model = GenerativeModel(
        model: 'gemini-3.5-flash',
        apiKey: apiKey,
      );

      final response = await model.generateContent(content);
      final text = response.text;
      
      debugPrint('Respuesta cruda de Gemini: $text');
      
      if (text == null || text.trim().isEmpty) {
        throw Exception('Respuesta vacia del servicio de IA.');
      }

      String cleanJson = text.trim();
      if (cleanJson.startsWith('```')) {
        cleanJson = cleanJson.replaceAll(RegExp(r'^```json\s*|```$'), '').trim();
      }

      final Map<String, dynamic> result = jsonDecode(cleanJson);
      final bool valido = result['valido'] ?? false;
      final String motivo = result['motivo'] ?? 'No se pudo verificar la coherencia.';

      debugPrint('Analisis completado. Valido: $valido, Motivo: $motivo');

      if (!mounted) return;
      setState(() {
        reportPhoto.isValidating = false;
        reportPhoto.isValid = valido;
        reportPhoto.rejectionReason = valido ? null : motivo;
      });
    } catch (e) {
      debugPrint('Error en el analisis de IA: $e');
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error en el analisis de la IA: $e. Se aprobo por contingencia.'),
          backgroundColor: AppTheme.warning,
          duration: const Duration(seconds: 4),
        ),
      );

      setState(() {
        reportPhoto.isValidating = false;
        reportPhoto.isValid = true;
      });
    }
  }

  void _showRejectionDetailsDialog(ReportPhoto photo, int index) {
    showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.report_problem_rounded,
                    size: 32,
                    color: AppTheme.danger,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Foto Rechazada por IA',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Esta fotografia no coincide con el incidente reportado.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.brightness == Brightness.dark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outline,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Motivo del rechazo:',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.danger,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        photo.rejectionReason ?? 'No cumple con los requisitos del reporte.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Cerrar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _removePhoto(index);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.danger,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Eliminar foto'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _removePhoto(int index) {
    setState(() {
      _selectedPhotos.removeAt(index);
    });
  }

  void _submitReport() {
    if (_selectedCategoryIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, selecciona una categoria para tu reporte.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se puede enviar el reporte sin coordenadas GPS validas.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      _determinePosition();
      return;
    }

    if (_selectedPhotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Es obligatorio adjuntar al menos una fotografia para validar el reporte.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    if (_selectedPhotos.any((photo) => photo.isValidating)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, espera a que finalice el analisis de las fotografias.'),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    if (_selectedPhotos.any((photo) => photo.isValid == false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, remueve las fotografias que fueron rechazadas por la IA.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    // Log para el desarrollador del mapa con los datos completos
    debugPrint('=== REPORTE VALIDADO Y ENVIADO ===');
    debugPrint('Categoria: ${_categories[_selectedCategoryIndex!].label}');
    debugPrint('Descripcion: ${_descriptionController.text}');
    debugPrint('Coordenadas GPS: Lat: ${_currentPosition!.latitude}, Lng: ${_currentPosition!.longitude}');
    debugPrint('Precision GPS: ${_currentPosition!.accuracy} metros');
    debugPrint('Numero de fotos adjuntas: ${_selectedPhotos.length}');
    debugPrint('=================================');

    // Simular el envio
    Future.delayed(const Duration(milliseconds: 1500), () {
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
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) {
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;

          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              border: Border.all(
                color: theme.colorScheme.outline,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 50,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.positive.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 48,
                    color: AppTheme.positive,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Reporte Creado con Exito',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Tu contribucion ha sido registrada y ayudara a mantener informados a otros viajeros en tiempo real.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                InteractiveScale(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.positive,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Listo',
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bool isFormReadyForPhotos = _selectedCategoryIndex != null && _descriptionController.text.trim().length >= 8;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo Reporte'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cabecera e informacion
                Text(
                  'Reportar un Incidente',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 24,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Informa a la comunidad sobre el estado de la transitabilidad. Cada reporte cuenta.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),

                // Categoria
                Text(
                  'Categoria del incidente',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
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
                            const SnackBar(
                              content: Text('No puedes cambiar la categoria con fotos asociadas. Elimina las fotos primero.'),
                              backgroundColor: AppTheme.warning,
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
                const SizedBox(height: 24),

                // Descripcion
                Text(
                  'Descripcion del suceso',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 4,
                  readOnly: _selectedPhotos.isNotEmpty,
                  onTap: () {
                    if (_selectedPhotos.isNotEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No puedes editar la descripcion con fotos asociadas. Elimina las fotos primero.'),
                          backgroundColor: AppTheme.warning,
                        ),
                      );
                    }
                  },
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _selectedPhotos.isNotEmpty
                        ? (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)
                        : theme.colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Detalla lo que esta ocurriendo en la ruta (ej. bloqueo de transportistas, derrumbe parcial)...',
                    alignLabelWithHint: true,
                    contentPadding: const EdgeInsets.all(16),
                    filled: true,
                    fillColor: _selectedPhotos.isNotEmpty
                        ? (isDark ? const Color(0xFF161A22) : const Color(0xFFE5E7EB))
                        : null,
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
                const SizedBox(height: 24),

                // Fotografias
                Text(
                  'Fotografias (obligatorio para validar)',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Completa primero la categoria y descripcion para desbloquear esta seccion.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ),
                if (_isGeminiApiKeyMissing) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Modo Demo: GEMINI_API_KEY no configurada. Las fotos se aprobaran automaticamente sin analisis real.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  height: 110,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _selectedPhotos.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _selectedPhotos.length) {
                        return Opacity(
                          opacity: isFormReadyForPhotos ? 1.0 : 0.45,
                          child: AddPhotoCard(onTap: _onAddPhotoTap),
                        );
                      }
                      final photo = _selectedPhotos[index];
                      return GestureDetector(
                        onTap: () {
                          if (photo.isValid == false) {
                            _showRejectionDetailsDialog(photo, index);
                          }
                        },
                        child: AnimatedPhotoCard(
                          key: ValueKey(photo.file.path),
                          photo: photo,
                          onDelete: () => _removePhoto(index),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),

                // Ubicacion del reporte
                Text(
                  'Ubicacion del reporte',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _locationError.isNotEmpty
                          ? AppTheme.danger.withOpacity(0.5)
                          : theme.colorScheme.outline,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _locationError.isNotEmpty
                              ? AppTheme.danger.withOpacity(0.12)
                              : AppTheme.climate.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.location_on_rounded,
                          size: 20,
                          color: _locationError.isNotEmpty
                              ? AppTheme.danger
                              : AppTheme.climate,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ubicacion del Dispositivo',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            if (_isLoadingLocation)
                              Text(
                                'Detectando posicion en tiempo real...',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                ),
                              )
                            else if (_locationError.isNotEmpty)
                              Text(
                                _locationError,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppTheme.danger,
                                ),
                              )
                            else if (_currentPosition != null)
                              Text(
                                'Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}, Lng: ${_currentPosition!.longitude.toStringAsFixed(6)} (Precision: +/- ${_currentPosition!.accuracy.toStringAsFixed(1)}m)',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                ),
                              )
                            else
                              Text(
                                'GPS inactivo',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (_isLoadingLocation)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.climate,
                          ),
                        )
                      else if (_locationError.isNotEmpty)
                        TextButton(
                          onPressed: _determinePosition,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(50, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Reintentar',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.climate,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else if (_currentPosition != null)
                        Text(
                          'GPS Activo',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.positive,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Boton de envio
                InteractiveScale(
                  onTap: _isSubmitting ? null : _submitReport,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: _isSubmitting 
                          ? AppTheme.positive.withOpacity(0.5) 
                          : AppTheme.positive,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(
                            'Enviar reporte',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageSourceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ImageSourceButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InteractiveScale(
      onTap: onTap,
      child: Container(
        width: 130,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outline,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: AppTheme.climate),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
