import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../common/format.dart';
import '../common/store_picker.dart';
import '../data/providers.dart';
import '../staff/staff_screen.dart';

/// One day's marks at every store, from one collection-group query.
final attendanceDayAllProvider =
    StreamProvider.family<List<AttendanceRecord>, String>(
      (ref, date) =>
          ref.watch(attendanceRepositoryProvider).watchDayAllLocations(date),
    );

/// One store's marks for one month (`YYYY-MM`). A month is about 30 reads per
/// staff member, so only one store is ever loaded at a time.
final attendanceMonthProvider =
    StreamProvider.family<List<AttendanceRecord>, (String, String)>(
      (ref, key) =>
          ref.watch(attendanceRepositoryProvider).watchMonth(key.$1, key.$2),
    );

/// A day count as `12` or `12.5`.
String formatDays(double days) =>
    days == days.roundToDouble() ? '${days.toInt()}' : days.toStringAsFixed(1);

String statusLabel(AttendanceStatus s) => switch (s) {
  AttendanceStatus.present => 'Present',
  AttendanceStatus.halfDay => 'Half-day',
  AttendanceStatus.absent => 'Absent',
};

String _statusLetter(AttendanceStatus s) => switch (s) {
  AttendanceStatus.present => 'P',
  AttendanceStatus.halfDay => 'H',
  AttendanceStatus.absent => 'A',
};

enum _View { daily, monthly }

/// Staff attendance across stores (D-042), read only: who was present, on
/// half-day or absent on a day, which stores have not marked, and a monthly
/// grid with totals for one store. Needs `report.all` (router guard).
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  _View _view = _View.daily;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Attendance', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Marked by each Store Manager. Read only.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        SegmentedButton<_View>(
          key: const Key('attendance-view'),
          segments: const [
            ButtonSegment(value: _View.daily, label: Text('Daily')),
            ButtonSegment(value: _View.monthly, label: Text('Monthly')),
          ],
          selected: {_view},
          onSelectionChanged: (s) => setState(() => _view = s.single),
        ),
        const SizedBox(height: 16),
        switch (_view) {
          _View.daily => const _DailyView(),
          _View.monthly => const _MonthlyView(),
        },
      ],
    );
  }
}

class _DailyView extends ConsumerStatefulWidget {
  const _DailyView();

  @override
  ConsumerState<_DailyView> createState() => _DailyViewState();
}

class _DailyViewState extends ConsumerState<_DailyView> {
  String? _date;

  Future<void> _pick(String date, String today) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: pickerDate(date),
      firstDate: DateTime(2024),
      lastDate: pickerDate(today),
    );
    if (picked != null) setState(() => _date = businessDateOfPicked(picked));
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final date = _date ?? today;
    final locations = ref.watch(locationsProvider).value;
    final marks = ref.watch(attendanceDayAllProvider(date));
    final theme = Theme.of(context);

    Widget body;
    final records = marks.value;
    if (locations == null || records == null) {
      body = marks.hasError
          ? Text('Could not load attendance: ${marks.error}')
          : const Center(child: CircularProgressIndicator());
    } else {
      final byStore = <String, List<AttendanceRecord>>{};
      for (final r in records) {
        (byStore[r.locationId ?? ''] ??= []).add(r);
      }
      // Open stores always; a closed store only when it has marks that day.
      final shown = [
        for (final l in locations)
          if (l.active || (byStore[l.code] ?? const []).isNotEmpty) l,
      ]..sort((a, b) => a.code.compareTo(b.code));
      // Stores that have staff but no marks that day. Staff counts load per
      // store, so a store still loading is not counted either way.
      var loading = false;
      final missing = <String>[];
      for (final l in shown) {
        if (!l.active || (byStore[l.code] ?? const []).isNotEmpty) continue;
        final staff = ref.watch(activeStaffProvider(l.code)).value;
        if (staff == null) {
          loading = true;
        } else if (staff.isNotEmpty) {
          missing.add(l.code);
        }
      }
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '${missing.length} ${missing.length == 1 ? 'store has' : 'stores have'} '
                'not marked ${date == today ? 'today' : 'this day'}: '
                '${missing.join(', ')}.',
                key: const Key('att-summary'),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            )
          else if (!loading && shown.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Every store has marked ${date == today ? 'today' : 'this day'}.',
                key: const Key('att-all-marked'),
                style: theme.textTheme.titleSmall,
              ),
            ),
          if (shown.isEmpty)
            const Text('There are no stores yet.')
          else
            for (final l in shown)
              _StoreDay(
                location: l,
                records: byStore[l.code] ?? const [],
                isToday: date == today,
              ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'Previous day',
              icon: const Icon(Icons.chevron_left),
              onPressed: () =>
                  setState(() => _date = BusinessDate.addDays(date, -1)),
            ),
            TextButton.icon(
              key: const Key('att-date'),
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(
                date == today
                    ? 'Today, ${formatBusinessDate(date)}'
                    : formatBusinessDate(date),
              ),
              onPressed: () => _pick(date, today),
            ),
            IconButton(
              tooltip: 'Next day',
              icon: const Icon(Icons.chevron_right),
              onPressed: date.compareTo(today) >= 0
                  ? null
                  : () => setState(() => _date = BusinessDate.addDays(date, 1)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        body,
      ],
    );
  }
}

