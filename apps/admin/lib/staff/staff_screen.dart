import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../common/dialogs.dart';
import '../common/store_picker.dart';
import '../data/providers.dart';

/// Every staff member of one store, active or not (D-042).
final staffRosterProvider = StreamProvider.family<List<StaffMember>, String>(
  (ref, locationId) => ref.watch(staffRepositoryProvider).watchAll(locationId),
);

/// Active staff of one store, by name.
final activeStaffProvider = StreamProvider.family<List<StaffMember>, String>(
  (ref, locationId) =>
      ref.watch(staffRepositoryProvider).watchActive(locationId),
);

/// The roster per store: add a person, edit the name and role label,
/// deactivate or reactivate. Nobody is deleted (D-042). Changes need a
/// connection, so offline they fail with a message. The router guards the
/// page with `staff.manage`.
class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});

  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  String? _picked;

  Future<void> _add(String locationId) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _StaffDialog(locationId: locationId),
    );
    if (saved == true && mounted) showMessage(context, 'Staff member added.');
  }

  Future<void> _edit(String locationId, StaffMember s) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _StaffDialog(locationId: locationId, existing: s),
    );
    if (saved == true && mounted) showMessage(context, 'Changes saved.');
  }

  Future<void> _toggle(String locationId, StaffMember s) async {
    final deactivate = s.active;
    if (deactivate) {
      final ok = await confirmAction(
        context,
        title: 'Deactivate ${s.name}?',
        message:
            'They no longer appear on the attendance screen. Their past '
            'attendance stays. You can reactivate them at any time.',
        confirmLabel: 'Deactivate',
      );
      if (!ok || !mounted) return;
    }
    try {
      await ref
          .read(staffServiceProvider)
          .update(locationId: locationId, staffId: s.id, active: !deactivate);
      if (mounted) {
        showMessage(
          context,
          deactivate ? '${s.name} is deactivated.' : '${s.name} is active.',
        );
      }
    } on Object catch (e) {
      if (mounted) showMessage(context, failureMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locations = ref.watch(locationsProvider).value;
    if (locations == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final sorted = [...locations]..sort((a, b) => a.code.compareTo(b.code));
    if (sorted.isEmpty) {
      return const Center(child: Text('There are no stores yet.'));
    }
    final picked = _picked;
    final loc = picked != null && sorted.any((l) => l.code == picked)
        ? picked
        : defaultStore(sorted, ref.watch(selectedLocationProvider));
    final async = ref.watch(staffRosterProvider(loc));
    final staff = async.value;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Staff', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'The people who work at each store. They have no logins; the Store '
          'Manager marks their attendance. Nobody is deleted: a person who '
          'leaves is deactivated.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            KeyedSubtree(
              key: const Key('staff-store'),
              child: StorePicker(
                locations: sorted,
                value: loc,
                onChanged: (v) => setState(() => _picked = v),
              ),
            ),
            FilledButton.icon(
              key: const Key('staff-add'),
              icon: const Icon(Icons.person_add_alt_outlined),
              label: const Text('Add person'),
              onPressed: () => _add(loc),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (staff == null)
          async.hasError
              ? Text('Could not load the roster: ${async.error}')
              : const Center(child: CircularProgressIndicator())
        else if (staff.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No staff at this store yet. Add the first person.',
              key: Key('staff-empty'),
            ),
          )
        else ...[
          Text(
            '${staff.where((s) => s.active).length} active of ${staff.length}',
            key: const Key('staff-count'),
            style: theme.textTheme.bodySmall,
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              key: const Key('staff-table'),
              columnSpacing: 32,
              columns: const [
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Role')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('')),
              ],
              rows: [
                for (final s in staff)
                  DataRow(
                    key: ValueKey('staff-${s.id}'),
                    cells: [
                      DataCell(
                        Text(
                          s.name,
                          style: s.active
                              ? null
                              : TextStyle(color: theme.disabledColor),
                        ),
                      ),
                      DataCell(Text(s.role.isEmpty ? '—' : s.role)),
                      DataCell(Text(s.active ? 'Active' : 'Inactive')),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              key: Key('staff-edit-${s.id}'),
                              onPressed: () => _edit(loc, s),
                              child: const Text('Edit'),
                            ),
                            TextButton(
                              key: Key('staff-toggle-${s.id}'),
                              onPressed: () => _toggle(loc, s),
                              child: Text(
                                s.active ? 'Deactivate' : 'Reactivate',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Add or edit one person. Validates with `StaffMember.nameError` and
/// `roleError`; a failed save (offline, not permitted) shows its message and
/// keeps the dialog open.
class _StaffDialog extends ConsumerStatefulWidget {
  const _StaffDialog({required this.locationId, this.existing});

  final String locationId;
  final StaffMember? existing;

  @override
  ConsumerState<_StaffDialog> createState() => _StaffDialogState();
}

class _StaffDialogState extends ConsumerState<_StaffDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _role = TextEditingController(
    text: widget.existing?.role ?? '',
  );
  String? _nameError;
  String? _roleError;
  String? _failure;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nameError = StaffMember.nameError(_name.text);
    final roleError = StaffMember.roleError(_role.text);
    setState(() {
      _nameError = nameError;
      _roleError = roleError;
      _failure = null;
    });
    if (nameError != null || roleError != null) return;
    final name = StaffMember.cleanText(_name.text);
    final role = StaffMember.cleanText(_role.text);
    setState(() => _saving = true);
    try {
      final service = ref.read(staffServiceProvider);
      final existing = widget.existing;
      if (existing == null) {
        await service.create(
          locationId: widget.locationId,
          name: name,
          role: role,
        );
      } else {
        await service.update(
          locationId: widget.locationId,
          staffId: existing.id,
          name: name == existing.name ? null : name,
          role: role == existing.role ? null : role,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _failure = e is ArgumentError
              ? 'Check the details: ${e.message}'
              : failureMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Edit staff member' : 'Add staff member'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('staff-name'),
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: _nameError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('staff-role'),
              controller: _role,
              decoration: InputDecoration(
                labelText: 'Role (optional, e.g. Baker)',
                errorText: _roleError,
              ),
            ),
            if (_failure != null) ...[
              const SizedBox(height: 12),
              Text(
                _failure!,
                key: const Key('staff-form-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('staff-cancel'),
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('staff-save'),
          onPressed: _saving ? null : _save,
          child: Text(editing ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
