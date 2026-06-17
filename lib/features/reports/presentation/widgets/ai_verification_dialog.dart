import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:exif/exif.dart';
import 'package:ruteando_bolivia/theme/app_theme.dart';
import 'package:ruteando_bolivia/features/reports/domain/models/mock_photo.dart';
import 'package:ruteando_bolivia/features/reports/presentation/widgets/interactive_scale.dart';
import 'package:ruteando_bolivia/features/discovery/data/services/gemini_service.dart';

class AIVerificationDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final String mimeType;
  final String fileName;
  final String category;
  final String description;
  final Function(MockPhoto) onSuccess;

  const AIVerificationDialog({
    super.key,
    required this.imageBytes,
    required this.mimeType,
    required this.fileName,
    required this.category,
    required this.description,
    required this.onSuccess,
  });

  @override
  State<AIVerificationDialog> createState() => _AIVerificationDialogState();
}

class _AIVerificationDialogState extends State<AIVerificationDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _scannerController;
  String _statusMessage = 'Inicializando verificacion...';
  bool _isChecking = true;
  bool _isValid = false;
  double _confidence = 0.0;
  String _reason = '';
  String _category = 'Desconocido';
  String? _descriptionReformulada;

  final List<String> _loadingMessages = [
    'Conectando con Ruteando AI...',
    'Extrayendo metadatos de la imagen...',
    'Analizando composición y coherencia física...',
    'Detectando patrones de moiré y reflejos de pantalla...',
    'Comprobando integridad contra re-fotografías...',
    'Buscando elementos de infraestructura vial...',
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

    // 1. Extraer metadatos EXIF
    Map<String, String> exifMetadata = {};
    try {
      final tags = await readExifFromBytes(widget.imageBytes);
      if (tags.isNotEmpty) {
        if (tags.containsKey('Image Make')) {
          exifMetadata['Make'] = tags['Image Make']!.toString();
        }
        if (tags.containsKey('Image Model')) {
          exifMetadata['Model'] = tags['Image Model']!.toString();
        }
        if (tags.containsKey('Image DateTime')) {
          exifMetadata['DateTime'] = tags['Image DateTime']!.toString();
        }
        if (tags.containsKey('EXIF DateTimeOriginal')) {
          exifMetadata['DateTimeOriginal'] = tags['EXIF DateTimeOriginal']!.toString();
        }
        if (tags.containsKey('Image Software')) {
          exifMetadata['Software'] = tags['Image Software']!.toString();
        }
      }
    } catch (e) {
      debugPrint('Error leyendo EXIF en Dialog: $e');
    }

    // 2. Validaciones locales de metadatos (Filtros Anti-Spam / Anti-Captura)
    final lowerFileName = widget.fileName.toLowerCase();
    if (lowerFileName.contains('screenshot') || 
        lowerFileName.contains('pantallazo') || 
        lowerFileName.contains('screen_shot') || 
        lowerFileName.contains('screen-shot')) {
      exifMetadata['ALERTA LOCAL'] = 'Nombre de archivo sospechoso de ser captura de pantalla.';
    }

    if (exifMetadata.containsKey('DateTimeOriginal')) {
      try {
        final dtStr = exifMetadata['DateTimeOriginal']!;
        // Formato típico de EXIF: YYYY:MM:DD HH:MM:SS
        final parts = dtStr.split(' ');
        if (parts.length == 2) {
          final dateParts = parts[0].split(':');
          final timeParts = parts[1].split(':');
          if (dateParts.length == 3 && timeParts.length == 3) {
            final photoDate = DateTime(
              int.parse(dateParts[0]),
              int.parse(dateParts[1]),
              int.parse(dateParts[2]),
              int.parse(timeParts[0]),
              int.parse(timeParts[1]),
              int.parse(timeParts[2]),
            );
            final diff = DateTime.now().difference(photoDate).abs();
            if (diff.inMinutes > 30) {
              exifMetadata['ADVERTENCIA LOCAL'] = 'La fecha de la fotografia (${diff.inMinutes} mins de antiguedad) no coincide con una toma en tiempo real.';
            }
          }
        }
      } catch (_) {}
    }

    // 3. Enviar a Gemini con los metadatos y prompts antifraude
    final result = await GeminiService().verifyImage(
      widget.imageBytes,
      widget.mimeType,
      widget.category,
      widget.description,
      exifMetadata: exifMetadata,
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
      _descriptionReformulada = result['descripcion_reformulada'];
    });
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
                const SizedBox(height: 24),
                InteractiveScale(
                  onTap: () {
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
                      description: _descriptionReformulada,
                    );

                    Navigator.pop(context);
                    widget.onSuccess(verifiedPhoto);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.positive,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        'Aceptar',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
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
