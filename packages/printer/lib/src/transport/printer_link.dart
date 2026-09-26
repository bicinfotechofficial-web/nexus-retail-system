import 'dart:async';
import 'dart:math' as math;

import '../api.dart';
import 'printer_transport.dart';

/// Sends one print job at a time over a [PrinterTransport]: connects when
/// needed, writes in chunks with a timeout, and makes one reconnect attempt
/// per job. Never throws; every failure is a [PrintFailed] (the bill is
/// already saved, POS-6 offers a retry).
final class PrinterLink {
  PrinterLink(
    this._transport, {
    this.chunkSize = 512,
    this.connectTimeout = const Duration(seconds: 10),
    this.writeTimeout = const Duration(seconds: 5),
  }) : assert(chunkSize > 0, 'chunkSize: $chunkSize');

  final PrinterTransport _transport;

  /// Bytes per write. Small enough for cheap printers' input buffers.
  final int chunkSize;
  final Duration connectTimeout;

  /// Per chunk.
  final Duration writeTimeout;

  /// The address of the open socket, or null.
  String? _connectedTo;
  Future<void> _queue = Future.value();

  static const String bluetoothOff = 'Bluetooth is off';
  static const String cannotConnect = 'Could not connect to the printer';
  static const String stoppedResponding = 'The printer stopped responding';

  /// Whether the last job left the socket to [address] open.
  bool isConnectedTo(String address) => _connectedTo == address;

  /// Connects to [address] without printing, e.g. right after the printer
  /// is chosen. Uses the same single retry as [send].
  Future<bool> open(String address) => _serial(() async {
    if (_connectedTo == address) return true;
    return await _connect(address) || await _reconnect(address);
  });

  /// Prints [bytes] on the printer at [address].
  ///
  /// When a write fails or times out, the link reconnects once and resends
  /// from the chunk that failed, so a slip is never cut short silently; at
  /// worst a few lines print twice.
  Future<PrintResult> send(String address, List<int> bytes) =>
      _serial(() async {
        if (!await _guard(_transport.isBluetoothOn(), connectTimeout)) {
          _connectedTo = null;
          return const PrintFailed(bluetoothOff);
        }
        var retried = false;
        if (_connectedTo != address && !await _connect(address)) {
          retried = true;
          if (!await _reconnect(address)) {
            return const PrintFailed(cannotConnect);
          }
        }
        var offset = 0;
        while (offset < bytes.length) {
          final end = math.min(offset + chunkSize, bytes.length);
          final chunk = bytes.sublist(offset, end);
          if (await _guard(_transport.write(chunk), writeTimeout)) {
            offset = end;
            continue;
          }
          if (retried || !await _reconnect(address)) {
            await _drop();
            return const PrintFailed(stoppedResponding);
          }
          retried = true;
        }
        return const Printed();
      });

  /// Closes the socket.
  Future<void> close() => _serial(_drop);

  Future<bool> _connect(String address) async {
    if (_connectedTo != null) await _drop();
    final ok = await _guard(_transport.connect(address), connectTimeout);
    _connectedTo = ok ? address : null;
    return ok;
  }

  Future<bool> _reconnect(String address) async {
    await _drop();
    return _connect(address);
  }

  Future<void> _drop() async {
    _connectedTo = null;
    try {
      await _transport.disconnect().timeout(connectTimeout);
    } on Object {
      // Already gone; nothing to do.
    }
  }

  /// [call]'s result, or false when it throws or takes longer than
  /// [timeout].
  static Future<bool> _guard(Future<bool> call, Duration timeout) async {
    try {
      return await call.timeout(timeout);
    } on Object {
      return false;
    }
  }

  /// Runs jobs one after another, so two prints never interleave.
  Future<T> _serial<T>(Future<T> Function() job) {
    final result = _queue.then((_) => job());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}
