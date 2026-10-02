import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../../app/providers.dart';
import '../../widgets/section_card.dart';

/// Where the receipt goes on WhatsApp (D-034).
enum WhatsappChoice { same, different, none }

/// What was typed in the Customer section. It lives in the payment page's
/// state, so going Back from the review keeps it.
final class CustomerForm {
  final TextEditingController name = TextEditingController();
  final TextEditingController phone = TextEditingController();
  final TextEditingController whatsapp = TextEditingController();
  WhatsappChoice choice = WhatsappChoice.same;

  /// Set when a suggestion was picked, until the mobile is edited again.
  bool suggestionsHidden = false;

  void dispose() {
    name.dispose();
    phone.dispose();
    whatsapp.dispose();
  }

  bool get _nameTouched => name.text.trim().isNotEmpty;
  bool get _phoneTouched => phone.text.trim().isNotEmpty;
  bool get _whatsappTouched => whatsapp.text.trim().isNotEmpty;

  /// Messages shown as you type: nothing on an empty field.
  String? get nameError =>
      _nameTouched ? CustomerValidator.nameError(name.text) : null;
  String? get phoneError =>
      _phoneTouched ? CustomerValidator.phoneError(phone.text) : null;
  String? get whatsappError =>
      choice == WhatsappChoice.different && _whatsappTouched
      ? CustomerValidator.phoneError(whatsapp.text)
      : null;

  /// The ten digits typed so far, or what was pasted with +91 cleaned.
  String get phoneDigits => CustomerValidator.cleanPhone(phone.text);

  /// The customer for the bill, or null until every field is valid.
  BillCustomer? get customer {
    if (CustomerValidator.nameError(name.text) != null ||
        CustomerValidator.phoneError(phone.text) != null) {
      return null;
    }
    final String? wa;
    switch (choice) {
      case WhatsappChoice.same:
        wa = phone.text;
      case WhatsappChoice.different:
        if (CustomerValidator.phoneError(whatsapp.text) != null) return null;
        wa = whatsapp.text;
      case WhatsappChoice.none:
        wa = null;
    }
    return BillCustomer(name: name.text, phone: phone.text, whatsapp: wa);
  }

  /// A pasted `+91 98765 43210` becomes the plain ten digits in the field.
  void tidyPhone(TextEditingController c) {
    final clean = CustomerValidator.cleanPhone(c.text);
    if (clean.length == 10 && clean != c.text) {
      c.value = TextEditingValue(
        text: clean,
        selection: TextSelection.collapsed(offset: clean.length),
      );
    }
  }

  /// Fills the form from a saved customer: name, mobile and the WhatsApp
  /// choice (same as the mobile, none, or a different number).
  void apply(Customer c) {
    name.text = c.name;
    phone.text = c.phone;
    final wa = c.whatsapp;
    if (wa == null) {
      choice = WhatsappChoice.none;
      whatsapp.clear();
    } else if (wa == c.phone) {
      choice = WhatsappChoice.same;
      whatsapp.clear();
    } else {
      choice = WhatsappChoice.different;
      whatsapp.text = wa;
    }
    suggestionsHidden = true;
  }
}

/// The Customer card on the payment page: name, mobile with saved
/// suggestions, and where WhatsApp goes (D-034, D-037).
class CustomerSection extends ConsumerWidget {
  const CustomerSection({
    required this.form,
    required this.onChanged,
    super.key,
  });

  final CustomerForm form;

  /// Called after any change, so the page can refresh its Save button.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final digits = form.phoneDigits;
    final suggestions = digits.length >= 3 && !form.suggestionsHidden
        ? ref.watch(customerSuggestionsProvider(digits)).value ??
              const <Customer>[]
        : const <Customer>[];
    return SectionCard(
      title: 'Customer',
      children: [
        TextField(
          key: const Key('customer-name'),
          controller: form.name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'Customer name',
            helperText: 'Required',
            errorText: form.nameError,
          ),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('customer-phone'),
          controller: form.phone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'Mobile number',
            helperText: 'Required, 10 digits',
            errorText: form.phoneError,
          ),
          onChanged: (_) {
            form
              ..suggestionsHidden = false
              ..tidyPhone(form.phone);
            onChanged();
          },
        ),
        if (suggestions.isNotEmpty)
          Column(
            key: const Key('customer-suggestions'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final c in suggestions)
                ListTile(
                  key: Key('customer-suggestion-${c.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(c.name),
                  subtitle: Text(c.phone),
                  onTap: () {
                    form.apply(c);
                    onChanged();
                  },
                ),
            ],
          ),
        const SizedBox(height: 12),
        Text('WhatsApp', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        // The labels are long for three segments on a phone, so each shrinks
        // to its third of the width instead of overflowing.
        LayoutBuilder(
          builder: (context, constraints) {
            final labelWidth = (constraints.maxWidth / 3 - 28).clamp(
              40.0,
              200.0,
            );
            Widget label(String text, String key) => SizedBox(
              width: labelWidth,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(text, key: Key(key)),
              ),
            );
            return SegmentedButton<WhatsappChoice>(
              segments: [
                ButtonSegment(
                  value: WhatsappChoice.same,
                  label: label('Same as mobile', 'wa-same'),
                ),
                ButtonSegment(
                  value: WhatsappChoice.different,
                  label: label('Different number', 'wa-different'),
                ),
                ButtonSegment(
                  value: WhatsappChoice.none,
                  label: label('No WhatsApp', 'wa-none'),
                ),
              ],
              selected: {form.choice},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                form.choice = s.single;
                onChanged();
              },
            );
          },
        ),
        if (form.choice == WhatsappChoice.different) ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('customer-whatsapp'),
            controller: form.whatsapp,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'WhatsApp number',
              errorText: form.whatsappError,
            ),
            onChanged: (_) {
              form.tidyPhone(form.whatsapp);
              onChanged();
            },
          ),
        ],
      ],
    );
  }
}
