import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/emulator_switch.dart';
import 'router.dart';

class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Caramel Cottage Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8D5524)),
      ),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

/// Shown while Firebase starts and a saved sign-in is restored.
class StartingApp extends StatelessWidget {
  const StartingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Caramel Cottage Admin',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(child: CircularProgressIndicator(key: Key('starting'))),
      ),
    );
  }
}

/// Shown instead of the console when Firebase or the data layer can't
/// start. Says what to do, with the technical detail underneath.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({required this.error, this.onRetry, super.key});

  final Object error;

  /// Tries the whole startup again. Hidden when null.
  final VoidCallback? onRetry;

  /// The headline for [error].
  static String messageFor(Object error) => error is EmulatorInReleaseError
      ? 'This build of the console was made for testing against the local '
            'emulator and cannot be used. Deploy a build made without '
            'USE_EMULATOR.'
      : "The console couldn't start. Check the internet connection and try "
            'again. If it keeps happening, reload the page later.';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Caramel Cottage Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8D5524)),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
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
                    SelectableText(
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
