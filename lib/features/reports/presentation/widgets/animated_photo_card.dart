import 'package:flutter/material.dart';
import 'package:ruteando_bolivia/theme/app_theme.dart';
import 'package:ruteando_bolivia/features/reports/domain/models/mock_photo.dart';
import 'package:ruteando_bolivia/features/reports/presentation/widgets/interactive_scale.dart';

class AnimatedPhotoCard extends StatefulWidget {
  final MockPhoto photo;
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
    final isDark = theme.brightness == Brightness.dark;

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
          color: widget.photo.tintColor.withOpacity(isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.photo.tintColor.withOpacity(isDark ? 0.3 : 0.4),
            width: 1.5,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.photo.icon,
                    size: 32,
                    color: widget.photo.tintColor,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      widget.photo.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
          ],
        ),
      ),
    );
  }
}
