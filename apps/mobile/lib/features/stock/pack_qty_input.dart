import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';

/// Stock typed as full packs plus loose units, in base units:
/// 30 boxes + 5 loose of a 50-piece box = 1,505. Blank counts as 0; returns
/// null when nothing (or something that isn't a number) was typed.
double? packQtyTotal(String packs, String loose, double factor) {
  final p = packs.trim().isEmpty ? 0.0 : double.tryParse(packs.trim());
  final l = loose.trim().isEmpty ? 0.0 : double.tryParse(loose.trim());
  if (p == null || l == null || p < 0 || l < 0) return null;
  if (packs.trim().isEmpty && loose.trim().isEmpty) return null;
  return p * factor + l;
}

/// Two boxes side by side, "Full box" and "Loose pcs", with the total in
/// base units underneath, so nobody has to multiply 30 × 50 by hand.
class PackQtyInput extends StatelessWidget {
  const PackQtyInput({
    super.key,
    required this.packs,
    required this.loose,
    required this.packName,
    required this.unitShort,
    required this.factor,
    this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController packs;
  final TextEditingController loose;
  final String packName; // e.g. Box
  final String unitShort; // e.g. pcs
  final double factor; // units in one pack
  final VoidCallback? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final total = packQtyTotal(packs.text, loose.text, factor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: packs,
                autofocus: autofocus,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => onChanged?.call(),
                decoration: InputDecoration(
                  labelText: t('Full {v1}', {'v1': packName}),
                  helperText: '1 $packName = ${qty(factor)} $unitShort',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: loose,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => onChanged?.call(),
                decoration: InputDecoration(
                  labelText: t('Loose {v1}', {'v1': unitShort}),
                  helperText: t('Optional'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          total == null
              ? t('Type the number of full {v1} and any loose {v2}', {
                  'v1': packName,
                  'v2': unitShort,
                })
              : t('= {v1} {v2} in all', {'v1': qty(total), 'v2': unitShort}),
          style: TextStyle(
            fontSize: 13,
            fontWeight: total == null ? FontWeight.w400 : FontWeight.w700,
            color: total == null ? AppColors.inkSoft : AppColors.green,
          ),
        ),
      ],
    );
  }
}
