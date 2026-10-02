import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings.dart';
import '../../widgets/pos_scaffold.dart';

/// Settings kept on this phone for the signed-in user (POS-16).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final review = reviewIsOn(ref);
    return PosScaffold(
      title: 'Settings',
      body: ListView(
        children: [
          SwitchListTile(
            key: const Key('review-switch'),
            value: review,
            onChanged: (v) =>
                ref.read(reviewBeforeSaveProvider.notifier).set(v),
            title: const Text('Review bill before saving'),
            subtitle: const Text(
              'Shows the customer, items and payment once more before the '
              'bill is saved. A saved bill can only be cancelled, not '
              'edited. Kept on this phone for your login.',
            ),
          ),
        ],
      ),
    );
  }
}
