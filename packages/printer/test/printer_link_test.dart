import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_printer/src/api.dart';
import 'package:nexus_printer/src/transport/printer_link.dart';

import 'fake_transport.dart';

const String mac = '66:02:BD:06:18:7B';
final List<int> job = List.generate(1200, (i) => i % 256);

void main() {
  late FakeTransport transport;
  late PrinterLink link;

  setUp(() {
    transport = FakeTransport();
    link = PrinterLink(transport, chunkSize: 500);
  });

  test('connects once and writes in chunks', () async {
    expect(await link.send(mac, job), isA<Printed>());
    expect(transport.calls, [
      'connect $mac',
      'write 500',
      'write 500',
      'write 200',
    ]);
    expect(transport.printed, job);
    expect(link.isConnectedTo(mac), isTrue);
  });

  test('keeps the socket open between jobs', () async {
    await link.send(mac, [1]);
    await link.send(mac, [2]);
    expect(transport.connects, 1);
  });

  test('switching printers closes the old socket first', () async {
    await link.send(mac, [1]);
    await link.send('AA:BB:CC:DD:EE:FF', [2]);
    expect(transport.calls, [
      'connect $mac',
      'write 1',
      'disconnect',
      'connect AA:BB:CC:DD:EE:FF',
      'write 1',
    ]);
  });

  test('Bluetooth off fails without connecting', () async {
    transport.bluetoothOn = false;
    final r = await link.send(mac, job);
    expect((r as PrintFailed).reason, PrinterLink.bluetoothOff);
    expect(transport.connects, 0);
  });

  test('a failed connect is retried once', () async {
    transport.connectResults.add(false);
    expect(await link.send(mac, job), isA<Printed>());
    expect(transport.connects, 2);
    expect(transport.printed, job);
  });

  test('two failed connects give PrintFailed', () async {
    transport.connectResults.addAll([false, false]);
    final r = await link.send(mac, job);
    expect((r as PrintFailed).reason, PrinterLink.cannotConnect);
    expect(transport.connects, 2);
    expect(link.isConnectedTo(mac), isFalse);
  });

  test('a failed write reconnects once and resends from that chunk', () async {
    transport.writeOutcomes.addAll([WriteOutcome.ok, WriteOutcome.fail]);
    expect(await link.send(mac, job), isA<Printed>());
    expect(transport.calls, [
      'connect $mac',
      'write 500',
      'write 500',
      'disconnect',
      'connect $mac',
      'write 500',
      'write 200',
    ]);
    expect(transport.printed, job);
  });

  test('a write that throws is treated as a failed write', () async {
    transport.writeOutcomes.add(WriteOutcome.throws);
    expect(await link.send(mac, job), isA<Printed>());
    expect(transport.connects, 2);
    expect(transport.printed, job);
  });

  test('only one reconnect per job', () async {
    transport.writeOutcomes.addAll([WriteOutcome.fail, WriteOutcome.fail]);
    final r = await link.send(mac, job);
    expect((r as PrintFailed).reason, PrinterLink.stoppedResponding);
    expect(transport.connects, 2);
    expect(transport.calls.last, 'disconnect');
    expect(link.isConnectedTo(mac), isFalse);
  });

  test('a job after a failure reconnects and succeeds', () async {
    transport.writeOutcomes.addAll([WriteOutcome.fail, WriteOutcome.fail]);
    await link.send(mac, job);
    transport.printed.clear();
    expect(await link.send(mac, job), isA<Printed>());
    expect(transport.printed, job);
  });

  test('a write that hangs times out, then reconnects', () {
    fakeAsync((clock) {
      // Built inside the fake zone, so its job queue runs on the fake clock.
      final link = PrinterLink(transport, chunkSize: 500);
      transport.writeOutcomes.add(WriteOutcome.hang);
      PrintResult? result;
      link.send(mac, job).then((r) => result = r).ignore();
      clock.elapse(const Duration(seconds: 4));
      expect(result, isNull);
      clock.elapse(const Duration(seconds: 2));
      expect(result, isA<Printed>());
      expect(transport.connects, 2);
      expect(transport.printed, job);
    });
  });

  test('a connect after a failed job still has only one retry', () async {
    transport.connectResults.add(false);
    transport.writeOutcomes.add(WriteOutcome.fail);
    final r = await link.send(mac, job);
    expect((r as PrintFailed).reason, PrinterLink.stoppedResponding);
    expect(transport.connects, 2);
  });

  test('jobs never interleave', () async {
    final a = link.send(mac, List.filled(1000, 1));
    final b = link.send(mac, List.filled(1000, 2));
    await Future.wait([a, b]);
    expect(transport.printed, [
      ...List.filled(1000, 1),
      ...List.filled(1000, 2),
    ]);
  });

  test('open connects without writing, and close disconnects', () async {
    expect(await link.open(mac), isTrue);
    expect(await link.open(mac), isTrue);
    expect(transport.calls, ['connect $mac']);
    await link.close();
    expect(link.isConnectedTo(mac), isFalse);
    expect(transport.calls.last, 'disconnect');
  });

  test('open fails after one retry', () async {
    transport.connectResults.addAll([false, false]);
    expect(await link.open(mac), isFalse);
    expect(transport.connects, 2);
  });
}
