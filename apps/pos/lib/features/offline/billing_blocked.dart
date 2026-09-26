import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../../app/destinations.dart';
import '../../app/messages.dart';
import '../../app/providers.dart';

/// Shows [child] unless the offline limit blocks billing (`BillingBlocked`),
/// in which case it shows the block screen. Only billing pages use it, so
/// stock operations and viewing keep working (03-SYNC §7).
class BillingGate extends ConsumerWidget {
  const BillingGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(offlineViewProvider.select((v) => v.blocked));
    return blocked ? const BillingBlockedView() : child;
  }
}

/// Billing is paused: Retry sync, or an Admin PIN override (D-016).
class BillingBlockedView extends ConsumerStatefulWidget {
  const BillingBlockedView({super.key});

  @override
  ConsumerState<BillingBlockedView> createState() => _BillingBlockedViewState();
}

class _BillingBlockedViewState extends ConsumerState<BillingBlockedView> {
  final _pin = TextEditingController();
  bool _syncing = false;
  bool _retried = false;
  bool _checking = false;
  String? _pinError;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _retried = false;
    });
    try {
      await ref.read(syncServiceProvider).syncNow();
    } catch (_) {
      // Shown below as "still offline".
    }
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _retried = true;
    });
  }

  Future<void> _override() async {
    if (_checking) return;
    final pin = _pin.text.trim();
    if (pin.length < Limits.minOverridePinDigits) {
      setState(
        () => _pinError =
            'The override PIN has at least ${Limits.minOverridePinDigits} '
            'digits.',
      );
      return;
    }
    setState(() {
      _checking = true;
      _pinError = null;
    });
    final bool ok;
    try {
      ok = await ref.read(offlineGuardProvider).override(pin);
    } on DataFailure catch (e) {
      _pinFailed(Messages.failure(e));
      return;
    } catch (_) {
      _pinFailed(Messages.failure(const DataFailure(FailureReason.unknown)));
      return;
    }
    if (!ok) {
      _pinFailed('Wrong PIN. Billing stays paused.');
      return;
    }
    if (!mounted) return;
    final location = ref.read(sessionProvider).value?.location;
    final hours =
        location?.overrideExtensionHours ??
        Location.defaultOverrideExtensionHours;
    final until = ref.read(clockProvider)().add(Duration(hours: hours));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('override-ok'),
          content: Text(
            'Billing allowed until '
            '${DateFormat('HH:mm').format(until.toLocal())}. '
            'Connect to the internet before then.',
          ),
        ),
      );
    _pin.clear();
    setState(() => _checking = false);
  }

  void _pinFailed(String message) {
    if (!mounted) return;
    _pin.clear();
    setState(() {
      _checking = false;
      _pinError = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider).value;
    final location = session?.location;
    final limit =
        location?.offlineLimitHours ?? Location.defaultOfflineLimitHours;
    final last = ref.read(syncServiceProvider).lastSyncAt;
    final since = last == null
        ? ''
        : ' (last sync ${DateFormat('HH:mm, d MMM').format(last.toLocal())})';
    return SingleChildScrollView(
      key: const Key('billing-blocked'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.cloud_off, size: 56, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(
            'Billing is paused',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            "This device hasn't synced for $limit hours$since. Connect to the "
            'internet and retry, or ask the Admin for the override PIN. '
            'Stock and past bills still work.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('retry-sync'),
            onPressed: _syncing ? null : _retry,
            icon: _syncing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: const Text('Retry sync'),
          ),
          if (_retried)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Still not synced. Check the internet connection and try '
                'again.',
                key: const Key('retry-result'),
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 28),
          Text('Admin PIN override', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            key: const Key('override-pin'),
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Override PIN',
              errorText: _pinError,
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => _override(),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('override-submit'),
            onPressed: _checking ? null : _override,
            child: const Text('Allow billing'),
          ),
          if (session != null && Destinations.stock.allowedFor(session)) ...[
            const SizedBox(height: 20),
            TextButton(
              key: const Key('open-stock'),
              onPressed: () => context.go(Destinations.stock.path),
              child: const Text('Go to Stock'),
            ),
          ],
        ],
      ),
    );
  }
}
