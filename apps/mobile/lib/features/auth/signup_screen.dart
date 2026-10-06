import '../../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth_links.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../../core/theme.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  // Non-null once signup succeeds and a verification email was sent — the
  // screen then shows a "check your email" panel instead of the form.
  String? _signedUpEmail;

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final email = _email.text.trim();
      final res = await ref
          .read(supabaseProvider)
          .auth
          .signUp(
            email: email,
            password: _password.text,
            data: {'full_name': _name.text.trim()},
            emailRedirectTo: authCallbackUrl,
          );
      if (mounted && res.session == null) {
        // Email confirmation is enabled — show the verify panel.
        setState(() => _signedUpEmail = email);
      }
      // If session != null the router redirects to business setup.
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final email = _signedUpEmail;
    if (email == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(supabaseProvider)
          .auth
          .resend(
            type: OtpType.signup,
            email: email,
            emailRedirectTo: authCallbackUrl,
          );
      if (mounted) showSuccess(context, 'Verification email sent to $email.');
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
      appBar: AppBar(title: Text(t('Create account'))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: _signedUpEmail != null
                  ? _VerifyPanel(
                      email: _signedUpEmail!,
                      busy: _busy,
                      onResend: _resend,
                      onGoToLogin: () => context.go('/login'),
                    )
                  : Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _name,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: t('Your name'),
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Enter your name'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: t('Email'),
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: (v) => v == null || !v.contains('@')
                                ? 'Enter a valid email'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                              labelText: t('Password'),
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) => v == null || v.length < 6
                                ? 'Minimum 6 characters'
                                : null,
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: _busy ? null : _signup,
                            child: _busy
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(t('Sign up')),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown after a successful signup: tells the user to check their inbox,
/// with a resend button and a route back to login.
class _VerifyPanel extends StatelessWidget {
  const _VerifyPanel({
    required this.email,
    required this.busy,
    required this.onResend,
    required this.onGoToLogin,
  });

  final String email;
  final bool busy;
  final VoidCallback onResend;
  final VoidCallback onGoToLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.mark_email_read_outlined,
          size: 64,
          color: AppColors.primary,
        ),
        const SizedBox(height: 20),
        Text(t('Check your email'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        Text(
          'We sent a verification link to\n$email\n\n'
          'Open it to activate your account, then log in. '
          'It may take a minute — remember to check your spam folder.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.inkSoft, height: 1.5),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: busy ? null : onGoToLogin,
          child: Text(t('Go to login')),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: busy ? null : onResend,
          child: busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(t('Resend verification email')),
        ),
      ],
    );
  }
}
