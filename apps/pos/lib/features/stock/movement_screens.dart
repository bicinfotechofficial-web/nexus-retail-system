import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../../app/providers.dart';
import '../../widgets/section_card.dart';
import 'stock_common.dart';

/// Shared state of a single-list movement page: the lines and a text field.
abstract class _LinesPageState<T extends ConsumerStatefulWidget>
    extends ConsumerState<T> {
  final List<LineDraft> lines = [LineDraft()];
  final TextEditingController text = TextEditingController();

  @override
  void dispose() {
    for (final l in lines) {
      l.dispose();
    }
    text.dispose();
    super.dispose();
  }

  void changed() => setState(() {});

  Widget editor(List<StockOption> options, {String prefix = 'line'}) =>
      LinesEditor(
        keyPrefix: prefix,
        options: options,
        lines: lines,
        maxLines: Limits.maxMovementLines,
        onChanged: changed,
      );
}

/// Raw materials received (STOCK_IN), with an optional note such as the
/// supplier.
class StockInScreen extends ConsumerStatefulWidget {
  const StockInScreen({super.key});

  @override
  ConsumerState<StockInScreen> createState() => _StockInScreenState();
}

class _StockInScreenState extends _LinesPageState<StockInScreen> {
  @override
  Widget build(BuildContext context) {
    final options = ref.watch(stockOptionsProvider).ofKind(StockKind.raw);
    final parsed = parseLines(lines);
    final ready = parsed.lines;
    return StockForm(
      title: 'Stock In',
      saveLabel: 'Save Stock In',
      problem: parsed.problem,
      onSave: ready == null
          ? null
          : () async {
              await ref
                  .read(stockServiceProvider)
                  .stockIn(ready, note: text.text.trim());
              return 'Stock In saved.';
            },
      children: [
        SectionCard(title: 'Received', children: [editor(options)]),
        TextFieldRow(
          fieldKey: 'note',
          controller: text,
          label: 'Note (optional)',
          helper: 'For example, the supplier or invoice number.',
          onChanged: changed,
        ),
      ],
    );
  }
}

/// Raw materials taken out for a reason other than wastage (STOCK_OUT_RAW).
class StockOutScreen extends ConsumerStatefulWidget {
  const StockOutScreen({super.key});

  @override
  ConsumerState<StockOutScreen> createState() => _StockOutScreenState();
}

class _StockOutScreenState extends _LinesPageState<StockOutScreen> {
  @override
  Widget build(BuildContext context) {
    final options = ref.watch(stockOptionsProvider).ofKind(StockKind.raw);
    final parsed = parseLines(lines);
    final reason = text.text.trim();
    final ready = parsed.lines;
    return StockForm(
      title: 'Stock Out',
      saveLabel: 'Save Stock Out',
      problem: parsed.problem ?? (reason.isEmpty ? 'Enter a reason.' : null),
      onSave: ready == null || reason.isEmpty
          ? null
          : () async {
              await ref
                  .read(stockServiceProvider)
                  .stockOutRaw(ready, reason: reason);
              return 'Stock Out saved.';
            },
      children: [
        SectionCard(title: 'Taken out', children: [editor(options)]),
        TextFieldRow(
          fieldKey: 'reason',
          controller: text,
          label: 'Reason',
          helper: 'For example, sent to another store.',
          onChanged: changed,
        ),
      ],
    );
  }
}

/// Spoiled or damaged stock, raw or finished (WASTAGE_RAW / WASTAGE_FG).
class WastageScreen extends ConsumerStatefulWidget {
  const WastageScreen({super.key});

  @override
  ConsumerState<WastageScreen> createState() => _WastageScreenState();
}

class _WastageScreenState extends _LinesPageState<WastageScreen> {
  StockKind _kind = StockKind.finished;