/// One store's day: marked and active counts, the "Not marked yet" flag, and
/// the people by status.
class _StoreDay extends ConsumerWidget {
  const _StoreDay({
    required this.location,
    required this.records,
    required this.isToday,
  });

  final Location location;
  final List<AttendanceRecord> records;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final code = location.code;
    final active = ref.watch(activeStaffProvider(code)).value;
    final noStaff = active != null && active.isEmpty && records.isEmpty;
    final notMarked = active != null && !noStaff && records.isEmpty;

    final sorted = [...records]
      ..sort((a, b) => a.staffName.compareTo(b.staffName));

    return Card(
      key: Key('att-store-$code'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  locationLabel(location),
                  style: theme.textTheme.titleMedium,
                ),
                if (active != null && !noStaff)
                  Text(
                    '${records.length} of ${active.length} marked',
                    key: Key('att-count-$code'),
                    style: theme.textTheme.bodyMedium,
                  ),
                if (notMarked)
                  Chip(
                    key: Key('att-notmarked-$code'),
                    avatar: Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: scheme.onErrorContainer,
                    ),
                    label: Text(
                      'Not marked yet',
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                    backgroundColor: scheme.errorContainer,
                    side: BorderSide.none,
                  ),
                if (noStaff)
                  Text(
                    'No staff on this store\'s roster.',
                    key: Key('att-nostaff-$code'),
                    style: theme.textTheme.bodyMedium,
                  ),
              ],
            ),
            if (records.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final status in AttendanceStatus.values)
                _StatusGroup(
                  code: code,
                  status: status,
                  records: [
                    for (final r in sorted)
                      if (r.status == status) r,
                  ],
                ),
            ] else if (notMarked && isToday)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'The Store Manager has not marked anyone today.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusGroup extends StatelessWidget {
  const _StatusGroup({
    required this.code,
    required this.status,
    required this.records,
  });

  final String code;
  final AttendanceStatus status;
  final List<AttendanceRecord> records;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${statusLabel(status)} (${records.length})',
            key: Key('att-group-$code-${status.wire}'),
            style: theme.textTheme.labelLarge,
          ),
          if (records.isEmpty)
            Text('Nobody', style: theme.textTheme.bodySmall)
          else
            for (final r in records)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 2),
                child: Text(
                  r.note == null || r.note!.isEmpty
                      ? r.staffName
                      : '${r.staffName} — ${r.note}',
                  key: Key('att-person-$code-${r.staffId}'),
                ),
              ),
        ],
      ),
    );
  }
}

class _MonthlyView extends ConsumerStatefulWidget {
  const _MonthlyView();

  @override
  ConsumerState<_MonthlyView> createState() => _MonthlyViewState();
}

class _MonthlyViewState extends ConsumerState<_MonthlyView> {
  String? _store;
  String? _month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final thisMonth = BusinessDate.monthOf(today);
    final month = _month ?? thisMonth;
    final locations = ref.watch(locationsProvider).value;
    if (locations == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final sorted = [...locations]..sort((a, b) => a.code.compareTo(b.code));
    if (sorted.isEmpty) return const Text('There are no stores yet.');
    final picked = _store;
    final store = picked != null && sorted.any((l) => l.code == picked)
        ? picked
        : defaultStore(sorted, ref.watch(selectedLocationProvider));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            KeyedSubtree(
              key: const Key('att-month-store'),
              child: StorePicker(
                locations: sorted,
                value: store,
                onChanged: (v) => setState(() => _store = v),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () =>
                      setState(() => _month = addMonths(month, -1)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    formatMonthKey(month),
                    key: const Key('att-month'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: month.compareTo(thisMonth) >= 0
                      ? null
                      : () => setState(() => _month = addMonths(month, 1)),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _MonthGrid(store: store, month: month),
      ],
    );
  }
}

class _MonthGrid extends ConsumerWidget {
  const _MonthGrid({required this.store, required this.month});

  final String store;
  final String month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rosterAsync = ref.watch(activeStaffProvider(store));
    final recordsAsync = ref.watch(attendanceMonthProvider((store, month)));
    final roster = rosterAsync.value;
    final records = recordsAsync.value;
    if (roster == null || records == null) {
      final error = rosterAsync.error ?? recordsAsync.error;
      return error != null
          ? Text('Could not load attendance: $error')
          : const Center(child: CircularProgressIndicator());
    }
    if (roster.isEmpty && records.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No staff at this store yet. Add people under Staff.',
          key: Key('att-month-empty'),
        ),
      );
    }

