import 'package:flutter/material.dart';
import 'package:ruteando_bolivia/theme/app_theme.dart';
import 'package:ruteando_bolivia/features/reports/domain/models/report_category.dart';
import 'package:ruteando_bolivia/features/reports/domain/models/mock_photo.dart';
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

  final List<MockPhoto> _photoTemplates = [
    const MockPhoto(
      id: '1',
      title: 'bloqueo_ruta.jpg',
      tintColor: Color(0xFFF97316),
      icon: Icons.alt_route_rounded,
    ),
    const MockPhoto(
      id: '2',
      title: 'deslizamiento.jpg',
      tintColor: Color(0xFF38BDF8),
      icon: Icons.landscape_rounded,
    ),
    const MockPhoto(
      id: '3',
      title: 'accidente_detalles.jpg',
      tintColor: Color(0xFFEF4444),
      icon: Icons.report_problem_rounded,
    ),
    const MockPhoto(
      id: '4',
      title: 'bache_camino.jpg',
      tintColor: Color(0xFFEAB308),
      icon: Icons.broken_image_rounded,
    ),
  ];

  final List<MockPhoto> _selectedPhotos = [];

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  void _addMockPhoto() {
    if (_selectedPhotos.length >= _photoTemplates.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Has alcanzado el limite de 4 fotografias para el reporte.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() {
      _selectedPhotos.add(_photoTemplates[_selectedPhotos.length]);
    });
  }

  void _removePhoto(String id) {
    setState(() {
      _selectedPhotos.removeWhere((photo) => photo.id == id);
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

    setState(() {
      _isSubmitting = true;
    });

    // Simular el envio con una respuesta tactil y visual
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
                  'Fotografias (opcional)',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
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
                      AddPhotoCard(onTap: _addMockPhoto),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Ubicacion sutil (mock de ubicacion automatica)
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
                      color: theme.colorScheme.outline,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.climate.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          size: 20,
                          color: AppTheme.climate,
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
                            Text(
                              'Carretera Central, Cochabamba - Santa Cruz',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
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
