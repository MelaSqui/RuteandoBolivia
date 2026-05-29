import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:ruteando_bolivia/theme/app_theme.dart';
import 'package:ruteando_bolivia/features/reports/presentation/widgets/interactive_scale.dart';
import 'package:ruteando_bolivia/features/reports/domain/models/report_photo.dart';

class AnimatedPhotoCard extends StatefulWidget {
  final ReportPhoto photo;
  final VoidCallback onDelete;

  const AnimatedPhotoCard({
    super.key,
    required this.photo,
    required this.onDelete,
  });

  @override
  State<AnimatedPhotoCard> createState() => _AnimatedPhotoCardState();
}

class _AnimatedPhotoCardState extends State<AnimatedPhotoCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDelete() {
    _controller.reverse().then((_) {
      widget.onDelete();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bool isInvalid = widget.photo.isValid == false;
    final bool isValid = widget.photo.isValid == true;
    final bool isValidating = widget.photo.isValidating;

    Color borderColor = theme.colorScheme.outline;
    if (isInvalid) {
      borderColor = AppTheme.danger;
    } else if (isValid) {
      borderColor = AppTheme.positive;
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          ),
        );
      },
      child: Container(
        width: 110,
        height: 110,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor,
            width: widget.photo.isValid != null ? 2.5 : 1.5,
          ),
        ),
        child: Stack(
          children: [
            // Preview image
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 110,
                height: 110,
                child: kIsWeb
                    ? Image.network(
                        widget.photo.file.path,
                        fit: BoxFit.cover,
                      )
                    : Image.file(
                        File(widget.photo.file.path),
                        fit: BoxFit.cover,
                      ),
              ),
            ),
            
            // Validating Overlay
            if (isValidating)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Analizando...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Delete Button (only if not currently validating)
            if (!isValidating)
              Positioned(
                top: 6,
                right: 6,
                child: InteractiveScale(
                  onTap: _handleDelete,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

            // Success Badge
            if (isValid && !isValidating)
              Positioned(
                bottom: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: AppTheme.positive,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),

            // Rejection Badge
            if (isInvalid && !isValidating)
              Positioned(
                bottom: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: AppTheme.danger,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
