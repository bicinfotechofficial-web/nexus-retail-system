import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../../app/destinations.dart';
import '../../app/messages.dart';
import '../../app/providers.dart';
import '../../widgets/pos_scaffold.dart';

final NumberFormat _qtyFormat = NumberFormat('#,##0', 'en_IN');

String unitLabel(StockUnit unit) => switch (unit) {
  StockUnit.g => 'g',
  StockUnit.ml => 'ml',
  StockUnit.pcs => 'pcs',
};

/// `1,500 g`, `-2 pcs`. Base units (D-006).
String formatQty(int qty, StockUnit unit) =>
    '${_qtyFormat.format(qty)} ${unitLabel(unit)}';

/// An item a stock operation can use: every active raw material, every
/// product sellable here, and every existing stock doc (which wins, since it
/// has the quantity and threshold). An item without a stock doc is at zero.
final class StockOption {
  const StockOption({
    required this.itemKey,
    required this.name,
    required this.kind,
    required this.unit,
    required this.qty,
    this.lowThreshold,
  });

  factory StockOption.of(StockItem i) => StockOption(
    itemKey: i.itemKey,
    name: i.name,
    kind: i.kind,
    unit: i.unit,
    qty: i.qty,
    lowThreshold: i.lowThreshold,
  );

  final String itemKey;
  final String name;
  final StockKind kind;
  final StockUnit unit;
  final int qty;
  final int? lowThreshold;
}

final stockOptionsProvider = Provider<List<StockOption>>((ref) {
  final stock = ref.watch(stockProvider).value ?? const <StockItem>[];
  final materials =
      ref.watch(rawMaterialsProvider).value ?? const <RawMaterial>[];
  final products = ref.watch(sellableProductsProvider).value ?? const [];
  final byKey = <String, StockOption>{
    for (final m in materials)
      if (m.active && Ids.isSafeKey(m.id))
        Ids.rawItemKey(m.id): StockOption(
          itemKey: Ids.rawItemKey(m.id),
          name: m.name,
          kind: StockKind.raw,
          unit: m.unit,
          qty: 0,
        ),
    for (final p in products)
      if (Ids.isSafeKey(p.id))
        Ids.finishedItemKey(p.id): StockOption(
          itemKey: Ids.finishedItemKey(p.id),
          name: p.name,
          kind: StockKind.finished,
          unit: p.unit,
          qty: 0,
        ),
    for (final s in stock) s.itemKey: StockOption.of(s),
  };
  return byKey.values.toList()..sort((a, b) {
    final k = a.kind.index.compareTo(b.kind.index);
    return k != 0 ? k : a.name.compareTo(b.name);
  });
});

/// One editable line of a movement: an item and a quantity in base units.
final class LineDraft {
  String? itemKey;
  final TextEditingController qty = TextEditingController();

  void dispose() => qty.dispose();
}

/// The lines as `StockLineInput`s, or why they can't be saved yet.
({List<StockLineInput>? lines, String? problem}) parseLines(
  List<LineDraft> drafts,
) {
  if (drafts.isEmpty) return (lines: null, problem: 'Add at least one item.');
  final out = <StockLineInput>[];
  final seen = <String>{};
  for (final d in drafts) {
    final key = d.itemKey;
    if (key == null) {
      return (lines: null, problem: 'Choose an item on every line.');
    }
    final qty = int.tryParse(d.qty.text.trim());
    if (qty == null || qty <= 0) {
      return (
        lines: null,
        problem: 'Enter a whole quantity of 1 or more on every line.',
      );
    }
    if (!seen.add(key)) {
      return (lines: null, problem: 'Each item can be on only one line.');
    }
    out.add(StockLineInput(itemKey: key, qty: qty));
  }
  return (lines: out, problem: null);
}

/// Rows of item + quantity with add and remove, for one movement. At most
/// [maxLines] rows (`Limits.maxMovementLines`, shared on Produce).
class LinesEditor extends StatelessWidget {
  const LinesEditor({
    required this.keyPrefix,
    required this.options,
    required this.lines,
    required this.maxLines,
    required this.onChanged,
    super.key,
  });

