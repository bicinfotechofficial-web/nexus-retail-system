import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../../app/messages.dart';
import '../../app/providers.dart';
import '../../widgets/date_bar.dart';
import '../../widgets/pos_scaffold.dart';

/// What the manager has chosen for one person on one day, before Save.
class _Draft {
  _Draft(String note) : note = TextEditingController(text: note);

  AttendanceStatus? status;
  final TextEditingController note;
}

/// The Store Manager's daily attendance (D-042): every active staff member
/// gets Present, Half-day or Absent and an optional note, for today or up to
/// [Limits.attendanceBackDays] days back. Existing marks are pre-filled, and
/// one Save sends only the rows that changed, in one `mark` call, so marking
/// again overwrites and a retry is harmless. The service works offline, so
/// Save does too.
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  late final String _today;
  late final String _earliest;
  late String _date;

  /// Choices per date, then per staff ID, so going to another day and back
  /// keeps what was entered.
  final Map<String, Map<String, _Draft>> _drafts = {};
  bool _saving = false;
  String? _error;

  /// What the last Save said, until the next change.
  String? _saved;

  @override
  void initState() {
    super.initState();
    _today = BusinessDate.of(ref.read(clockProvider)());
    _earliest = BusinessDate.addDays(_today, -Limits.attendanceBackDays);
    _date = _today;
  }

  @override
  void dispose() {
    for (final day in _drafts.values) {
      for (final d in day.values) {
        d.note.dispose();
      }
    }
    super.dispose();
  }

  _Draft _draft(String staffId, AttendanceRecord? existing) {
    final day = _drafts[_date] ??= {};
    return day[staffId] ??= _Draft(existing?.note ?? '')
      ..status = existing?.status;
  }

  static String? _noteOf(_Draft d) {
    final t = d.note.text.trim();
    return t.isEmpty ? null : t;
  }

  bool _changed(_Draft d, AttendanceRecord? existing) {
    final status = d.status;
    if (status == null) return false;
    return existing == null ||
        existing.status != status ||
        existing.note != _noteOf(d);
  }

  void _pick(_Draft d, AttendanceStatus status) => setState(() {
    d.status = status;
    _saved = null;
    _error = null;
  });

  Future<void> _save(List<AttendanceMark> marks) async {
    // Guard before any await, so a double tap sends one call.
    if (_saving || marks.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
      _saved = null;
    });
    final date = _date;
    String? error;
    try {
      await ref.read(attendanceServiceProvider).mark(date, marks);
    } on Object catch (e) {
      error = Messages.anyError(e);
    }
    if (!mounted) return;
    final offline = ref.read(syncStatusProvider).value is Offline;
    setState(() {
      _saving = false;
      _error = error;
      if (error == null) {
        final n = marks.length;
        _saved =
            'Saved $n ${n == 1 ? 'mark' : 'marks'} for '
            '${formatBusinessDate(date)}.'
            '${offline ? ' Kept on this phone, and sent when it is online.' : ''}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final staffAsync = ref.watch(activeStaffProvider);
    final recordsAsync = ref.watch(attendanceForDayProvider(_date));
    final staff = staffAsync.value;
    final records = recordsAsync.value;

    Widget body;
    List<AttendanceMark> marks = const [];
    if (staffAsync.hasError || recordsAsync.hasError) {
      body = _Message(
        Messages.anyError(staffAsync.error ?? recordsAsync.error!),
        key: const Key('attendance-error'),
      );
    } else if (staff == null || records == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (staff.isEmpty) {
      body = const _Message(
        'No staff yet. Ask the Admin to add staff.',
        key: Key('attendance-empty'),
      );
    } else {
      final byStaff = {for (final r in records) r.staffId: r};
      final drafts = {for (final s in staff) s.id: _draft(s.id, byStaff[s.id])};
      marks = [
        for (final s in staff)
          if (_changed(drafts[s.id]!, byStaff[s.id]))
            AttendanceMark(
              staffId: s.id,
              staffName: s.name,
              status: drafts[s.id]!.status!,
              note: _noteOf(drafts[s.id]!),
            ),
      ];
      int count(AttendanceStatus? st) =>
          drafts.values.where((d) => d.status == st).length;
      final unmarked = count(null);
      // A roster is a handful of people: build every row, no lazy list.
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${count(AttendanceStatus.present)} present · '
                    '${count(AttendanceStatus.halfDay)} half-day · '
                    '${count(AttendanceStatus.absent)} absent'
                    '${unmarked > 0 ? ' · $unmarked not marked' : ''}',
                    key: const Key('attendance-summary'),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                TextButton.icon(
                  key: const Key('mark-all-present'),
                  onPressed: unmarked == 0
                      ? null
                      : () => setState(() {
                          for (final d in drafts.values) {
                            d.status ??= AttendanceStatus.present;
                          }
                          _saved = null;
                          _error = null;
                        }),
                  icon: const Icon(Icons.done_all),
                  label: const Text('Mark all present'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final s in staff)
              _StaffCard(
                key: Key('staff-${s.id}'),
                staff: s,
                draft: drafts[s.id]!,
                onPick: (st) => _pick(drafts[s.id]!, st),
                onNote: () => setState(() {
                  _saved = null;
                  _error = null;
                }),
              ),
          ],
        ),
      );
    }

    return PosScaffold(
      title: 'Attendance',
      bottom: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  key: const Key('attendance-save-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            if (_saved != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Color(0xFF1E6B2A),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_saved!, key: const Key('attendance-saved')),
                    ),
                  ],
                ),
              ),
            FilledButton.icon(
              key: const Key('save-attendance'),
              onPressed: marks.isEmpty || _saving ? null : () => _save(marks),
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(
                marks.isEmpty
                    ? 'Save'
                    : 'Save ${marks.length} '
                          '${marks.length == 1 ? 'change' : 'changes'}',
              ),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DateBar(
            date: _date,
            today: _today,
            earliest: _earliest,
            onChanged: (d) => setState(() {
              _date = d.compareTo(_today) > 0
                  ? _today
                  : d.compareTo(_earliest) < 0
                  ? _earliest
                  : d;
              _saved = null;
              _error = null;
            }),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({
    required this.staff,
    required this.draft,
    required this.onPick,
    required this.onNote,
    super.key,
  });

  final StaffMember staff;
  final _Draft draft;
  final ValueChanged<AttendanceStatus> onPick;
  final VoidCallback onNote;

  static const _labels = {
    AttendanceStatus.present: 'Present',
    AttendanceStatus.halfDay: 'Half-day',
    AttendanceStatus.absent: 'Absent',
  };

  static const _keys = {
    AttendanceStatus.present: 'present',
    AttendanceStatus.halfDay: 'half',
    AttendanceStatus.absent: 'absent',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(staff.name, style: theme.textTheme.titleMedium),
                ),
                if (staff.role.isNotEmpty)
                  Text(staff.role, style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final st in AttendanceStatus.values)
                  ChoiceChip(
                    key: Key('att-${staff.id}-${_keys[st]}'),
                    label: Text(_labels[st]!),
                    selected: draft.status == st,
                    onSelected: (_) => onPick(st),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: Key('att-note-${staff.id}'),
              controller: draft.note,
              enabled: draft.status != null,
              maxLength: Limits.attendanceNoteMax,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    required maxLength,
                  }) => null,
              decoration: InputDecoration(
                labelText: 'Note (optional)',
                hintText: draft.status == null ? 'Mark first' : null,
                isDense: true,
              ),
              onChanged: (_) => onNote(),
            ),
          ],
        ),
      ),
    );
  }
}
