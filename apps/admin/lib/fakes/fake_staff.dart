import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'live.dart';

/// An in-memory roster that is both the `StaffRepository` and the
/// `StaffService`, for the Admin's widget tests. Set [offline] to make the
/// service fail as it does without a connection.
final class FakeStaffStore implements StaffRepository, StaffService {
  FakeStaffStore([Map<String, List<StaffMember>> seed = const {}])
    : _byStore = Live({for (final e in seed.entries) e.key: List.of(e.value)});

  final Live<Map<String, List<StaffMember>>> _byStore;
  bool offline = false;
  int _next = 1;

  /// Every `create` and `update` that reached the service.
  final List<String> calls = [];

  List<StaffMember> of(String locationId) =>
      _byStore.value[locationId] ?? const [];

  static List<StaffMember> _sorted(Iterable<StaffMember> s) =>
      [...s]..sort((a, b) => a.name.compareTo(b.name));

  @override
  Stream<List<StaffMember>> watchAll(String locationId) =>
      _byStore.watch((m) => _sorted(m[locationId] ?? const []));

  @override
  Stream<List<StaffMember>> watchActive(String locationId) => _byStore.watch(
    (m) => _sorted((m[locationId] ?? const []).where((s) => s.active)),
  );

  void _write(String loc, List<StaffMember> list) {
    _byStore.value = {..._byStore.value, loc: list};
  }

  @override
  Future<StaffMember> create({
    required String locationId,
    required String name,
    String role = '',
  }) async {
    calls.add('create $locationId $name');
    if (offline) throw const DataFailure(FailureReason.offline);
    final problem = StaffMember.nameError(name) ?? StaffMember.roleError(role);
    if (problem != null) throw ArgumentError(problem);
    final member = StaffMember(
      id: 'new${_next++}',
      name: StaffMember.cleanText(name),
      role: StaffMember.cleanText(role),
      active: true,
      locationId: locationId,
    );
    _write(locationId, [...of(locationId), member]);
    return member;
  }

  @override
  Future<void> update({
    required String locationId,
    required String staffId,
    String? name,
    String? role,
    bool? active,
  }) async {
    calls.add('update $locationId $staffId');
    if (offline) throw const DataFailure(FailureReason.offline);
    _write(locationId, [
      for (final s in of(locationId))
        if (s.id == staffId)
          StaffMember(
            id: s.id,
            name: name ?? s.name,
            role: role ?? s.role,
            active: active ?? s.active,
            locationId: locationId,
          )
        else
          s,
    ]);
  }
}
