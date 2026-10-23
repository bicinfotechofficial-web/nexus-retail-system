import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexus_core/nexus_core.dart';

/// `2026-09-26` → `Sat, 26 Sep 2026`.
String formatBusinessDate(String businessDate) {
  final p = businessDate.split('-').map(int.parse).toList();
  return DateFormat('EEE, d MMM y').format(DateTime(p[0], p[1], p[2]));
}

/// `HH:mm` in IST, whatever the device's own time zone (D-022).
String formatIstTime(DateTime instant) =>
    DateFormat('HH:mm').format(instant.toUtc().add(BusinessDate.istOffset));

/// Previous day, a date picker, and next day, for screens that show one
/// business day. It never goes past [today], nor before [earliest] when given.
class DateBar extends StatelessWidget {
  const DateBar({
    required this.date,
    required this.today,
    required this.onChanged,
    this.earliest,
    super.key,
  });

  /// `YYYY-MM-DD`.
  final String date;
  final String today;
  final ValueChanged<String> onChanged;

  /// The oldest day that can be chosen, or null for no limit.
  final String? earliest;

  static DateTime _local(String d) {
    final p = d.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _pick(BuildContext context) async {
    final last = _local(today);
    final picked = await showDatePicker(
      context: context,
      initialDate: _local(date),
      firstDate: earliest == null ? DateTime(last.year - 2) : _local(earliest!),
      lastDate: last,
    );
    if (picked != null) onChanged(_key(picked));
  }

  @override
  Widget build(BuildContext context) {
    final isToday = date == today;
    return Row(
      children: [
        IconButton(
          key: const Key('date-prev'),
          tooltip: 'Previous day',
          icon: const Icon(Icons.chevron_left),
          onPressed: earliest != null && date.compareTo(earliest!) <= 0
              ? null
              : () => onChanged(BusinessDate.addDays(date, -1)),
        ),
        Expanded(
          child: TextButton.icon(
            key: const Key('date-pick'),
            onPressed: () => _pick(context),
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(
              isToday
                  ? 'Today · ${formatBusinessDate(date)}'
                  : formatBusinessDate(date),
              key: const Key('date-label'),
            ),
          ),
        ),
        IconButton(
          key: const Key('date-next'),
          tooltip: 'Next day',
          icon: const Icon(Icons.chevron_right),
          onPressed: isToday
              ? null
              : () => onChanged(BusinessDate.addDays(date, 1)),
        ),
      ],
    );
  }
}
