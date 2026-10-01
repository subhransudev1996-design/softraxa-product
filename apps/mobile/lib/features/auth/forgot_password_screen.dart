import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth_links.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Password reset — request step. The user enters their email and we send a
/// reset link via Supabase (delivered through Resend). When they open the
/// link, Supabase fires a passwordRecovery auth event and the app shows the
/// "set a new password" step (handled here so the whole flow is one screen).
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;

  Future<void> _sendReset() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      showError(context, 'Enter a valid email');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(supabaseProvider)
          .auth
          .resetPasswordForEmail(email, redirectTo: authCallbackUrl);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Reset password'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: _sent ? _sentPanel() : _requestPanel(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _requestPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.lock_reset, size: 64, color: AppColors.primary),
        const SizedBox(height: 20),
        Text(
          'Forgot your password?',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        Text(
          'Enter your account email and we\'ll send you a link to set a new '
          'password.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.inkSoft, height: 1.5),
        ),
        const SizedBox(height: 28),
        TextFormField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.email_outlined),
          ),
          onFieldSubmitted: (_) => _sendReset(),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _sendReset,
          child: _busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send reset link'),
        ),
      ],
    );
  }

  Widget _sentPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.mark_email_read_outlined,
          size: 64,
          color: AppColors.primary,
        ),
        const SizedBox(height: 20),
        Text(
          'Check your email',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        Text(
          'If an account exists for ${_email.text.trim()}, we\'ve sent a '
          'password reset link. Open it to set a new password.\n\n'
          'Check your spam folder if you don\'t see it.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.inkSoft, height: 1.5),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () => context.go('/login'),
          child: const Text('Back to login'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _sendReset,
          child: const Text('Resend link'),
        ),
      ],
    );
  }
}

/// The "set a new password" step, shown when Supabase fires a
/// passwordRecovery event (user tapped the reset link). Presented as a
/// dialog from wherever the app currently is.
Future<void> showSetNewPasswordDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final controller = TextEditingController();
  bool busy = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Set a new password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New password (min 6 characters)',
          ),
        ),
        actions: [
          FilledButton(
            style: dialogActionStyle,
            onPressed: busy
                ? null
                : () async {
                    if (controller.text.length < 6) return;
                    setLocal(() => busy = true);
                    try {
                      await ref
                          .read(supabaseProvider)
                          .auth
                          .updateUser(
                            UserAttributes(password: controller.text),
                          );
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        showSuccess(
                          ctx,
                          'Password updated. You\'re signed in.',
                        );
                      }
                    } catch (e) {
                      if (ctx.mounted) showError(ctx, e);
                      setLocal(() => busy = false);
                    }
                  },
            child: busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Update password'),
          ),
        ],
      ),
    ),
  );
}