  @override
  Widget build(BuildContext context) {
    final options = ref.watch(stockOptionsProvider).ofKind(_kind);
    final parsed = parseLines(lines);
    final reason = text.text.trim();
    final ready = parsed.lines;
    return StockForm(
      title: 'Wastage',
      saveLabel: 'Save Wastage',
      problem: parsed.problem ?? (reason.isEmpty ? 'Enter a reason.' : null),
      onSave: ready == null || reason.isEmpty
          ? null
          : () async {
              await ref
                  .read(stockServiceProvider)
                  .wastage(_kind, ready, reason: reason);
              return 'Wastage saved.';
            },
      children: [
        SegmentedButton<StockKind>(
          segments: const [
            ButtonSegment(
              value: StockKind.finished,
              label: Text('Finished goods', key: Key('kind-finished')),
            ),
            ButtonSegment(
              value: StockKind.raw,
              label: Text('Raw materials', key: Key('kind-raw')),
            ),
          ],
          selected: {_kind},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() {
            _kind = s.single;
            // Lines of the other kind no longer apply.
            for (final l in lines) {
              l.dispose();
            }
            lines
              ..clear()
              ..add(LineDraft());
          }),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Wasted',
          children: [
            LinesEditor(
              // A new key per kind, so the pickers start empty.
              key: ValueKey(_kind),
              keyPrefix: 'line',
              options: options,
              lines: lines,
              maxLines: Limits.maxMovementLines,
              onChanged: changed,
            ),
          ],
        ),
        TextFieldRow(
          fieldKey: 'reason',
          controller: text,
          label: 'Reason',
          helper: 'For example, expired or dropped.',
          onChanged: changed,
        ),
      ],
    );
  }
}

/// Raw materials consumed and finished goods made, in one PRODUCE movement.
/// Both lists share `Limits.maxMovementLines`.
class ProduceScreen extends ConsumerStatefulWidget {
  const ProduceScreen({super.key});

  @override
  ConsumerState<ProduceScreen> createState() => _ProduceScreenState();
}

class _ProduceScreenState extends ConsumerState<ProduceScreen> {
  final List<LineDraft> _consumed = [LineDraft()];
  final List<LineDraft> _produced = [LineDraft()];

  @override
  void dispose() {
    for (final l in [..._consumed, ..._produced]) {
      l.dispose();
    }
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final options = ref.watch(stockOptionsProvider);
    final consumed = parseLines(_consumed);
    final produced = parseLines(_produced);
    final c = consumed.lines;
    final p = produced.lines;
    final problem = consumed.problem == null
        ? (produced.problem == null ? null : 'Made: ${produced.problem}')
        : 'Used: ${consumed.problem}';
    return StockForm(
      title: 'Produce',
      saveLabel: 'Save Produce',
      problem: problem,
      onSave: c == null || p == null
          ? null
          : () async {
              await ref
                  .read(stockServiceProvider)
                  .produce(consumed: c, produced: p);
              return 'Production saved.';
            },
      children: [
        SectionCard(
          title: 'Raw materials used',
          children: [
            LinesEditor(
              keyPrefix: 'used',
              options: options.ofKind(StockKind.raw),
              lines: _consumed,
              maxLines: Limits.maxMovementLines - _produced.length,
              onChanged: _changed,
            ),
          ],
        ),
        SectionCard(
          title: 'Finished goods made',
          children: [
            LinesEditor(
              keyPrefix: 'made',
              options: options.ofKind(StockKind.finished),
              lines: _produced,
              maxLines: Limits.maxMovementLines - _consumed.length,
              onChanged: _changed,
            ),
          ],
        ),
      ],
    );
  }
}

/// A physical count of one item. The service records `counted − localQty`
/// as the delta (03-SYNC §5).
class AdjustScreen extends ConsumerStatefulWidget {
  const AdjustScreen({this.itemKey, super.key});

  /// Preselected item, e.g. from the stock list.
  final String? itemKey;

  @override
  ConsumerState<AdjustScreen> createState() => _AdjustScreenState();
}

