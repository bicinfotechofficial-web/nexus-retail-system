import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_data/nexus_data.dart';

import '../data/providers.dart';

/// Shown on the login screen when running on fake data, so testers know
/// which accounts exist. Null in production.
final demoLoginHintProvider = Provider<String?>((ref) => null);

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The router redirects once the session stream emits.
      await ref
          .read(authServiceProvider)
          .signIn(email: _email.text, password: _password.text);
    } on DataFailure catch (e) {
      if (mounted) setState(() => _error = messageFor(e.reason));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String messageFor(FailureReason reason) => switch (reason) {
    FailureReason.invalidCredentials => 'Wrong email or password.',
    FailureReason.userDisabled => 'This account has been disabled.',
    FailureReason.noProfile => 'This account has no user profile yet.',
    FailureReason.offline =>
      'No network. The admin console needs a connection.',
    _ => 'Sign-in failed. Please try again.',
  };

  @override
  Widget build(BuildContext context) {
    final hint = ref.watch(demoLoginHintProvider);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Caramel Cottage Admin',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      key: const Key('login-email'),
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('login-password'),
                      controller: _password,
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _busy ? null : _submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      key: const Key('login-submit'),
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign in'),
                    ),
                    if (hint != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        hint,
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
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
