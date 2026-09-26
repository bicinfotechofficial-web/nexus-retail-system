import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../../app/messages.dart';
import '../../app/providers.dart';
import '../../widgets/pos_scaffold.dart';
import '../../widgets/section_card.dart';

/// A Store Manager's local special (POS-10, `catalog.suggest`). It is saved
/// as PENDING with a proposed price, and can't be sold until an Admin
/// approves it and sets the price (D-008).
class SuggestScreen extends ConsumerStatefulWidget {
  const SuggestScreen({super.key});

  @override
  ConsumerState<SuggestScreen> createState() => _SuggestScreenState();
}

class _SuggestScreenState extends ConsumerState<SuggestScreen> {
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _price = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _price.dispose();
    super.dispose();
  }

  static Money? _money(String text) {
    try {
      return Money.parse(text.trim());
    } on FormatException {
      return null;
    }
  }

  Future<void> _submit(String name, String category, Money price) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(catalogServiceProvider)
          .suggest(name: name, category: category, proposedPrice: price);
    } on DataFailure catch (e) {
      _failed(Messages.failure(e));
      return;
    } catch (_) {
      _failed(Messages.failure(const DataFailure(FailureReason.unknown)));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('suggest-sent'),
          content: Text(
            '$name was sent to the Admin. It can be sold once approved.',
          ),
        ),
      );
    setState(() {
      _saving = false;
      _name.clear();
      _price.clear();
    });
  }

  void _failed(String message) {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = <String>{
      for (final p
          in ref.watch(sellableProductsProvider).value ?? const <Product>[])
        p.category,
    };
    final pending = ref.watch(pendingSuggestionsProvider).value ?? const [];

    final name = _name.text.trim();
    final category = _category.text.trim();
    final priceText = _price.text.trim();
    final price = priceText.isEmpty ? null : _money(priceText);
    final priceError = priceText.isNotEmpty && (price == null)
        ? 'Enter an amount, like 450 or 449.50.'
        : price != null && !price.isPositive
        ? 'The price must be more than zero.'
        : null;
    final ready =
        name.isNotEmpty &&
        category.isNotEmpty &&
        price != null &&
        priceError == null;

    return PosScaffold(
      title: 'Suggest special',
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
                  key: const Key('save-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            FilledButton.icon(
              key: const Key('save'),
              onPressed: ready && !_saving
                  ? () => _submit(name, category, price)
                  : null,
              icon: const Icon(Icons.send),
              label: const Text('Send for approval'),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SectionCard(
            title: 'New local special',
            children: [
              Text(
                'Only this store will sell it, after the Admin approves it '
                'and sets the final price.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('suggest-name'),
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('suggest-category'),
                controller: _category,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Category'),
                onChanged: (_) => setState(() {}),
              ),
              if (categories.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final c in categories)
                      ChoiceChip(
                        key: Key('category-chip-$c'),
                        label: Text(c),
                        selected: category == c,
                        onSelected: (_) => setState(() => _category.text = c),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                key: const Key('suggest-price'),
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Proposed price (₹)',
                  errorText: priceError,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          SectionCard(
            title: 'Waiting for approval',
            children: [
              if (pending.isEmpty)
                const Text('Nothing waiting.')
              else
                for (final p in pending)
                  ListTile(
                    key: Key('pending-${p.id}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.name),
                    subtitle: Text(p.category),
                    trailing: Text(p.proposedPrice?.format() ?? ''),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}
