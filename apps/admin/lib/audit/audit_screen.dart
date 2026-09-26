import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../common/dialogs.dart';
import '../common/format.dart';
import '../data/providers.dart';
import 'audit_diff.dart';

/// The audit log filters. Dates are IST business dates, both inclusive.
final class AuditFilter {
  const AuditFilter({
    this.locationId,
    this.userId,
    this.action,
    this.fromDate,
    this.toDate,
  });

  /// How many entries one query returns, newest first.
  static const int pageSize = 100;

  final String? locationId;
  final String? userId;
  final AuditAction? action;

  /// `YYYY-MM-DD`; null for no bound.
  final String? fromDate;
  final String? toDate;

  bool get isEmpty =>
      locationId == null &&
      userId == null &&
      action == null &&
      fromDate == null &&
      toDate == null;

  /// The query: from the IST midnight that starts [fromDate] up to the
  /// last instant of [toDate] in IST (D-022).
  AuditQuery toQuery() => AuditQuery(
    locationId: locationId,
    userId: userId,
    action: action,
    from: fromDate == null ? null : BusinessDate.startOf(fromDate!),
    to: toDate == null
        ? null
        : BusinessDate.startOf(
            BusinessDate.addDays(toDate!, 1),
          ).subtract(const Duration(microseconds: 1)),
    limit: pageSize,
  );

