import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../common/dialogs.dart';
import '../common/model_copies.dart';
import '../data/providers.dart';
import '../users/users_screen.dart' show usersProvider;
import 'catalog_providers.dart';
import 'product_form.dart';

/// Products, the approval queue for PENDING suggestions, and raw
/// materials. The whole screen needs `catalog.manage` (router guard).
class CatalogScreen extends ConsumerWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingProductsProvider).value?.length ?? 0;
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Text(
              'Catalog',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              const Tab(key: Key('tab-products'), text: 'Products'),
              Tab(
                key: const Key('tab-approvals'),
                text: pending == 0
                    ? 'Approval queue'
                    : 'Approval queue ($pending)',
              ),
              const Tab(key: Key('tab-materials'), text: 'Raw materials'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [ProductsTab(), ApprovalQueue(), RawMaterialsTab()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Every product, with filters by text, category, status and scope.
class ProductsTab extends ConsumerStatefulWidget {
  const ProductsTab({super.key});

  @override
  ConsumerState<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends ConsumerState<ProductsTab> {
  String _query = '';
  String? _category;
  ProductStatus? _status;
  String? _scope;

  bool _matches(Product p) =>
      (_query.isEmpty || p.name.toLowerCase().contains(_query)) &&
      (_category == null || p.category == _category) &&
      (_status == null || p.status == _status) &&
      (_scope == null || p.scope == _scope);

  Future<void> _setStatus(Product p, ProductStatus status) async {
    final deactivate = status == ProductStatus.inactive;
    final ok = await confirmAction(
      context,
      title: deactivate ? 'Deactivate ${p.name}?' : 'Reactivate ${p.name}?',
      message: deactivate
          ? 'It disappears from the POS at every location. Past bills and '
                'reports keep it.'
          : 'It can be sold again at ${scopeLabel(p.scope).toLowerCase()} '
                'for ${p.price?.format()}.',
      confirmLabel: deactivate ? 'Deactivate' : 'Reactivate',
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(catalogServiceProvider).save(p.copyWith(status: status));
    } on Object catch (e) {
      if (mounted) showMessage(context, failureMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final canManage = session?.can(Permission.catalogManage) ?? false;
    final async = ref.watch(allProductsProvider);
    final all = async.value;
    if (all == null) {
      return async.hasError
          ? Center(child: Text('Could not load products: ${async.error}'))
          : const Center(child: CircularProgressIndicator());
    }
    final categories = {for (final p in all) p.category}.toList()..sort();
    final scopes = {for (final p in all) p.scope}.toList()..sort();
    final shown = all.where(_matches).toList();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 240,
              child: TextField(
                key: const Key('product-search'),
                decoration: const InputDecoration(
                  labelText: 'Search by name',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
            _Filter<String>(
              filterKey: 'filter-category',
              label: 'Category',
              value: _category,
              options: {for (final c in categories) c: c},
              onChanged: (v) => setState(() => _category = v),
            ),
            _Filter<ProductStatus>(
              filterKey: 'filter-status',
              label: 'Status',
              value: _status,
              options: {
                for (final s in ProductStatus.values) s: productStatusLabel(s),
              },
              onChanged: (v) => setState(() => _status = v),
            ),
            _Filter<String>(
              filterKey: 'filter-scope',
              label: 'Sold at',
              value: _scope,
              options: {for (final s in scopes) s: scopeLabel(s)},
              onChanged: (v) => setState(() => _scope = v),
            ),
            if (canManage)
              FilledButton.icon(
                key: const Key('product-add'),
                onPressed: () => showProductForm(context),
                icon: const Icon(Icons.add),
                label: const Text('New product'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '${shown.length} of ${all.length} products',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            key: const Key('products-table'),
            columnSpacing: 32,
            // A declined suggestion shows its note and reviewer too.
            dataRowMaxHeight: 80,
            columns: const [
              DataColumn(label: Text('Name')),
              DataColumn(label: Text('Category')),
              DataColumn(label: Text('Price'), numeric: true),
              DataColumn(label: Text('Sold at')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final p in shown)
                DataRow(
                  key: ValueKey('product-${p.id}'),
                  cells: [
                    DataCell(Text(p.name)),
                    DataCell(Text(p.category)),
                    DataCell(
                      Text(
                        p.price?.format() ??
                            'proposed ${p.proposedPrice?.format() ?? '–'}',
                        key: Key('price-${p.id}'),
                      ),
                    ),
                    DataCell(Text(scopeLabel(p.scope))),
                    DataCell(
                      p.wasDeclined
                          ? DeclinedNote(
                              key: Key('declined-${p.id}'),
                              product: p,
                            )
                          : Text(
                              productStatusLabel(p.status),
                              key: Key('status-${p.id}'),
                            ),
                    ),
                    DataCell(canManage ? _actions(p) : const SizedBox.shrink()),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actions(Product p) => Row(
    mainAxisSize: MainAxisSize.min,
    children: switch (p.status) {
      ProductStatus.pending => [const Text('See the approval queue')],
      ProductStatus.active => [
        IconButton(
          key: Key('edit-${p.id}'),
          tooltip: 'Edit',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => showProductForm(context, existing: p),
        ),
        TextButton(
          key: Key('deactivate-${p.id}'),
          onPressed: () => _setStatus(p, ProductStatus.inactive),
          child: const Text('Deactivate'),
        ),
      ],
      ProductStatus.inactive => [
        IconButton(
          key: Key('edit-${p.id}'),
          tooltip: 'Edit',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => showProductForm(context, existing: p),
        ),
        if (p.price != null)
          TextButton(
            key: Key('reactivate-${p.id}'),
            onPressed: () => _setStatus(p, ProductStatus.active),
            child: const Text('Reactivate'),
          ),
      ],
    },
  );
}

/// A dropdown whose first entry, "All", clears the filter.
class _Filter<T> extends StatelessWidget {
  const _Filter({
    required this.filterKey,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String filterKey;
  final String label;
  final T? value;
  final Map<T, String> options;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 200,
    child: DropdownButtonFormField<T?>(
      key: Key(filterKey),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem<T?>(value: null, child: Text('All')),
        for (final e in options.entries)
          DropdownMenuItem<T?>(value: e.key, child: Text(e.value)),
      ],
      onChanged: onChanged,
    ),
  );
}

/// PENDING suggestions from Store Managers. Approving sets the price and
/// makes the product sellable (D-008); declining needs a note (D-038).
class ApprovalQueue extends ConsumerWidget {
  const ApprovalQueue({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage =
        ref.watch(sessionProvider)?.can(Permission.catalogManage) ?? false;
    final async = ref.watch(pendingProductsProvider);
    final pending = async.value == null
        ? null
        : [
            for (final p in async.value!)
              if (p.status == ProductStatus.pending) p,
          ];
    if (pending == null) {
      return async.hasError
          ? Center(child: Text('Could not load suggestions: ${async.error}'))
          : const Center(child: CircularProgressIndicator());
    }
    if (pending.isEmpty) {
      return const Center(
        key: Key('approvals-empty'),
        child: Text('No suggestions are waiting for approval.'),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Store Managers suggested these local specials. They cannot be '
          'sold until you approve them and set the price.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        for (final p in pending)
          Card(
            key: ValueKey('pending-${p.id}'),
            child: ListTile(
              title: Text(p.name),
              subtitle: Text(
                '${p.category} · ${scopeLabel(p.scope)} · proposed '
                '${p.proposedPrice?.format() ?? 'no price'}',
              ),
              trailing: canManage
                  ? Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          key: Key('decline-${p.id}'),
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => DeclineDialog(product: p),
                          ),
                          child: const Text('Decline'),
                        ),
                        FilledButton(
                          key: Key('approve-${p.id}'),
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => ApproveDialog(product: p),
                          ),
                          child: const Text('Approve'),
                        ),
                      ],
                    )
                  : null,
            ),
          ),
      ],
    );
  }
}

/// Declines a PENDING suggestion with a note for the Store Manager, 1 to
/// [Limits.reviewNoteMax] characters (`CatalogService.decline`, D-038).
class DeclineDialog extends ConsumerStatefulWidget {
  const DeclineDialog({required this.product, super.key});

  final Product product;

  @override
  ConsumerState<DeclineDialog> createState() => _DeclineDialogState();
}

class _DeclineDialogState extends ConsumerState<DeclineDialog> {
  final _form = GlobalKey<FormState>();
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _decline() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(catalogServiceProvider)
          .decline(productId: widget.product.id, note: _note.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop();
      showMessage(context, '${widget.product.name} is declined.');
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, failureMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Decline ${widget.product.name}'),
    content: SizedBox(
      width: 400,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'It never appears on the POS. The Store Manager sees your note '
              'in My suggestions.',
            ),
            TextFormField(
              key: const Key('decline-note'),
              controller: _note,
              maxLines: 3,
              maxLength: Limits.reviewNoteMax,
              decoration: const InputDecoration(
                labelText: 'Note for the Store Manager',
              ),
              validator: (v) => (v ?? '').trim().isEmpty
                  ? 'Say why, in up to ${Limits.reviewNoteMax} characters'
                  : null,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('decline-confirm'),
        onPressed: _saving ? null : _decline,
        child: const Text('Decline'),
      ),
    ],
  );
}

/// "Declined", the note and who decided, for a declined suggestion.
class DeclinedNote extends ConsumerWidget {
  const DeclinedNote({required this.product, super.key});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final by = product.reviewedBy;
    final name = [
      for (final u in ref.watch(usersProvider).value ?? const <AppUser>[])
        if (u.uid == by) u.name,
    ].firstOrNull;
    final note = product.reviewNote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Declined', key: Key('status-${product.id}')),
        if (note != null)
          Text(
            'Note: $note',
            key: Key('decline-note-${product.id}'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (by != null)
          Text(
            'By ${name ?? by}',
            key: Key('decline-by-${product.id}'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

/// Sets the price of a PENDING product and approves it
/// (`CatalogService.approve`).
class ApproveDialog extends ConsumerStatefulWidget {
  const ApproveDialog({required this.product, super.key});

  final Product product;

  @override
  ConsumerState<ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends ConsumerState<ApproveDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _price = TextEditingController(
    text: widget.product.proposedPrice?.format(symbol: '') ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  Future<void> _approve() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(catalogServiceProvider)
          .approve(
            productId: widget.product.id,
            price: parsePositiveMoney(_price.text)!,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      showMessage(context, '${widget.product.name} is approved.');
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, failureMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return AlertDialog(
      title: Text('Approve ${p.name}'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sold at ${scopeLabel(p.scope)}. The Store Manager proposed '
                '${p.proposedPrice?.format() ?? 'no price'}.',
              ),
              TextFormField(
                key: const Key('approve-price'),
                controller: _price,
                decoration: const InputDecoration(
                  labelText: 'Price (₹)',
                  prefixText: '₹ ',
                ),
                validator: (v) => parsePositiveMoney(v ?? '') == null
                    ? 'Enter a price above ₹0'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('approve-confirm'),
          onPressed: _saving ? null : _approve,
          child: const Text('Approve and set price'),
        ),
      ],
    );
  }
}

/// Raw materials, and adding one (`rawMaterial.create`).
class RawMaterialsTab extends ConsumerWidget {
  const RawMaterialsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canAdd =
        ref.watch(sessionProvider)?.can(Permission.rawMaterialCreate) ?? false;
    final async = ref.watch(rawMaterialsProvider);
    final materials = async.value;
    if (materials == null) {
      return async.hasError
          ? Center(child: Text('Could not load raw materials: ${async.error}'))
          : const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (canAdd)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('material-add'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AddMaterialDialog(),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add raw material'),
            ),
          ),
        DataTable(
          key: const Key('materials-table'),
          columns: const [
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Unit')),
            DataColumn(label: Text('Status')),
          ],
          rows: [
            for (final m in materials)
              DataRow(
                key: ValueKey('material-${m.id}'),
                cells: [
                  DataCell(Text(m.name)),
                  DataCell(Text(unitLabel(m.unit))),
                  DataCell(Text(m.active ? 'Active' : 'Inactive')),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class AddMaterialDialog extends ConsumerStatefulWidget {
  const AddMaterialDialog({super.key});

  @override
  ConsumerState<AddMaterialDialog> createState() => _AddMaterialDialogState();
}

class _AddMaterialDialogState extends ConsumerState<AddMaterialDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  StockUnit _unit = StockUnit.g;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final name = _name.text.trim();
    final taken = (ref.read(rawMaterialsProvider).value ?? const []).any(
      (m) => m.name.toLowerCase() == name.toLowerCase(),
    );
    if (taken) {
      showMessage(context, '$name already exists.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(catalogServiceProvider)
          .addRawMaterial(name: name, unit: _unit);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, failureMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add raw material'),
    content: SizedBox(
      width: 400,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('material-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter a name' : null,
            ),
            DropdownButtonFormField<StockUnit>(
              key: const Key('material-unit'),
              initialValue: _unit,
              decoration: const InputDecoration(
                labelText: 'Unit',
                helperText: 'Stock is counted in this base unit',
              ),
              items: [
                for (final u in StockUnit.values)
                  DropdownMenuItem(value: u, child: Text(unitLabel(u))),
              ],
              onChanged: (v) => setState(() => _unit = v!),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('material-save'),
        onPressed: _saving ? null : _save,
        child: const Text('Add'),
      ),
    ],
  );
}
