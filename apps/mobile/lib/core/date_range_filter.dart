import 'package:flutter/material.dart';

import 'formatters.dart';

/// Asks for a "from date – to date" range (both days included).
Future<DateTimeRange?> pickDateRange(
  BuildContext context, {
  DateTime? from,
  DateTime? to,
}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return showDateRangePicker(
    context: context,
    firstDate: DateTime(2020),
    lastDate: today,
    initialDateRange: from != null && to != null
        ? DateTimeRange(start: from, end: to.isAfter(today) ? today : to)
        : null,
    helpText: 'Select from date and to date',
    saveText: 'Apply',
    fieldStartLabelText: 'From date',
    fieldEndLabelText: 'To date',
  );
}

/// A filter chip for a custom date range: "From – To dates" until one is
/// picked, then "01 Oct 2026 → 05 Oct 2026" with an × to clear it.
class DateRangeFilterChip extends StatelessWidget {
  const DateRangeFilterChip({
    super.key,
    required this.from,
    required this.to,
    required this.onChanged,
  });

  final DateTime? from;
  final DateTime? to;

  /// The new range, or null when cleared.
  final ValueChanged<DateTimeRange?> onChanged;

  Future<void> _pick(BuildContext context) async {
    final picked = await pickDateRange(context, from: from, to: to);
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    if (from == null || to == null) {
      return ActionChip(
        avatar: const Icon(Icons.date_range, size: 18),
        label: const Text('From – To dates'),
        onPressed: () => _pick(context),
      );
    }
    final same = DateUtils.isSameDay(from, to);
    return InputChip(
      selected: true,
      showCheckmark: false,
      avatar: const Icon(Icons.date_range, size: 18),
      label: Text(same ? dateStr(from) : '${dateStr(from)} → ${dateStr(to)}'),
      onPressed: () => _pick(context),
      onDeleted: () => onChanged(null),
    );
  }
}