  final String keyPrefix;
  final List<StockOption> options;
  final List<LineDraft> lines;
  final int maxLines;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    StockOption? optionOf(String? key) =>
        options.where((o) => o.itemKey == key).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < lines.length; i++)
          Padding(
            key: ObjectKey(lines[i]),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    key: Key('$keyPrefix-item-$i'),
                    isExpanded: true,
                    initialValue: lines[i].itemKey,
                    hint: const Text('Item'),
                    items: [
                      for (final o in options)
                        DropdownMenuItem(
                          value: o.itemKey,
                          child: Text(o.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) {
                      lines[i].itemKey = v;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: Builder(
                    builder: (context) {
                      final o = optionOf(lines[i].itemKey);
                      return TextField(
                        key: Key('$keyPrefix-qty-$i'),
                        controller: lines[i].qty,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Qty',
                          suffixText: o == null ? null : unitLabel(o.unit),
                          helperText: o == null
                              ? null
                              : 'Has ${formatQty(o.qty, o.unit)}',
                          helperMaxLines: 2,
                        ),
                        onChanged: (_) => onChanged(),
                      );
                    },
                  ),
                ),
                if (lines.length > 1)
                  IconButton(
                    key: Key('$keyPrefix-remove-$i'),
                    tooltip: 'Remove line',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      lines.removeAt(i).dispose();
                      onChanged();
                    },
                  ),
              ],
            ),
          ),
        Row(
          children: [
            TextButton.icon(
              key: Key('$keyPrefix-add'),
              onPressed: lines.length < maxLines
                  ? () {
                      lines.add(LineDraft());
                      onChanged();
                    }
                  : null,
              icon: const Icon(Icons.add),
              label: const Text('Add item'),
            ),
            if (lines.length >= maxLines)
              Expanded(
                child: Text(
                  'A movement can have at most ${Limits.maxMovementLines} '
                  'lines. Save this one and start another for the rest.',
                  key: Key('$keyPrefix-limit'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// A stock operation page: the form, and a Save button that disables on
/// the first tap and returns to the stock hub with a confirmation.
class StockForm extends StatefulWidget {
  const StockForm({
    required this.title,
    required this.saveLabel,
    required this.children,
    required this.onSave,
    this.problem,
    super.key,
  });

  final String title;
  final String saveLabel;
  final List<Widget> children;

  /// Null while the form is incomplete. Returns the confirmation text.
  final Future<String> Function()? onSave;

  /// Why Save is off, shown above it.
  final String? problem;

  @override
  State<StockForm> createState() => _StockFormState();
}

class _StockFormState extends State<StockForm> {
  bool _saving = false;

  /// Set when a save failed in a way that leaves it unclear whether the
  /// movement was written, so another tap could record it twice.
  bool _locked = false;
  String? _error;

  Future<void> _save() async {
    final onSave = widget.onSave;
    if (_saving || _locked || onSave == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final String done;
    try {
      done = await onSave();
    } on DataFailure catch (e) {
      _failed(Messages.failure(e), lock: e.reason == FailureReason.unknown);
      return;
    } catch (_) {
      _failed(
        Messages.failure(const DataFailure(FailureReason.unknown)),
        lock: true,
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(key: const Key('stock-saved'), content: Text(done)),
      );
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Destinations.stock.path);
    }
  }

  void _failed(String message, {required bool lock}) {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _locked = lock;
      _error = lock
          ? '$message\nIt may have been saved. Check the stock list before '
                'trying again.'
          : message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = _error ?? widget.problem;
    return PosScaffold(
      title: widget.title,
      showDrawer: false,
      bottom: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  message,
                  key: Key(_error != null ? 'save-error' : 'form-problem'),
                  style: _error != null
                      ? TextStyle(color: theme.colorScheme.error)
                      : theme.textTheme.bodySmall,
                ),
              ),
            FilledButton.icon(
              key: const Key('save'),
              onPressed: widget.onSave != null && !_saving && !_locked
                  ? _save
                  : null,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(widget.saveLabel),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: widget.children,
        ),
      ),
    );
  }
}

/// A required or optional free-text field (reason, note).
class TextFieldRow extends StatelessWidget {
  const TextFieldRow({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.onChanged,
    this.helper,
    super.key,
  });

  final String fieldKey;
  final TextEditingController controller;
  final String label;
  final String? helper;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      key: Key(fieldKey),
      controller: controller,
      textCapitalization: TextCapitalization.sentences,
      maxLength: 200,
      decoration: InputDecoration(labelText: label, helperText: helper),
      onChanged: (_) => onChanged(),
    ),
  );
}

/// The options of one kind, for a picker.
extension StockOptionsOf on List<StockOption> {
  List<StockOption> ofKind(StockKind kind) =>
      where((o) => o.kind == kind).toList();
}
