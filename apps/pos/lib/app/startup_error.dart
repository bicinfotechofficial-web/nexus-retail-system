import 'package:flutter/material.dart';

import 'emulator_switch.dart';
import 'theme.dart';

/// Shown instead of the POS when Firebase or the data layer can't start.
/// Says what to do in shop terms, with the technical detail underneath for
/// whoever supports the device.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({required this.error, this.onRetry, super.key});

  final Object error;

  /// Tries the whole startup again. Hidden when null.
  final VoidCallback? onRetry;

  /// The headline for [error].
  static String messageFor(Object error) => error is EmulatorInReleaseError
      ? 'This copy of the app was built for testing and cannot be used in '
            'the shop. Ask the Admin for the shop version.'
      : "The app couldn't start. Check that the phone is connected to the "
            'internet, then tap Try again. If it keeps happening, call the '
            'Admin.';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Caramel Cottage POS',
      debugShowCheckedModeBanner: false,
      theme: PosTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 56,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      messageFor(error),
                      key: const Key('startup-error'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (onRetry != null && error is! EmulatorInReleaseError)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: FilledButton.icon(
                          key: const Key('startup-retry'),
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try again'),
                        ),
                      ),
                    const SizedBox(height: 32),
                    Text(
                      '$error',
                      key: const Key('startup-error-detail'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
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
