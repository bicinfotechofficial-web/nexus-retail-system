import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:nexus_data/nexus_data.dart';

import '../../app/providers.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/pos_scaffold.dart';
import '../../widgets/section_card.dart';
import '../../widgets/sync_chip.dart';
import '../../widgets/total_row.dart';

/// Sync health (03-SYNC §6): the connection, the last completed sync, the
/// offline limit, and every write the server rejected.
class SyncHealthScreen extends ConsumerStatefulWidget {
  const SyncHealthScreen({super.key});

  @override
  ConsumerState<SyncHealthScreen> createState() => _SyncHealthScreenState();
}

class _SyncHealthScreenState extends ConsumerState<SyncHealthScreen> {
  bool _syncing = false;

  static final DateFormat _when = DateFormat('HH:mm, d MMM');

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await ref.read(syncServiceProvider).syncNow();
    } catch (_) {
      // The status and last sync below show the outcome.
    }
    if (mounted) setState(() => _syncing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = ref.watch(syncStatusProvider).value;
    final offline = ref.watch(offlineViewProvider);
    final errors = ref.watch(syncErrorsProvider).value ?? const <SyncError>[];
    final last = ref.read(syncServiceProvider).lastSyncAt;
    final now = ref.read(clockProvider)();
    final limitText = switch (offline.state) {
      WithinLimit() => 'Billing allowed',
      NearLimit() =>
        'Billing stops in '
            '${formatCountdown(offline.deadline!.difference(now))}',
      BillingBlocked() => 'Billing paused until a sync or a PIN override',
    };

    return PosScaffold(
      title: 'Sync health',
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SectionCard(
            title: 'This device',
            children: [
              TotalRow(
                'Connection',
                status == null ? '…' : SyncChip.label(status),
              ),
              TotalRow(
                'Last sync',
                last == null ? 'Not yet' : _when.format(last.toLocal()),
                key: const Key('last-sync'),
              ),
              TotalRow('Offline limit', limitText, key: const Key('limit')),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('sync-now'),
                onPressed: _syncing ? null : _syncNow,
                icon: _syncing
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: const Text('Sync now'),
              ),
            ],
          ),
          SectionCard(
            title: 'Sync errors (${errors.length})',
            children: [
              if (errors.isEmpty)
                const Text('No sync errors.', key: Key('no-sync-errors'))
              else ...[
                Text(
                  'The server refused these writes, so they are not saved. '
                  'Re-enter each one, and tell the Admin: it is always a bug.',
                  style: theme.textTheme.bodySmall,
                ),
                for (final (i, e) in errors.indexed)
                  ListTile(
                    key: Key('sync-error-$i'),
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.error_outline,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(e.path),
                    subtitle: Text(
                      '${e.detail}\n${_when.format(e.at.toLocal())}',
                    ),
                    isThreeLine: true,
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
