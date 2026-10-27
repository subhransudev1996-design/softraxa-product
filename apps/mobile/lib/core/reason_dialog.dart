import 'package:flutter/material.dart';

import 'i18n.dart';
import 'widgets.dart';

/// Asks to confirm an undo / reversal with a reason (at least 3 letters,
/// as the server requires). Returns the reason, or null when cancelled.
Future<String?> askReason(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  String? hint,
}) async {
  final reason = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              autofocus: true,
              decoration: InputDecoration(
                labelText: t('Reason *'),
                hintText: hint,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Cancel')),
          ),
          FilledButton(
            style: dialogActionStyle,
            onPressed: reason.text.trim().length >= 3
                ? () => Navigator.pop(ctx, true)
                : null,
            child: Text(action),
          ),
        ],
      ),
    ),
  );
  final text = reason.text.trim();
  reason.dispose();
  return ok == true ? text : null;
}
