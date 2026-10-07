import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/platform.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'app_lock.dart';

/// One line for the More screen: is the lock on, and how.
String appLockSummary(AppLockState s, {bool? desktop}) {
  if (!s.enabled) return t('Off');
  return (desktop ?? isDesktopPlatform)
      ? t('On — PIN')
      : t('On — fingerprint or screen lock');
}

/// Turn the app lock on or off, set / change the PIN (PC), and choose when
/// it locks again.
Future<void> showAppLockSettings(BuildContext context, {bool? desktop}) {
  final pc = desktop ?? isDesktopPlatform;
  return showDialog<void>(
    context: context,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final s = ref.watch(appLockProvider);
        final lock = ref.read(appLockProvider.notifier);
        return AlertDialog(
          title: Text(t('App lock')),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    key: const Key('app-lock-switch'),
                    contentPadding: EdgeInsets.zero,
                    value: s.enabled,
                    title: Text(
                      t('Lock the app'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      pc
                          ? t('Ask for a PIN to open Dukania on this computer')
                          : t(
                              'Ask for your fingerprint or the phone screen lock to open Dukania',
                            ),
                    ),
                    onChanged: (on) =>
                        on ? _turnOn(ctx, lock, pc) : _turnOff(ctx, lock, pc),
                  ),
                  if (s.enabled) ...[
                    const Divider(),
                    Text(
                      t('Lock again'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pc
                          ? t('When the computer is not used for:')
                          : t('After you leave the app:'),
                      style: TextStyle(
                        color: AppColors.inkSoft,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final sec in lockAfterChoices(desktop: pc))
                          ChoiceChip(
                            label: Text(lockAfterLabel(sec)),
                            selected: s.lockAfterSeconds == sec,
                            onSelected: (_) => lock.setLockAfter(sec),
                          ),
                      ],
                    ),
                    if (pc) ...[
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.password),
                        title: Text(t('Change PIN')),
                        onTap: () => _changePin(ctx, lock),
                      ),
                      Text(
                        t(
                          'Going away? Lock it now with the lock button at the top.',
                        ),
                        style: TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('Close')),
            ),
          ],
        );
      },
    ),
  );
}

Future<void> _turnOn(
  BuildContext context,
  AppLockNotifier lock,
  bool pc,
) async {
  if (pc) {
    final pin = await askNewPin(context);
    if (pin == null) return;
    await lock.setPin(pin);
    if (context.mounted) showSuccess(context, t('App lock is on'));
    return;
  }
  final r = await lock.enableDeviceLock();
  if (!context.mounted) return;
  switch (r) {
    case DeviceUnlockResult.ok:
      showSuccess(context, t('App lock is on'));
    case DeviceUnlockResult.noScreenLock:
      showError(
        context,
        t(
          'Set a screen lock (PIN, pattern or fingerprint) in your phone settings first.',
        ),
      );
    case DeviceUnlockResult.failed:
      break;
  }
}

/// Turning the lock off needs the PIN / fingerprint — otherwise anyone at
/// the counter could switch it off.
Future<void> _turnOff(
  BuildContext context,
  AppLockNotifier lock,
  bool pc,
) async {
  final ok = pc
      ? await _confirmPin(context, lock)
      : await lock.askDevice(t('Confirm it is you')) == DeviceUnlockResult.ok;
  if (!ok) return;
  await lock.disable();
  if (context.mounted) showSuccess(context, t('App lock is off'));
}

Future<void> _changePin(BuildContext context, AppLockNotifier lock) async {
  if (!await _confirmPin(context, lock)) return;
  if (!context.mounted) return;
  final pin = await askNewPin(context);
  if (pin == null) return;
  await lock.setPin(pin);
  if (context.mounted) showSuccess(context, t('PIN changed'));
}

Future<bool> _confirmPin(BuildContext context, AppLockNotifier lock) async {
  final pin = await _pinDialog(
    context,
    title: t('Enter your current PIN'),
    confirm: false,
  );
  if (pin == null) return false;
  if (await lock.checkPin(pin)) return true;
  if (context.mounted) showError(context, t('Wrong PIN'));
  return false;
}

/// Asks for a new 4–6 digit PIN twice. Returns it, or null when cancelled.
Future<String?> askNewPin(BuildContext context) =>
    _pinDialog(context, title: t('Set a PIN'), confirm: true);

Future<String?> _pinDialog(
  BuildContext context, {
  required String title,
  required bool confirm,
}) {
  final pin = TextEditingController();
  final again = TextEditingController();
  final formKey = GlobalKey<FormState>();
  InputDecoration deco(String label) =>
      InputDecoration(labelText: label, counterText: '');
  final formatters = [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(6),
  ];
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      void done() {
        if (formKey.currentState!.validate()) Navigator.pop(ctx, pin.text);
      }

      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 320,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (confirm)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      t(
                        '4 to 6 digits. You will need it every time you open Dukania on this computer.',
                      ),
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                    ),
                  ),
                TextFormField(
                  key: const Key('pin-field'),
                  controller: pin,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: formatters,
                  decoration: deco(t('PIN')),
                  textInputAction: confirm
                      ? TextInputAction.next
                      : TextInputAction.done,
                  onFieldSubmitted: (_) => confirm ? null : done(),
                  validator: (v) =>
                      isValidPin(v ?? '') ? null : t('Enter 4 to 6 digits'),
                ),
                if (confirm)
                  TextFormField(
                    key: const Key('pin-again-field'),
                    controller: again,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: formatters,
                    decoration: deco(t('PIN again')),
                    onFieldSubmitted: (_) => done(),
                    validator: (v) => v == pin.text
                        ? null
                        : t('The two PINs are not the same'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('Cancel')),
          ),
          FilledButton(
            key: const Key('pin-save'),
            style: dialogActionStyle,
            onPressed: done,
            child: Text(confirm ? t('Save') : t('Continue')),
          ),
        ],
      );
    },
  );
}
