import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../common/dialogs.dart';
import '../data/providers.dart';

/// Field rules for the location form, kept pure so they can be unit
/// tested.
abstract final class LocationRules {
  static const int minOfflineLimitHours = 1;
  static const int maxOfflineLimitHours = 72;
  static const int minExtensionHours = 1;
  static const int maxExtensionHours = 24;

  /// A new code: 2–4 uppercase letters, not already used.
  static String? code(String value, Iterable<String> taken) {
    final v = value.trim();
    if (!Ids.isLocationCode(v)) return 'Use 2 to 4 capital letters, e.g. PTB';
    if (taken.contains(v)) return '$v is already used';
    return null;
  }

  static String? required(String value, String what) =>
      value.trim().isEmpty ? 'Enter the $what' : null;

  static String? hours(String value, int min, int max) {
    final n = int.tryParse(value.trim());
    if (n == null || n < min || n > max) {
      return 'Enter whole hours from $min to $max';
    }
    return null;
  }

  /// Blank means no cap (D-011).
  static String? discountCap(String value) {
    if (value.trim().isEmpty) return null;
    final n = int.tryParse(value.trim());
    if (n == null || n < 0 || n > 100) return 'Enter 0 to 100, or leave blank';
    return null;
  }

  /// The override PIN. Required when [creating]; when editing, blank keeps
  /// the current one.
  static String? pin(String value, {required bool creating}) {
    if (value.isEmpty) return creating ? 'Set an override PIN' : null;
    if (!RegExp(r'^\d+$').hasMatch(value)) return 'Use digits only';
    if (value.length < Limits.minOverridePinDigits) {
      return 'Use at least ${Limits.minOverridePinDigits} digits';
    }
    return null;
  }

  static String? pinConfirm(String value, String pin) =>
      value == pin ? null : 'The PINs do not match';
}

/// Creates a location, or edits [existing]. Returns the saved location or
/// null. The PIN is passed only to `LocationService.save(newPin:)`: it is
/// never shown, kept, or written anywhere else. `nextDeviceNo` is not a
/// field here; only device registration changes it (D-004).
Future<Location?> showLocationForm(
  BuildContext context, {
  Location? existing,
}) => showDialog<Location>(
  context: context,
  builder: (_) => LocationForm(existing: existing),
);

class LocationForm extends ConsumerStatefulWidget {
  const LocationForm({this.existing, super.key});

  final Location? existing;

  @override
  ConsumerState<LocationForm> createState() => _LocationFormState();
}

