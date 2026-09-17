import 'package:flutter/material.dart';

import '../theme.dart';

class PythonOutputPanel extends StatelessWidget {
  final String output;
  final String? error;

  const PythonOutputPanel({super.key, required this.output, this.error});

  @override
  Widget build(BuildContext context) {
    final hasError = error != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasError
            ? AppColors.danger.withValues(alpha: 0.10)
            : const Color(0xFFF0F1F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasError
              ? AppColors.danger.withValues(alpha: 0.4)
              : AppColors.textMuted.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasError ? Icons.error_outline : Icons.terminal,
                size: 16,
                color: hasError ? AppColors.danger : AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                'Вывод программы',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: hasError ? AppColors.danger : AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (output.isNotEmpty)
            SelectableText(
              output,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.4,
              ),
            ),
          if (hasError)
            Text(
              error!,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.4,
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (output.isEmpty && !hasError)
            const Text(
              '(пусто)',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: AppColors.textMuted,
              ),
            ),
        ],
      ),
    );
  }
}