  AuditFilter copyWith({
    String? Function()? locationId,
    String? Function()? userId,
    AuditAction? Function()? action,
    (String, String)? Function()? dates,
  }) {
    final d = dates == null ? (fromDate, toDate) : dates();
    return AuditFilter(
      locationId: locationId == null ? this.locationId : locationId(),
      userId: userId == null ? this.userId : userId(),
      action: action == null ? this.action : action(),
      fromDate: d?.$1,
      toDate: d?.$2,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AuditFilter &&
      other.locationId == locationId &&
      other.userId == userId &&
      other.action == action &&
      other.fromDate == fromDate &&
      other.toDate == toDate;

  @override
  int get hashCode => Object.hash(locationId, userId, action, fromDate, toDate);
}

final auditFilterProvider = NotifierProvider<AuditFilterNotifier, AuditFilter>(
  AuditFilterNotifier.new,
);

class AuditFilterNotifier extends Notifier<AuditFilter> {
  @override
  AuditFilter build() => const AuditFilter();

  void set(AuditFilter filter) => state = filter;
}

/// The entries matching the filters, newest first (`audit.view`).
final auditEntriesProvider = FutureProvider.autoDispose<List<AuditEntry>>(
  (ref) => ref
      .watch(auditRepositoryProvider)
      .query(ref.watch(auditFilterProvider).toQuery()),
);

/// Every user, for the user filter and for names in the list.
final auditUsersProvider = StreamProvider<List<AppUser>>(
  (ref) => ref.watch(userRepositoryProvider).watchUsers(),
);

class AuditScreen extends ConsumerWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final filter = ref.watch(auditFilterProvider);
    final notifier = ref.read(auditFilterProvider.notifier);
    final locations = [...?ref.watch(locationsProvider).value]
      ..sort((a, b) => a.code.compareTo(b.code));
    final users = [...?ref.watch(auditUsersProvider).value]
      ..sort((a, b) => a.name.compareTo(b.name));
    final names = {for (final u in users) u.uid: u.name};
    final async = ref.watch(auditEntriesProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Audit log', style: theme.textTheme.headlineSmall),
        Text(
          'Newest first. Times are IST. Select an entry to see what changed.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Filter<String?>(
              filterKey: const Key('audit-location'),
              label: 'Location',
              value: filter.locationId,
              items: {
                null: 'All locations',
                for (final l in locations) l.code: locationLabel(l),
              },
              onChanged: (v) =>
                  notifier.set(filter.copyWith(locationId: () => v)),
            ),
            _Filter<String?>(
              filterKey: const Key('audit-user'),
              label: 'User',
              value: filter.userId,
              items: {
                null: 'All users',
                for (final u in users) u.uid: '${u.name} (${u.email})',
              },
              onChanged: (v) => notifier.set(filter.copyWith(userId: () => v)),
            ),
            _Filter<AuditAction?>(
              filterKey: const Key('audit-action'),
              label: 'Action',
              value: filter.action,
              items: {
                null: 'All actions',
                for (final a in AuditAction.values) a: auditActionLabel(a),
              },
              onChanged: (v) => notifier.set(filter.copyWith(action: () => v)),
            ),
            OutlinedButton.icon(
              key: const Key('audit-dates'),
              icon: const Icon(Icons.date_range_outlined, size: 18),
              label: Text(
                filter.fromDate == null
                    ? 'Any date'
                    : '${formatBusinessDate(filter.fromDate!)} – '
                          '${formatBusinessDate(filter.toDate!)}',
              ),
              onPressed: () => _pickDates(context, ref, filter),
            ),
            if (!filter.isEmpty)
              TextButton(
                key: const Key('audit-clear'),
                onPressed: () => notifier.set(const AuditFilter()),
                child: const Text('Clear filters'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        switch (async) {
          AsyncData(:final value) => _Entries(
            entries: value,
            names: names,
            full: value.length >= AuditFilter.pageSize,
          ),
          AsyncError(:final error) => Text(
            'Could not load the audit log: ${failureMessage(error)}',
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ],
    );
  }

  Future<void> _pickDates(
    BuildContext context,
    WidgetRef ref,
    AuditFilter filter,
  ) async {
    final today = ref.read(todayProvider);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: pickerDate(today),
      // "Today" is the IST date, whatever the browser's zone.
      currentDate: pickerDate(today),
      initialDateRange: filter.fromDate == null
          ? null
          : DateTimeRange(
              start: pickerDate(filter.fromDate!),
              end: pickerDate(filter.toDate!),
            ),
    );
    if (picked == null) return;
    ref
        .read(auditFilterProvider.notifier)
        .set(
          filter.copyWith(
            dates: () => (
              businessDateOfPicked(picked.start),
              businessDateOfPicked(picked.end),
            ),
          ),
        );
  }
}

class _Filter<T> extends StatelessWidget {
  const _Filter({
    required this.filterKey,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final Key filterKey;
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: filterKey,
      width: 240,
      child: DropdownButtonFormField<T>(
        // Rebuilt when "Clear filters" resets the value from outside.
        key: ValueKey<Object?>(value),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final e in items.entries)
            DropdownMenuItem<T>(
              value: e.key,
              child: Text(e.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => onChanged(v as T),
      ),
    );
  }
}

class _Entries extends StatelessWidget {
  const _Entries({
    required this.entries,
    required this.names,
    required this.full,
  });

  final List<AuditEntry> entries;
  final Map<String, String> names;
  final bool full;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No audit entries match these filters.',
          key: Key('audit-empty'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            key: const Key('audit-table'),
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('When (IST)')),
              DataColumn(label: Text('Action')),
              DataColumn(label: Text('Location')),
              DataColumn(label: Text('User')),
              DataColumn(label: Text('Record')),
              DataColumn(label: Text('Reason')),
            ],
            rows: [
              for (final e in entries)
                DataRow(
                  key: ValueKey('audit-${e.id}'),
                  onSelectChanged: (_) => showAuditEntry(context, e, names),
                  cells: [
                    DataCell(Text(formatInstantIst(e.at ?? e.clientAt))),
                    DataCell(
                      Text(
                        auditActionLabel(e.action),
                        key: Key('audit-action-${e.id}'),
                      ),
                    ),
                    DataCell(Text(e.locationId ?? '—')),
                    DataCell(Text(names[e.by] ?? e.by)),
                    DataCell(Text(e.entityPath)),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: Text(
                          e.reason ?? '',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        if (full)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Showing the newest ${AuditFilter.pageSize}. Narrow the filters '
              'to see older entries.',
              key: const Key('audit-truncated'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

/// The entry's details and its before/after diff.
Future<void> showAuditEntry(
  BuildContext context,
  AuditEntry entry,
  Map<String, String> names,
) => showDialog<void>(
  context: context,
  builder: (context) => AuditEntryDialog(entry: entry, names: names),
);

class AuditEntryDialog extends StatelessWidget {
  const AuditEntryDialog({required this.entry, required this.names, super.key});

  final AuditEntry entry;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = entry;
    final rows = auditDiff(e.before, e.after);
    Widget meta(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );

    return AlertDialog(
      title: Text(
        '${auditActionLabel(e.action)} · '
        '${formatInstantIst(e.at ?? e.clientAt)}',
      ),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              meta('Record', e.entityPath),
              meta('By', '${names[e.by] ?? e.by} (${e.by})'),
              if (e.locationId != null) meta('Location', e.locationId!),
              if (e.deviceId != null) meta('Device', e.deviceId!),
              if (e.reason != null) meta('Reason', e.reason!),
              meta('Audit ID', e.id),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                const Text('No before or after values were recorded.')
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    key: const Key('audit-diff'),
                    columns: const [
                      DataColumn(label: Text('Field')),
                      DataColumn(label: Text('Before')),
                      DataColumn(label: Text('After')),
                      DataColumn(label: Text('')),
                    ],
                    rows: [for (final r in rows) _diffRow(theme, r)],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('audit-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  static DataRow _diffRow(ThemeData theme, DiffRow r) {
    final scheme = theme.colorScheme;
    final changed = r.kind != DiffKind.unchanged;
    final (label, color) = switch (r.kind) {
      DiffKind.added => ('added', scheme.primary),
      DiffKind.removed => ('removed', scheme.error),
      DiffKind.changed => ('changed', scheme.tertiary),
      DiffKind.unchanged => ('', scheme.onSurface),
    };
    final style = changed ? const TextStyle(fontWeight: FontWeight.bold) : null;
    return DataRow(
      key: ValueKey('diff-${r.path}'),
      color: changed
          ? WidgetStatePropertyAll(scheme.secondaryContainer.withAlpha(90))
          : null,
      cells: [
        DataCell(Text(r.path, style: style)),
        DataCell(
          Text(
            formatDiffValue(r.path, r.before),
            key: Key('diff-${r.path}-before'),
          ),
        ),
        DataCell(
          Text(
            formatDiffValue(r.path, r.after),
            key: Key('diff-${r.path}-after'),
            style: style,
          ),
        ),
        DataCell(
          Text(
            label,
            key: Key('diff-${r.path}-kind'),
            style: TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}
