import 'package:flutter/material.dart';
import 'package:ruteando_bolivia/theme/app_theme.dart';
import 'package:ruteando_bolivia/features/reports/domain/models/report_category.dart';
import 'package:ruteando_bolivia/features/reports/presentation/widgets/interactive_scale.dart';

class CategoryChip extends StatelessWidget {
  final ReportCategory category;
  final bool isSelected;
  final VoidCallback onTap;

  const CategoryChip({
    super.key,
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final baseColor = category.color;
    final selectedBg = baseColor.withOpacity(isDark ? 0.15 : 0.12);
    final selectedBorder = baseColor.withOpacity(isDark ? 0.5 : 0.6);
    final selectedText = isDark ? baseColor.withOpacity(0.9) : baseColor;

    final unselectedBg = isDark ? theme.colorScheme.surface : theme.colorScheme.background;
    final unselectedBorder = theme.colorScheme.outline;
    final unselectedText = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    return InteractiveScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? selectedBg : unselectedBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? selectedBorder : unselectedBorder,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              category.icon,
              size: 20,
              color: isSelected ? selectedText : unselectedText,
            ),
            const SizedBox(width: 8),
            Text(
              category.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? selectedText : unselectedText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
