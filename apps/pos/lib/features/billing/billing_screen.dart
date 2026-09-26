import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_core/nexus_core.dart';

import '../../app/messages.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../widgets/pos_scaffold.dart';
import '../../widgets/total_row.dart';
import 'cart.dart';

/// The home screen: product grid by category, search, and the cart.
class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _category;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(sellableProductsProvider);
    return PosScaffold(
      title: 'Billing',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              key: const Key('search'),
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search items',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      ),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: products.when(
              data: _catalog,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    "Couldn't load the catalog.\n$e",
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
          const CartPanel(),
        ],
      ),
    );
  }

  Widget _catalog(List<Product> products) {
    final categories = <String>[];
    for (final p in products) {
      if (!categories.contains(p.category)) categories.add(p.category);
    }
    final q = _query.toLowerCase();
    final shown = products
        .where(
          (p) =>
              (_category == null || p.category == _category) &&
              (q.isEmpty || p.name.toLowerCase().contains(q)),
        )
        .toList();
    return Column(
      children: [
        SizedBox(
          height: 56,
          // A handful of categories: build them all, scroll sideways.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final c in [null, ...categories])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: Key('category-${c ?? 'All'}'),
                      label: Text(c ?? 'All'),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? const Center(child: Text('No items match.'))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    mainAxisExtent: 96,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: shown.length,
                  itemBuilder: (context, i) => _ProductTile(shown[i]),
                ),
        ),
      ],
    );
  }
}

class _ProductTile extends ConsumerWidget {
  const _ProductTile(this.product);

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qty = ref.watch(
      cartProvider.select(
        (lines) => lines
            .where((l) => l.productId == product.id)
            .fold<int>(0, (a, l) => a + l.qty),
      ),
    );
    final theme = Theme.of(context);
    return Card(
      key: Key('product-${product.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          final error = ref.read(cartProvider.notifier).add(product);
          if (error == null) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                key: const Key('cart-limit'),
                content: Text(Messages.billError(error)),
              ),
            );
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      product.price?.format() ?? '',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: PosTheme.cocoa,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (qty > 0) Badge(label: Text('$qty')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The cart with qty ± and remove, and the running total.
class CartPanel extends ConsumerWidget {
  const CartPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final result = ref.watch(cartTotalsProvider);
    final totals = result?.totals;
    final error = result?.error;
    final notifier = ref.read(cartProvider.notifier);
    final theme = Theme.of(context);
    Money? lineTotal(String productId) => totals?.lines
        .where((l) => l.productId == productId)
        .firstOrNull
        ?.lineTotal;
    return Material(
      elevation: 8,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (cart.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Tap an item to add it to the bill.',
                  textAlign: TextAlign.center,
                ),
              )
            else ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView(
                  key: const Key('cart'),
                  shrinkWrap: true,
                  children: [
                    // Rows come from the cart itself, so they stay usable
                    // even when the calculator refuses it (QA-027).
                    for (final line in cart)
                      _CartRow(
                        line: line,
                        lineTotal: lineTotal(line.productId),
                        onRemove: () => notifier.remove(line.productId),
                        onMinus: () => notifier.decrement(line.productId),
                        onPlus: () => notifier.increment(line.productId),
                      ),
                  ],
                ),
              ),
              const Divider(height: 8),
              if (error != null)
                Text(
                  Messages.billError(error),
                  key: const Key('cart-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              if (totals != null) ...[
                if (!totals.roundOff.isZero)
                  TotalRow('Round-off', totals.roundOff.format()),
                TotalRow(
                  'Total',
                  totals.total.format(),
                  key: const Key('cart-total'),
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('charge'),
              onPressed: totals == null ? null : () => context.push('/payment'),
              icon: const Icon(Icons.payments),
              label: Text(
                totals == null ? 'Charge' : 'Charge ${totals.total.format()}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  const _CartRow({
    required this.line,
    required this.lineTotal,
    required this.onRemove,
    required this.onMinus,
    required this.onPlus,
  });

  final CartLine line;

  /// From `BillCalculator`; null when the cart can't be computed.
  final Money? lineTotal;
  final VoidCallback onRemove;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final id = line.productId;
    return Row(
      key: Key('cart-line-$id'),
      children: [
        IconButton(
          key: Key('remove-$id'),
          tooltip: 'Remove ${line.name}',
          icon: const Icon(Icons.delete_outline),
          onPressed: onRemove,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(line.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                line.unitPrice.format(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton(
          key: Key('dec-$id'),
          tooltip: 'One less',
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: onMinus,
        ),
        SizedBox(
          width: 28,
          child: Text(
            '${line.qty}',
            key: Key('qty-$id'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          key: Key('inc-$id'),
          tooltip: 'One more',
          icon: const Icon(Icons.add_circle_outline),
          onPressed: onPlus,
        ),
        SizedBox(
          width: 88,
          child: Text(
            lineTotal?.format() ?? '',
            key: Key('line-total-$id'),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
