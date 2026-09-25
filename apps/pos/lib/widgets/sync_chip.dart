import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:nexus_data/nexus_data.dart';

import '../app/providers.dart';

/// ● Online / ◐ Syncing (n) / ○ Offline since HH:MM (03-SYNC §6).
class SyncChip extends ConsumerWidget {
  const SyncChip({super.key});

  static String label(SyncStatus status) => switch (status) {
    Online() => '● Online',
    Syncing(:final pending) => '◐ Syncing ($pending)',
    Offline(:final since) =>
      '○ Offline since ${DateFormat('HH:mm').format(since.toLocal())}',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).value;
    if (status == null) return const SizedBox.shrink();
    final (bg, fg) = switch (status) {
      Online() => (const Color(0xFFE3F4E1), const Color(0xFF1E6B2A)),
      Syncing() => (const Color(0xFFFFF1CC), const Color(0xFF7A5200)),
      Offline() => (const Color(0xFFFBE0DC), const Color(0xFF9B2A1C)),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Center(
        child: Container(
          key: const Key('sync-chip'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label(status),
            style: TextStyle(color: fg, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
