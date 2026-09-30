import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart' as cp;

/// Whether the device has a network connection. Only a hint: a sync pass
/// still proves the server is reachable with a server read before it moves
/// `lastSyncAt` (03-SYNC §6).
abstract interface class NetworkMonitor {
  /// The current state.
  Future<bool> isOnline();

  /// Emits on every change, with the new state.
  Stream<bool> get changes;
}

/// [NetworkMonitor] on `connectivity_plus`: online when any interface other
/// than `none` is up.
final class PlatformNetworkMonitor implements NetworkMonitor {
  PlatformNetworkMonitor([cp.Connectivity? connectivity])
    : _c = connectivity ?? cp.Connectivity();

  final cp.Connectivity _c;

  static bool _online(List<cp.ConnectivityResult> r) =>
      r.any((x) => x != cp.ConnectivityResult.none);

  @override
  Future<bool> isOnline() async {
    try {
      return _online(await _c.checkConnectivity());
    } on Object {
      return true; // Unknown: let the sync pass find out.
    }
  }

  @override
  Stream<bool> get changes => _c.onConnectivityChanged.map(_online).distinct();
}

/// A [NetworkMonitor] set by hand: tests, and the emulator test devices,
/// whose "network" is `disableNetwork` / `enableNetwork` on one Firestore
/// instance.
final class ManualNetworkMonitor implements NetworkMonitor {
  ManualNetworkMonitor({bool online = true}) : _online = online;

  bool _online;
  final _changes = StreamController<bool>.broadcast(sync: true);

  bool get online => _online;

  set online(bool value) {
    if (value == _online) return;
    _online = value;
    _changes.add(value);
  }

  @override
  Future<bool> isOnline() async => _online;

  @override
  Stream<bool> get changes => _changes.stream;
}