class _LocationFormState extends ConsumerState<LocationForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _footer;
  late final TextEditingController _offline;
  late final TextEditingController _extension;
  late final TextEditingController _cap;
  final _pin = TextEditingController();
  final _pinConfirm = TextEditingController();
  late bool _active;
  bool _saving = false;

  Location? get _existing => widget.existing;
  bool get _creating => _existing == null;

  @override
  void initState() {
    super.initState();
    final l = _existing;
    _code = TextEditingController(text: l?.code ?? '');
    _name = TextEditingController(text: l?.name ?? '');
    _address = TextEditingController(text: l?.address ?? '');
    _phone = TextEditingController(text: l?.phone ?? '');
    _footer = TextEditingController(
      text: l?.receiptFooter ?? 'Thank you! Visit caramelcottage.in',
    );
    _offline = TextEditingController(
      text: '${l?.offlineLimitHours ?? Location.defaultOfflineLimitHours}',
    );
    _extension = TextEditingController(
      text:
          '${l?.overrideExtensionHours ?? Location.defaultOverrideExtensionHours}',
    );
    _cap = TextEditingController(text: l?.maxDiscountPct?.toString() ?? '');
    _active = l?.active ?? true;
  }

  @override
  void dispose() {
    for (final c in [
      _code,
      _name,
      _address,
      _phone,
      _footer,
      _offline,
      _extension,
      _cap,
      _pin,
      _pinConfirm,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final existing = _existing;
    final cap = _cap.text.trim();
    final location = Location(
      code: existing?.code ?? _code.text.trim(),
      name: _name.text.trim(),
      address: _address.text.trim(),
      phone: _phone.text.trim(),
      gstin: existing?.gstin,
      offlineLimitHours: int.parse(_offline.text.trim()),
      overrideExtensionHours: int.parse(_extension.text.trim()),
      maxDiscountPct: cap.isEmpty ? null : int.parse(cap),
      receiptFooter: _footer.text.trim(),
      active: _active,
      // The data layer keeps the stored hash unless a new PIN is given,
      // and never writes nextDeviceNo (LocationService.save).
      overridePinHash: existing?.overridePinHash ?? '',
      nextDeviceNo: existing?.nextDeviceNo ?? 0,
    );
    final pin = _pin.text;
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(locationServiceProvider)
          .save(location, newPin: pin.isEmpty ? null : pin);
      if (mounted) Navigator.of(context).pop(saved);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, failureMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final taken = [
      for (final l in ref.watch(locationsProvider).value ?? const <Location>[])
        l.code,
    ];
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return AlertDialog(
      title: Text(
        _creating
            ? 'New location'
            : 'Edit ${_existing!.name} (${_existing!.code})',
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  key: const Key('location-code'),
                  controller: _code,
                  enabled: _creating,
                  decoration: InputDecoration(
                    labelText: 'Code',
                    helperText: _creating
                        ? 'Printed on every bill number. It cannot be '
                              'changed later.'
                        : 'The code cannot be changed.',
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[A-Za-z]')),
                    LengthLimitingTextInputFormatter(4),
                    const _UpperCase(),
                  ],
                  validator: _creating
                      ? (v) => LocationRules.code(v ?? '', taken)
                      : null,
                ),
                TextFormField(
                  key: const Key('location-name'),
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) => LocationRules.required(v ?? '', 'name'),
                ),
                TextFormField(
                  key: const Key('location-address'),
                  controller: _address,
                  decoration: const InputDecoration(labelText: 'Address'),
                  validator: (v) => LocationRules.required(v ?? '', 'address'),
                ),
                TextFormField(
                  key: const Key('location-phone'),
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  keyboardType: TextInputType.phone,
                  validator: (v) => LocationRules.required(v ?? '', 'phone'),
                ),
                TextFormField(
                  key: const Key('location-footer'),
                  controller: _footer,
                  decoration: const InputDecoration(
                    labelText: 'Receipt footer',
                  ),
                  validator: (v) =>
                      LocationRules.required(v ?? '', 'receipt footer'),
                ),
                TextFormField(
                  key: const Key('location-offline-hours'),
                  controller: _offline,
                  decoration: const InputDecoration(
                    labelText: 'Offline limit (hours)',
                    helperText: 'Billing stops after this long without a sync',
                  ),
                  inputFormatters: digits,
                  validator: (v) => LocationRules.hours(
                    v ?? '',
                    LocationRules.minOfflineLimitHours,
                    LocationRules.maxOfflineLimitHours,
                  ),
                ),
                TextFormField(
                  key: const Key('location-extension-hours'),
                  controller: _extension,
                  decoration: const InputDecoration(
                    labelText: 'Override extension (hours)',
                    helperText: 'How long billing continues after the PIN',
                  ),
                  inputFormatters: digits,
                  validator: (v) => LocationRules.hours(
                    v ?? '',
                    LocationRules.minExtensionHours,
                    LocationRules.maxExtensionHours,
                  ),
                ),
                TextFormField(
                  key: const Key('location-discount-cap'),
                  controller: _cap,
                  decoration: const InputDecoration(
                    labelText: 'Discount cap (%)',
                    helperText: 'Leave blank for no cap',
                  ),
                  inputFormatters: digits,
                  validator: (v) => LocationRules.discountCap(v ?? ''),
                ),
                const SizedBox(height: 16),
                Text(
                  _creating ? 'Override PIN' : 'Change the override PIN',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  _creating
                      ? 'At least ${Limits.minOverridePinDigits} digits. '
                            'Store Managers enter it to keep billing when '
                            'offline too long.'
                      : 'Leave blank to keep the current PIN. A new one '
                            'needs at least ${Limits.minOverridePinDigits} '
                            'digits.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                TextFormField(
                  key: const Key('location-pin'),
                  controller: _pin,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'New PIN'),
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  validator: (v) =>
                      LocationRules.pin(v ?? '', creating: _creating),
                ),
                TextFormField(
                  key: const Key('location-pin-confirm'),
                  controller: _pinConfirm,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'New PIN again'),
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  validator: (v) =>
                      LocationRules.pinConfirm(v ?? '', _pin.text),
                ),
                if (!_creating)
                  SwitchListTile(
                    key: const Key('location-active'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    subtitle: const Text(
                      'Inactive locations are left out of reports',
                    ),
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
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
          key: const Key('location-save'),
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _UpperCase extends TextInputFormatter {
  const _UpperCase();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}