class _AdjustScreenState extends ConsumerState<AdjustScreen> {
  late String? _itemKey = widget.itemKey;
  final _counted = TextEditingController();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _counted.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final options = ref.watch(stockOptionsProvider);
    final option = options.where((o) => o.itemKey == _itemKey).firstOrNull;
    final countedText = _counted.text.trim();
    final counted = int.tryParse(countedText);
    final reason = _reason.text.trim();
    final String? problem;
    if (option == null) {
      problem = 'Choose an item.';
    } else if (counted == null || counted < 0) {
      problem = 'Enter the counted quantity, 0 or more.';
    } else if (reason.isEmpty) {
      problem = 'Enter a reason.';
    } else {
      problem = null;
    }
    final theme = Theme.of(context);
    return StockForm(
      title: 'Adjust',
      saveLabel: 'Save count',
      problem: problem,
      onSave: problem != null
          ? null
          : () async {
              await ref
                  .read(stockServiceProvider)
                  .adjust(
                    itemKey: option!.itemKey,
                    countedQty: counted!,
                    reason: reason,
                  );
              return 'Count saved for ${option.name}.';
            },
      children: [
        DropdownButtonFormField<String>(
          key: const Key('adjust-item'),
          isExpanded: true,
          initialValue: option?.itemKey,
          hint: const Text('Item'),
          items: [
            for (final o in options)
              DropdownMenuItem(
                value: o.itemKey,
                child: Text(o.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => _itemKey = v),
        ),
        if (option != null) ...[
          const SizedBox(height: 12),
          Text(
            'On this device: ${formatQty(option.qty, option.unit)}',
            key: const Key('adjust-current'),
            style: theme.textTheme.titleMedium,
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          key: const Key('counted'),
          controller: _counted,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Counted quantity',
            suffixText: option == null ? null : unitLabel(option.unit),
          ),
          onChanged: (_) => _changed(),
        ),
        if (option != null && counted != null && counted >= 0) ...[
          const SizedBox(height: 8),
          Text(
            'Change: ${counted - option.qty > 0 ? '+' : ''}'
            '${formatQty(counted - option.qty, option.unit)}',
            key: const Key('adjust-delta'),
          ),
        ],
        TextFieldRow(
          fieldKey: 'reason',
          controller: _reason,
          label: 'Reason',
          helper: 'For example, weekly count.',
          onChanged: _changed,
        ),
        Text(
          'Count while online if you can: a sale on another device during '
          'the count changes the result.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// The low-stock threshold of one item (`stock.threshold`). Empty clears it.
class ThresholdScreen extends ConsumerStatefulWidget {
  const ThresholdScreen({required this.itemKey, super.key});

  final String itemKey;

  @override
  ConsumerState<ThresholdScreen> createState() => _ThresholdScreenState();
}

class _ThresholdScreenState extends ConsumerState<ThresholdScreen> {
  final _threshold = TextEditingController();
  bool _filled = false;

  @override
  void dispose() {
    _threshold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final option = ref
        .watch(stockOptionsProvider)
        .where((o) => o.itemKey == widget.itemKey)
        .firstOrNull;
    if (option != null && !_filled) {
      _filled = true;
      _threshold.text = option.lowThreshold?.toString() ?? '';
    }
    final text = _threshold.text.trim();
    final value = int.tryParse(text);
    final valid = text.isEmpty || (value != null && value >= 0);
    return StockForm(
      title: 'Low-stock alert',
      saveLabel: text.isEmpty ? 'Save without alert' : 'Save threshold',
      problem: option == null
          ? "This item isn't in stock here."
          : valid
          ? null
          : 'Enter a whole number, 0 or more.',
      onSave: option == null || !valid
          ? null
          : () async {
              await ref
                  .read(stockServiceProvider)
                  .setThreshold(option.itemKey, text.isEmpty ? null : value);
              return text.isEmpty
                  ? 'Alert removed for ${option.name}.'
                  : 'Alert set for ${option.name}.';
            },
      children: [
        if (option != null) ...[
          Text(option.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('In stock: ${formatQty(option.qty, option.unit)}'),
          const SizedBox(height: 16),
        ],
        TextField(
          key: const Key('threshold'),
          controller: _threshold,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Alert at or below',
            suffixText: option == null ? null : unitLabel(option.unit),
            helperText: 'Leave empty for no alert.',
            suffixIcon: text.isEmpty
                ? null
                : IconButton(
                    key: const Key('threshold-clear'),
                    tooltip: 'No alert',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(_threshold.clear),
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }
}
