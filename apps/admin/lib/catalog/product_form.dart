import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../common/dialogs.dart';
import '../common/model_copies.dart';
import '../data/providers.dart';
import 'catalog_providers.dart';

/// Creates a product, or edits [existing]. Returns the saved product, or
/// null when cancelled. A price change is audited by the data layer.
Future<Product?> showProductForm(BuildContext context, {Product? existing}) =>
    showDialog<Product>(
      context: context,
      builder: (_) => ProductForm(existing: existing),
    );

class ProductForm extends ConsumerStatefulWidget {
  const ProductForm({this.existing, super.key});

  final Product? existing;

  @override
  ConsumerState<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<ProductForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _price;
  late final TextEditingController _sort;
  late String _scope;
  bool _saving = false;

  Product? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final p = _existing;
    _name = TextEditingController(text: p?.name ?? '');
    _category = TextEditingController(text: p?.category ?? '');
    _price = TextEditingController(text: p?.price?.format(symbol: '') ?? '');
    _sort = TextEditingController(text: '${p?.sortOrder ?? 0}');
    _scope = p?.scope ?? Product.globalScope;
    _price.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _price.dispose();
    _sort.dispose();
    super.dispose();
  }

  bool get _priceChanged {
    final old = _existing?.price;
    if (old == null) return false;
    final now = parsePositiveMoney(_price.text);
    return now != null && now != old;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final price = parsePositiveMoney(_price.text)!;
    final sort = int.parse(_sort.text.trim());
    final product =
        _existing?.copyWith(
          name: _name.text.trim(),
          category: _category.text.trim(),
          price: price,
          scope: _scope,
          sortOrder: sort,
        ) ??
        Product(
          id: newProductId(),
          name: _name.text.trim(),
          category: _category.text.trim(),
          scope: _scope,
          status: ProductStatus.active,
          sortOrder: sort,
          createdBy: session.user.uid,
          price: price,
        );
    setState(() => _saving = true);
    try {
      final saved = await ref.read(catalogServiceProvider).save(product);
      if (mounted) Navigator.of(context).pop(saved);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, failureMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final locations = ref.watch(locationsProvider).value ?? const [];
    final scopes = <String>{
      Product.globalScope,
      for (final l in locations)
        if (l.active) l.code,
      _scope,
    };
    return AlertDialog(
      title: Text(_existing == null ? 'New product' : 'Edit product'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('product-name'),
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    helperText: 'Each size is its own product, e.g. "1 kg"',
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Enter a name' : null,
                ),
                TextFormField(
                  key: const Key('product-category'),
                  controller: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Enter a category' : null,
                ),
                TextFormField(
                  key: const Key('product-price'),
                  controller: _price,
                  decoration: const InputDecoration(
                    labelText: 'Price (₹)',
                    prefixText: '₹ ',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) => parsePositiveMoney(v ?? '') == null
                      ? 'Enter a price above ₹0, e.g. 350 or 349.50'
                      : null,
                ),
                if (_priceChanged)
                  Padding(
                    key: const Key('price-change-note'),
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Price change from ${_existing!.price!.format()}. '
                      'It is recorded in the audit log.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                DropdownButtonFormField<String>(
                  key: const Key('product-scope'),
                  initialValue: _scope,
                  decoration: const InputDecoration(labelText: 'Sold at'),
                  items: [
                    for (final s in scopes)
                      DropdownMenuItem(
                        value: s,
                        child: Text(
                          s == Product.globalScope
                              ? 'All locations'
                              : 'Only $s (local special)',
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _scope = v!),
                ),
                TextFormField(
                  key: const Key('product-sort'),
                  controller: _sort,
                  decoration: const InputDecoration(
                    labelText: 'Sort order',
                    helperText: 'Lower numbers come first on the POS',
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) => int.tryParse((v ?? '').trim()) == null
                      ? 'Enter a whole number'
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('product-save'),
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
