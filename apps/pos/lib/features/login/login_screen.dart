import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_data/nexus_data.dart';

import '../../app/messages.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';

/// Sign-in (POS-2). `AuthService.signIn` also prefetches the user, role,
/// location, catalog and raw materials (03-SYNC §8), so billing works
/// offline afterwards. The router moves on when the session arrives.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  /// The sign-in failure, worded for this screen.
  static String message(DataFailure failure) => switch (failure.reason) {
    FailureReason.offline =>
      'Signing in on this device needs an internet connection the first '
          'time. Connect to Wi-Fi or mobile data and try again.',
    _ => Messages.failure(failure),
  };

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _ready => _email.text.trim().isNotEmpty && _password.text.isNotEmpty;

  Future<void> _signIn() async {
    if (_busy || !_ready) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          .signIn(email: _email.text.trim(), password: _password.text);
    } on DataFailure catch (e) {
      _failed(LoginScreen.message(e));
      return;
    } catch (_) {
      _failed(Messages.failure(const DataFailure(FailureReason.unknown)));
      return;
    }
    // Success: the session stream sends the router home.
    if (mounted) setState(() => _busy = false);
  }

  void _failed(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
      _password.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.cake, size: 64, color: PosTheme.caramel),
                    const SizedBox(height: 8),
                    Text(
                      'Caramel Cottage',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: PosTheme.cocoa,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text('Sign in', textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    TextField(
                      key: const Key('login-email'),
                      controller: _email,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Email'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('login-password'),
                      controller: _password,
                      enabled: !_busy,
                      obscureText: !_showPassword,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          tooltip: _showPassword
                              ? 'Hide password'
                              : 'Show password',
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _signIn(),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error!,
                          key: const Key('login-error'),
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      key: const Key('sign-in'),
                      onPressed: _busy || !_ready ? null : _signIn,
                      child: const Text('Sign in'),
                    ),
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: Row(
                          key: Key('login-busy'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Flexible(
                              child: Text('Signing in and loading your store…'),
                            ),
                          ],
                        ),
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
