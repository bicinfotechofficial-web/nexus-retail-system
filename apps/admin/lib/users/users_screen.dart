import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../common/dialogs.dart';
import '../data/providers.dart';

/// Every user, by location. Store Managers are created with
/// `UserService.createStoreManager` (D-018) and disabled or enabled with
/// `setActive`. The router guards the page with `user.manage`.
final usersProvider = StreamProvider<List<AppUser>>(
  (ref) => ref.watch(userRepositoryProvider).watchUsers(),
);

/// A display name for a role ID. Display only; access is always checked
/// with permissions (D-017).
String roleLabel(String roleId) => switch (roleId) {
  SeedRoles.adminId => 'Admin',
  SeedRoles.storeManagerId => 'Store Manager',
  _ => roleId,
};

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  /// Null shows every user.
  String? _location;

  Future<void> _toggle(AppUser u) async {
    final disable = u.active;
    final ok = await confirmAction(
      context,
      title: disable ? 'Disable ${u.name}?' : 'Enable ${u.name}?',
      message: disable
          ? '${u.email} will be refused for every operation, on the POS and '
                'here, until you enable the account again.'
          : '${u.email} can sign in and work again.',
      confirmLabel: disable ? 'Disable' : 'Enable',
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(userServiceProvider).setActive(u.uid, active: !disable);
      if (mounted) {
        showMessage(
          context,
          disable ? '${u.name} is disabled.' : '${u.name} is enabled.',
        );
      }
    } on Object catch (e) {
      if (mounted) showMessage(context, failureMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final canManage = session?.can(Permission.userManage) ?? false;
    final locations = [...?ref.watch(locationsProvider).value]
      ..sort((a, b) => a.code.compareTo(b.code));
    final async = ref.watch(usersProvider);
    final users = async.value;
    if (users == null) {
      return async.hasError
          ? Center(child: Text('Could not load users: ${async.error}'))
          : const Center(child: CircularProgressIndicator());
    }
    final shown =
        [
          for (final u in users)
            if (_location == null || u.locationId == _location) u,
        ]..sort((a, b) {
          final l = (a.locationId ?? '').compareTo(b.locationId ?? '');
          return l != 0 ? l : a.name.compareTo(b.name);
        });

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Users',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (canManage)
              FilledButton.icon(
                key: const Key('user-add'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      CreateStoreManagerDialog(initialLocation: _location),
                ),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('New Store Manager'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 260,
            child: DropdownButtonFormField<String?>(
              key: const Key('users-location-filter'),
              initialValue: _location,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Location'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All locations'),
                ),
                for (final l in locations)
                  DropdownMenuItem<String?>(
                    value: l.code,
                    child: Text('${l.name} (${l.code})'),
                  ),
              ],
              onChanged: (v) => setState(() => _location = v),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No users at this location yet.'),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              key: const Key('users-table'),
              columnSpacing: 32,
              columns: const [
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Email')),
                DataColumn(label: Text('Role')),
                DataColumn(label: Text('Location')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('')),
              ],
              rows: [
                for (final u in shown)
                  DataRow(
                    cells: [
                      DataCell(Text(u.name, key: Key('user-${u.uid}'))),
                      DataCell(Text(u.email)),
                      DataCell(Text(roleLabel(u.roleId))),
                      DataCell(Text(u.locationId ?? 'All')),
                      DataCell(
                        Text(
                          u.active ? 'Active' : 'Disabled',
                          key: Key('user-status-${u.uid}'),
                        ),
                      ),
                      DataCell(
                        // Nobody disables their own account from here.
                        canManage && u.uid != session?.user.uid
                            ? TextButton(
                                key: Key('toggle-${u.uid}'),
                                onPressed: () => _toggle(u),
                                child: Text(u.active ? 'Disable' : 'Enable'),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Field rules for a new Store Manager.
abstract final class UserRules {
  /// Firebase Auth refuses shorter passwords.
  static const int minPasswordLength = 6;

  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? email(String value, Iterable<String> taken) {
    final v = value.trim().toLowerCase();
    if (!_email.hasMatch(v)) return 'Enter a valid email address';
    if (taken.any((t) => t.toLowerCase() == v)) {
      return 'A user with this email already exists';
    }
    return null;
  }

  static String? password(String value) => value.length < minPasswordLength
      ? 'Use at least $minPasswordLength characters'
      : null;
}

class CreateStoreManagerDialog extends ConsumerStatefulWidget {
  const CreateStoreManagerDialog({this.initialLocation, super.key});

  final String? initialLocation;

  @override
  ConsumerState<CreateStoreManagerDialog> createState() =>
      _CreateStoreManagerDialogState();
}

class _CreateStoreManagerDialogState
    extends ConsumerState<CreateStoreManagerDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  late String? _location = widget.initialLocation;
  bool _showPassword = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final user = await ref
          .read(userServiceProvider)
          .createStoreManager(
            name: _name.text.trim(),
            email: _email.text.trim().toLowerCase(),
            password: _password.text,
            locationId: _location!,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      showMessage(
        context,
        '${user.name} can now sign in to the POS with ${user.email}.',
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, failureMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final locations = [
      for (final l in ref.watch(locationsProvider).value ?? const <Location>[])
        if (l.active) l,
    ]..sort((a, b) => a.code.compareTo(b.code));
    final taken = [
      for (final u in ref.watch(usersProvider).value ?? const <AppUser>[])
        u.email,
    ];
    if (_location != null && !locations.any((l) => l.code == _location)) {
      _location = null;
    }
    return AlertDialog(
      title: const Text('New Store Manager'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('user-name'),
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Enter a name' : null,
                ),
                TextFormField(
                  key: const Key('user-email'),
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => UserRules.email(v ?? '', taken),
                ),
                TextFormField(
                  key: const Key('user-password'),
                  controller: _password,
                  obscureText: !_showPassword,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Initial password',
                    helperText: 'Share it with the Store Manager in person',
                    suffixIcon: IconButton(
                      tooltip: _showPassword ? 'Hide' : 'Show',
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  validator: (v) => UserRules.password(v ?? ''),
                ),
                DropdownButtonFormField<String>(
                  key: const Key('user-location'),
                  initialValue: _location,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Location'),
                  items: [
                    for (final l in locations)
                      DropdownMenuItem(
                        value: l.code,
                        child: Text('${l.name} (${l.code})'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _location = v),
                  validator: (v) => v == null ? 'Choose a location' : null,
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
          key: const Key('user-save'),
          onPressed: _saving ? null : _save,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