    final totals = attendanceTotals(roster, records);
    final p = month.split('-').map(int.parse).toList();
    final days = DateTime(p[0], p[1] + 1, 0).day;
    final marks = <String, Map<int, AttendanceRecord>>{};
    for (final r in records) {
      final day = int.parse(r.businessDate.substring(8));
      (marks[r.staffId] ??= {})[day] = r;
    }

    final scheme = theme.colorScheme;
    Widget cell(AttendanceRecord? r) {
      if (r == null) return const SizedBox.shrink();
      final (bg, fg) = switch (r.status) {
        AttendanceStatus.present => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
        AttendanceStatus.halfDay => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
        AttendanceStatus.absent => (
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
      };
      final letter = Container(
        width: 24,
        padding: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          _statusLetter(r.status),
          style: TextStyle(color: fg, fontWeight: FontWeight.w600),
        ),
      );
      final note = r.note;
      return note == null || note.isEmpty
          ? letter
          : Tooltip(message: note, child: letter);
    }

    Text num(String key, String text) => Text(text, key: Key(key));
    final sumPresent = totals.fold<int>(0, (a, t) => a + t.present);
    final sumHalf = totals.fold<int>(0, (a, t) => a + t.halfDays);
    final sumAbsent = totals.fold<int>(0, (a, t) => a + t.absent);
    final sumWorked = totals.fold<double>(0, (a, t) => a + t.daysWorked);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'P present, H half-day (counts 0.5), A absent. Blank means not '
          'marked.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            key: const Key('att-grid'),
            columnSpacing: 10,
            horizontalMargin: 10,
            dataRowMinHeight: 36,
            dataRowMaxHeight: 36,
            headingRowHeight: 40,
            columns: [
              const DataColumn(label: Text('Name')),
              for (var d = 1; d <= days; d++) DataColumn(label: Text('$d')),
              const DataColumn(label: Text('Present'), numeric: true),
              const DataColumn(label: Text('Half-days'), numeric: true),
              const DataColumn(label: Text('Absent'), numeric: true),
              const DataColumn(label: Text('Days worked'), numeric: true),
            ],
            rows: [
              for (final t in totals)
                DataRow(
                  key: ValueKey('att-row-${t.staffId}'),
                  cells: [
                    DataCell(Text(t.staffName)),
                    for (var d = 1; d <= days; d++)
                      DataCell(
                        KeyedSubtree(
                          key: Key('att-cell-${t.staffId}-$d'),
                          child: cell(marks[t.staffId]?[d]),
                        ),
                      ),
                    DataCell(
                      num('att-total-${t.staffId}-present', '${t.present}'),
                    ),
                    DataCell(
                      num('att-total-${t.staffId}-half', '${t.halfDays}'),
                    ),
                    DataCell(
                      num('att-total-${t.staffId}-absent', '${t.absent}'),
                    ),
                    DataCell(
                      num(
                        'att-total-${t.staffId}-worked',
                        formatDays(t.daysWorked),
                      ),
                    ),
                  ],
                ),
              DataRow(
                key: const ValueKey('att-row-all'),
                cells: [
                  DataCell(
                    Text('All staff', style: theme.textTheme.titleSmall),
                  ),
                  for (var d = 1; d <= days; d++) const DataCell(SizedBox()),
                  DataCell(num('att-total-all-present', '$sumPresent')),
                  DataCell(num('att-total-all-half', '$sumHalf')),
                  DataCell(num('att-total-all-absent', '$sumAbsent')),
                  DataCell(num('att-total-all-worked', formatDays(sumWorked))),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
