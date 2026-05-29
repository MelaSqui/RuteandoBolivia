import 'package:flutter/material.dart';
import 'package:ruteando_bolivia/theme/app_theme.dart';
import 'package:ruteando_bolivia/features/reports/domain/models/report_category.dart';
import 'package:ruteando_bolivia/features/reports/presentation/widgets/interactive_scale.dart';

class CategoryChip extends StatelessWidget {
  final ReportCategory category;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback onTap;

  const CategoryChip({
    super.key,
    required this.category,
    required this.isSelected,
    this.isDisabled = false,
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

    Color bg = isSelected ? selectedBg : unselectedBg;
    Color border = isSelected ? selectedBorder : unselectedBorder;
    Color text = isSelected ? selectedText : unselectedText;

    if (isDisabled && !isSelected) {
      bg = isDark
          ? theme.colorScheme.surface.withOpacity(0.4)
          : theme.colorScheme.background.withOpacity(0.4);
      border = unselectedBorder.withOpacity(0.3);
      text = text.withOpacity(0.4);
    }

    return InteractiveScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: border,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              category.icon,
              size: 20,
              color: text,
            ),
            const SizedBox(width: 8),
            Text(
              category.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
