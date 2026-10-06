import '../../core/i18n.dart';
import 'package:flutter/material.dart';

import '../../core/approvals.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// One exception with a tick box — every one must be ticked (PD15).
class ExceptionCheckList extends StatelessWidget {
  const ExceptionCheckList({
    super.key,
    required this.exceptions,
    required this.ticked,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> exceptions;
  final Set<String> ticked;
  final void Function(String kind, bool value) onChanged;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final e in exceptions)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: ticked.contains(e['kind']),
          onChanged: (v) => onChanged(e['kind'] as String, v ?? false),
          title: Text(
            exceptionTitle(e['kind'] as String?),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(describeException(e)),
        ),
    ],
  );
}

/// The owner's own sale: they acknowledge each exception (D17) before the
/// bill is created. True = go ahead.
Future<bool> showOwnerAcknowledge(
  BuildContext context,
  List<Map<String, dynamic>> exceptions,
) async {
  final ticked = <String>{};
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final all = exceptions.every((e) => ticked.contains(e['kind']));
        return AlertDialog(
          title: Text(t('Check before billing')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('This sale breaks your shop rules. Tick each one to go ahead:')),
                const SizedBox(height: 8),
                ExceptionCheckList(
                  exceptions: exceptions,
                  ticked: ticked,
                  onChanged: (k, v) => setState(() => v ? ticked.add(k) : ticked.remove(k)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Change the sale'))),
            FilledButton(
              style: dialogActionStyle,
              onPressed: all ? () => Navigator.pop(ctx, true) : null,
              child: Text(t('Acknowledge & bill')),
            ),
          ],
        );
      },
    ),
  );
  return ok == true;
}

/// Staff: explain why the owner is needed; returns the reason to send, or
/// null if they'd rather change the sale.
Future<String?> showRequestApproval(
  BuildContext context,
  List<Map<String, dynamic>> exceptions,
) {
  final reason = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('Owner approval needed')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in exceptions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(describeException(e))),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Text(t('The sale is kept as a pending request — nothing is sold yet. Complete it once the owner approves (Approvals screen).'),
              style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: reason,
              decoration: InputDecoration(
                labelText: t('Reason (optional)'),
                hintText: t('e.g. clearance, regular customer'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Change the sale'))),
        FilledButton(
          style: dialogActionStyle,
          onPressed: () => Navigator.pop(ctx, reason.text.trim()),
          child: Text(t('Ask the owner')),
        ),
      ],
    ),
  );
}
