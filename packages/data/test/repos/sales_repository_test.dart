import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_data/nexus_data.dart';

import 'docs.dart';

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreSalesRepository repo;

  // The IST day 2026-09-25 runs from 2026-09-24T18:30Z to 2026-09-25T18:30Z.
  final dayStart = ist(2026, 9, 25);
  final lastSecond = ist(2026, 9, 25, 23, 59, 59);
  final nextMidnight = ist(2026, 9, 26);
  final midday = ist(2026, 9, 25, 12);

  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = FirestoreSalesRepository(db);
    await putBill(db, 'PTB', bill('PTB', 'D01', 1, dayStart));
    await putBill(db, 'PTB', bill('PTB', 'D02', 7, midday));
    await putBill(db, 'PTB', bill('PTB', 'D01', 2, lastSecond));
    await putBill(db, 'PTB', bill('PTB', 'D01', 3, nextMidnight));
    await putBill(db, 'MNJ', bill('MNJ', 'D01', 1, midday));
  });

  group('watchBills', () {
    test('one IST business day, newest first, this location only', () async {
      final bills = await repo.watchBills('PTB', '2026-09-25').first;
      expect(bills.map((b) => b.billNo), [
        'PTB-D01-000002',
        'PTB-D02-000007',
        'PTB-D01-000001',
      ]);
      expect(bills.every((b) => b.businessDate == '2026-09-25'), isTrue);
    });

    test('IST midnight starts the next day', () async {
      final next = await repo.watchBills('PTB', '2026-09-26').first;
      expect(next.map((b) => b.id), ['D01-000003']);
      expect(await repo.watchBills('PTB', '2026-09-24').first, isEmpty);
    });

    test('emits again when a bill is added', () async {
      final seen = <int>[];
      final sub = repo
          .watchBills('PTB', '2026-09-25')
          .listen((l) => seen.add(l.length));
      await pumpEventQueue();
      await putBill(db, 'PTB', bill('PTB', 'D02', 8, ist(2026, 9, 25, 13)));
      await pumpEventQueue();
      await sub.cancel();
      expect(seen.last, 4);
    });
  });

  group('getBill', () {
    test('reads one bill with its timestamps', () async {
      final b = await repo.getBill('PTB', 'D02-000007');
      expect(b!.billNo, 'PTB-D02-000007');
      expect(b.clientCreatedAt.isAtSameMomentAs(midday), isTrue);
      expect(b.serverCreatedAt!.isAtSameMomentAs(midday), isTrue);
      expect(b.soldQty, {'bf1kg': 1});
    });

    test('null when missing or at another location', () async {
      expect(await repo.getBill('PTB', 'D09-000001'), isNull);
      expect(await repo.getBill('MNJ', 'D02-000007'), isNull);
    });
  });

  group('findByBillNo', () {
    test('finds the bill at the location in its number', () async {
      final ptb = await repo.findByBillNo('PTB-D01-000002');
      expect(ptb!.id, 'D01-000002');
      final mnj = await repo.findByBillNo('MNJ-D01-000001');
      expect(mnj!.billNo, 'MNJ-D01-000001');
    });

    test('accepts spaces and lower case', () async {
      final b = await repo.findByBillNo('  ptb-d02-000007 ');
      expect(b!.billNo, 'PTB-D02-000007');
    });

    test('null for an unknown or malformed number', () async {
      for (final s in [
        'PTB-D01-000099',
        'PTB-D01-123',
        'PTB-D01-0000002',
        'PTB-D1-000002',
        'PTBXX-D01-000002',
        'PTB-D01',
        'D01-000002',
        'PTB-D01-000000',
        'PTB-D01-00000A',
        '',
      ]) {
        expect(await repo.findByBillNo(s), isNull, reason: s);
      }
    });

    test('parseBillNo splits with Ids', () {
      expect(parseBillNo('PTB-D01-000123'), (
        billNo: 'PTB-D01-000123',
        locationId: 'PTB',
        billId: 'D01-000123',
      ));
      expect(parseBillNo('AB-D99-999999')?.locationId, 'AB');
      expect(parseBillNo('PTB-D01-000123-X'), isNull);
    });
  });

  group('returns', () {
    setUp(() async {
      await putReturn(
        db,
        'PTB',
        saleReturn('PTB', 'D01', 1, 'D01-000001', ist(2026, 9, 25, 10)),
      );
      await putReturn(
        db,
        'PTB',
        saleReturn('PTB', 'D02', 1, 'D01-000001', lastSecond),
      );
      await putReturn(
        db,
        'PTB',
        saleReturn('PTB', 'D01', 2, 'D02-000007', nextMidnight),
      );
      await putReturn(
        db,
        'MNJ',
        saleReturn('MNJ', 'D01', 1, 'D01-000001', midday),
      );
    });

    test('by the day they were processed, newest first', () async {
      final day = await repo.watchReturns('PTB', '2026-09-25').first;
      expect(day.map((r) => r.id), ['D02-R000001', 'D01-R000001']);
      final next = await repo.watchReturns('PTB', '2026-09-26').first;
      expect(next.map((r) => r.id), ['D01-R000002']);
    });

    test('for one bill, oldest first', () async {
      final rs = await repo.returnsForBill('PTB', 'D01-000001');
      expect(rs.map((r) => r.id), ['D01-R000001', 'D02-R000001']);
      expect(rs.first.billNo, 'PTB-D01-000001');
      expect(await repo.returnsForBill('PTB', 'D01-000002'), isEmpty);
    });
  });
}
