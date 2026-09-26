import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../common/dialogs.dart';
import '../common/format.dart';
import '../data/providers.dart';

/// The registered devices of one location.
final devicesProvider = StreamProvider.family<List<Device>, String>(
  (ref, locationId) => ref
      .watch(deviceServiceProvider)
      .watchDevices(locationId)
      .map((l) => [...l]..sort((a, b) => a.code.compareTo(b.code))),
);

/// Devices per location with when each was last seen, and retiring one.
/// The router guards the page with `location.manage`.
class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  String? _location;

  Future<void> _retire(String locationId, Device d) async {
    final ok = await confirmAction(
      context,
      title: 'Retire ${d.code} (${d.label})?',
      message:
          'Retire a device that is lost, replaced or reset. Its code is '
          'never reused; a reinstalled phone registers again with a new '
          'code. Bills it already made stay in the reports.',
      confirmLabel: 'Retire',
    );
    if (!ok || !mounted) return;
    try {
      await ref
          .read(deviceServiceProvider)
          .retire(locationId: locationId, deviceId: d.code);
      if (mounted) showMessage(context, '$locationId ${d.code} is retired.');
    } on Object catch (e) {
      if (mounted) showMessage(context, failureMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final locations = [
      for (final l in ref.watch(locationsProvider).value ?? const <Location>[])
        if (session != null && session.canAt(Permission.locationManage, l.code))
          l,
    ]..sort((a, b) => a.code.compareTo(b.code));
    if (locations.isEmpty) {
      return const Center(child: Text('No locations yet.'));
    }
    final switcher = ref.watch(selectedLocationProvider);
    final code =
        [_location, switcher].nonNulls
            .where((c) => locations.any((l) => l.code == c))
            .firstOrNull ??
        locations.first.code;
    final now = ref.watch(clockProvider)();
    final async = ref.watch(devicesProvider(code));
    final devices = async.value;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Devices', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 260,
            // Rebuilt when the location changes from outside, e.g. the
            // top-bar switcher.
            key: ValueKey(code),
            child: DropdownButtonFormField<String>(
              key: const Key('devices-location'),
              initialValue: code,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Location'),
              items: [
                for (final l in locations)
                  DropdownMenuItem(
                    value: l.code,
                    child: Text('${l.name} (${l.code})'),
                  ),
              ],
              onChanged: (v) => setState(() => _location = v),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (devices == null)
          async.hasError
              ? Text('Could not load devices: ${async.error}')
              : const Center(child: CircularProgressIndicator())
        else if (devices.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'No devices yet. A Store Manager registers each phone from '
              'the POS app.',
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              key: const Key('devices-table'),
              columnSpacing: 32,
              columns: const [
                DataColumn(label: Text('Code')),
                DataColumn(label: Text('Label')),
                DataColumn(label: Text('Last seen')),
                DataColumn(label: Text('Registered')),
                DataColumn(label: Text('Last bill'), numeric: true),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('')),
              ],
              rows: [
                for (final d in devices)
                  DataRow(
                    cells: [
                      DataCell(Text(d.code, key: Key('device-${d.code}'))),
                      DataCell(Text(d.label)),
                      DataCell(
                        Tooltip(
                          message: d.lastSeenAt == null
                              ? 'Not seen online since it registered'
                              : formatInstantIst(d.lastSeenAt!),
                          child: Text(
                            d.lastSeenAt == null
                                ? 'Never'
                                : formatAgo(d.lastSeenAt!, now),
                            key: Key('seen-${d.code}'),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          d.registeredAt == null
                              ? '–'
                              : formatInstantIst(d.registeredAt!),
                        ),
                      ),
                      DataCell(
                        Text(
                          d.lastBillSeq == 0
                              ? 'None'
                              : Ids.billNo(
                                  code,
                                  Ids.billId(d.code, d.lastBillSeq),
                                ),
                        ),
                      ),
                      DataCell(
                        Text(
                          d.retired ? 'Retired' : 'Active',
                          key: Key('device-status-${d.code}'),
                        ),
                      ),
                      DataCell(
                        !d.retired &&
                                (session?.canAt(
                                      Permission.locationManage,
                                      code,
                                    ) ??
                                    false)
                            ? TextButton(
                                key: Key('retire-${d.code}'),
                                onPressed: () => _retire(code, d),
                                child: const Text('Retire'),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
