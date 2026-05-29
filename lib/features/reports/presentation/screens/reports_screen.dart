import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:ruteando_bolivia/theme/app_theme.dart';
import 'package:ruteando_bolivia/features/reports/domain/models/report_category.dart';
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

  final List<XFile> _selectedPhotos = [];
  final ImagePicker _picker = ImagePicker();
  
  Position? _currentPosition;
  bool _isLoadingLocation = false;
  String _locationError = '';

  bool _isAnalyzingAI = false;
  String _aiStatusMessage = '';

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  @override
  void dispose() {
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

      setState(() {
        _currentPosition = position;
        _isLoadingLocation = false;
      });
    } catch (e) {
      setState(() {
        _locationError = 'Error al obtener GPS: $e';
        _isLoadingLocation = false;
      });
    }
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
        setState(() {
          _selectedPhotos.add(image);
        });
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

  void _removePhoto(int index) {
    setState(() {
      _selectedPhotos.removeAt(index);
    });
  }

  Future<bool> _analyzeImageWithGemini(XFile image, String description) async {
    const apiKey = String.fromEnvironment('GEMINI_API_KEY');
    if (apiKey.isEmpty) {
      debugPrint('WARNING: GEMINI_API_KEY is not defined in environment variables.');
      setState(() {
        _aiStatusMessage = 'Simulando validacion de IA (Clave API no configurada)...';
      });
      await Future.delayed(const Duration(seconds: 2));
      return true;
    }

    try {
      setState(() {
        _aiStatusMessage = 'Gemini analizando fotografia del incidente...';
      });

      final bytes = await image.readAsBytes();
      final content = [
        Content.multi([
          TextPart('''
          Analiza la siguiente imagen de un reporte vial y la descripcion del usuario.
          Determina si la imagen respalda o coincide con la descripcion del incidente (ej. bloqueo de carretera, derrumbe, bache, accidente, etc.).
          
          Descripcion del usuario: "$description"
          
          Responde exclusivamente en formato JSON estricto con esta estructura:
          {
            "valido": true o false,
            "motivo": "Explicacion muy breve y concisa en espanol del resultado"
          }
          
          No incluyas markdown, codigos o texto adicional en tu respuesta. Solo el objeto JSON.
          '''),
          DataPart('image/jpeg', bytes),
        ])
      ];

      final model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: apiKey,
      );

      final response = await model.generateContent(content);
      final text = response.text;
      
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

      if (!valido) {
        if (!mounted) return false;
        _showAiRejectionDialog(motivo);
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Error en el analisis de IA: $e');
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al analizar la imagen con IA: $e. Reintentando sin IA...'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return true;
    }
  }

  void _showAiRejectionDialog(String motivo) {
    showDialog(
      context: context,
      barrierDismissible: false,
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
                    color: AppTheme.danger.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.report_problem_rounded,
                    size: 40,
                    color: AppTheme.danger,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Reporte no Validado por IA',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'El analisis automatico de la fotografia indica que esta no coincide con la descripcion del incidente vial provista.',
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
                  padding: const EdgeInsets.all(14),
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
                        motivo,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                InteractiveScale(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.danger,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Revisar reporte',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _submitReport() async {
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

    setState(() {
      _isSubmitting = true;
      _isAnalyzingAI = true;
      _aiStatusMessage = 'Iniciando verificacion del reporte...';
    });

    // Validar primera imagen con Gemini
    final bool isImageValid = await _analyzeImageWithGemini(
      _selectedPhotos.first,
      _descriptionController.text,
    );

    if (!isImageValid) {
      setState(() {
        _isSubmitting = false;
        _isAnalyzingAI = false;
      });
      return;
    }

    setState(() {
      _aiStatusMessage = 'Guardando reporte en el sistema...';
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
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _isAnalyzingAI = false;
      });

      // Limpiar formulario
      _descriptionController.clear();
      setState(() {
        _selectedCategoryIndex = null;
        _selectedPhotos.clear();
      });

      // Mostrar bottom sheet de exito
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
                  style: theme.textTheme.titleLarge?.copyWith(
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo Reporte'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                          onTap: () {
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
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Detalla lo que esta ocurriendo en la ruta (ej. bloqueo de transportistas, derrumbe parcial)...',
                        alignLabelWithHint: true,
                        contentPadding: EdgeInsets.all(16),
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
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 110,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: _selectedPhotos.length + 1,
                        itemBuilder: (context, index) {
                          if (index == _selectedPhotos.length) {
                            return AddPhotoCard(onTap: _showImageSourceBottomSheet);
                          }
                          final photo = _selectedPhotos[index];
                          return AnimatedPhotoCard(
                            key: ValueKey(photo.path),
                            photo: photo,
                            onDelete: () => _removePhoto(index),
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
            if (_isAnalyzingAI)
              Container(
                color: Colors.black.withOpacity(0.6),
                width: double.infinity,
                height: double.infinity,
                child: Center(
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            color: AppTheme.climate,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Validacion por Inteligencia Artificial',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _aiStatusMessage,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
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
