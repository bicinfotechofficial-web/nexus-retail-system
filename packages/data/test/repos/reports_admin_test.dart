import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'docs.dart';

void main() {
  late FakeFirebaseFirestore db;
  setUp(() => db = FakeFirebaseFirestore());

  group('FirestoreSummaryRepository', () {
    late FirestoreSummaryRepository repo;

    Summary sales(int bills) => Summary(
      billCount: bills,
      grossSales: Money(bills * 10000),
      netSales: Money(bills * 10000),
      byMode: {PaymentMode.cash: Money(bills * 10000)},
      byProduct: {'bf1kg': ProductTally(qty: bills, amount: Money(bills))},
      lastWriteRef: 'locations/PTB/bills/D01-000001',
    );

    Future<void> putDaily(String loc, String day, int bills) =>
        put(db, FirestorePaths.dailySummary(loc, day), sales(bills).toMap());

    Future<void> putMonthly(String loc, String month, int bills) => put(
      db,
      FirestorePaths.monthlySummary(loc, month),
      sales(bills).toMap(),
    );

    setUp(() async {
      repo = FirestoreSummaryRepository(db);
      await putDaily('PTB', '2026-08-31', 1);
      await putDaily('PTB', '2026-09-01', 2);
      await putDaily('PTB', '2026-09-15', 3);
      await putDaily('PTB', '2026-09-30', 4);
      await putDaily('PTB', '2026-10-01', 5);
      await putDaily('MNJ', '2026-09-15', 9);
      await putMonthly('PTB', '2025-11', 1);
      await putMonthly('PTB', '2025-12', 2);
      await putMonthly('PTB', '2026-01', 3);
      await putMonthly('PTB', '2026-02', 4);
    });

    test('watchDaily reads a day and follows increments', () async {
      final seen = <int>[];
      final sub = repo
          .watchDaily('PTB', '2026-09-15')
          .listen((s) => seen.add(s.billCount));
      await pumpEventQueue();
      await db.doc(FirestorePaths.dailySummary('PTB', '2026-09-15')).update({
        'billCount': 4,
      });
      await pumpEventQueue();
      await sub.cancel();
      expect(seen, [3, 4]);
    });

    test('watchDaily of a day without sales is an empty summary', () async {
      final s = await repo.watchDaily('PTB', '2026-09-02').first;
      expect(s.billCount, 0);
      expect(s.netRevenue, Money.zero);
    });

    test('daily: the month of September, both ends included', () async {
      final days = await repo.daily('PTB', '2026-09-01', '2026-09-30');
      expect(days.keys, ['2026-09-01', '2026-09-15', '2026-09-30']);
      expect(days['2026-09-15']!.byMode[PaymentMode.cash], const Money(30000));
      expect(days['2026-09-15']!.byProduct['bf1kg']!.qty, 3);
    });

    test('daily: one day, and an empty or reversed range', () async {
      expect((await repo.daily('PTB', '2026-09-15', '2026-09-15')).keys, [
        '2026-09-15',
      ]);
      expect(await repo.daily('PTB', '2026-09-02', '2026-09-14'), isEmpty);
      expect(await repo.daily('PTB', '2026-09-30', '2026-09-01'), isEmpty);
      expect(await repo.daily('XYZ', '2026-01-01', '2026-12-31'), isEmpty);
    });

    test('monthly across a year boundary', () async {
      final months = await repo.monthly('PTB', '2025-12', '2026-01');
      expect(months.keys, ['2025-12', '2026-01']);
      final year = await repo.monthly('PTB', '2026-01', '2026-12');
      final total = year.values.fold(const Summary(), (a, b) => a + b);
      expect(total.billCount, 7);
    });
  });

  group('FirestoreAuditRepository', () {
    late FirestoreAuditRepository repo;
    final t0 = ist(2026, 9, 25, 9);

    setUp(() async {
      repo = FirestoreAuditRepository(db);
      final entries = [
        (
          audit(
            'PTB-D01-000001-X',
            action: AuditAction.billCancel,
            at: t0,
            locationId: 'PTB',
            by: 'sm1',
          ),
          t0,
        ),
        (
          audit(
            'PTB-D01-R000001',
            action: AuditAction.returned,
            at: t0,
            locationId: 'PTB',
            by: 'sm1',
          ),
          t0.add(const Duration(hours: 1)),
        ),
        (
          audit(
            'MNJ-D01-M000001',
            action: AuditAction.wastage,
            at: t0,
            locationId: 'MNJ',
            by: 'sm2',
          ),
          t0.add(const Duration(hours: 2)),
        ),
        (
          audit(
            'EXP-rent-1',
            action: AuditAction.expenseCreate,
            at: t0,
            locationId: 'PTB',
          ),
          t0.add(const Duration(hours: 3)),
        ),
        (
          audit('prod-x', action: AuditAction.priceChange, at: t0),
          t0.add(const Duration(days: 1)),
        ),
      ];
      for (final (a, at) in entries) {
        await putAudit(db, a, at);
      }
    });

    Future<List<String>> ids(AuditQuery q) async => [
      for (final e in await repo.query(q)) e.id,
    ];

    test('newest first, and before/after maps convert', () async {
      final all = await repo.query(const AuditQuery());
      expect(all.map((e) => e.id), [
        'prod-x',
        'EXP-rent-1',
        'MNJ-D01-M000001',
        'PTB-D01-R000001',
        'PTB-D01-000001-X',
      ]);
      expect(all.last.at!.isAtSameMomentAs(t0), isTrue);
      expect(all.last.before!['when'], isA<DateTime>());
    });

    test('filters by location, user and action, alone and together', () async {
      expect(await ids(const AuditQuery(locationId: 'PTB')), [
        'EXP-rent-1',
        'PTB-D01-R000001',
        'PTB-D01-000001-X',
      ]);
      expect(await ids(const AuditQuery(userId: 'sm2')), ['MNJ-D01-M000001']);
      expect(await ids(const AuditQuery(action: AuditAction.priceChange)), [
        'prod-x',
      ]);
      expect(
        await ids(
          const AuditQuery(
            locationId: 'PTB',
            userId: 'sm1',
            action: AuditAction.returned,
          ),
        ),
        ['PTB-D01-R000001'],
      );
    });

    test('from and to are both inclusive', () async {
      final to = t0.add(const Duration(hours: 2));
      expect(
        await ids(AuditQuery(from: t0.add(const Duration(hours: 1)), to: to)),
        ['MNJ-D01-M000001', 'PTB-D01-R000001'],
      );
      expect(
        await ids(AuditQuery(to: to.subtract(const Duration(microseconds: 1)))),
        ['PTB-D01-R000001', 'PTB-D01-000001-X'],
      );
    });

    test('an IST day as the admin screen asks for it', () async {
      // From the IST midnight that starts the day to its last microsecond.
      final q = AuditQuery(
        from: BusinessDate.startOf('2026-09-25'),
        to: BusinessDate.startOf(
          '2026-09-26',
        ).subtract(const Duration(microseconds: 1)),
      );
      expect((await ids(q)).length, 4);
    });

    test('limit counts matching entries', () async {
      expect(await ids(const AuditQuery(limit: 2)), ['prod-x', 'EXP-rent-1']);
      expect(await ids(const AuditQuery(locationId: 'PTB', limit: 1)), [
        'EXP-rent-1',
      ]);
      expect(await ids(const AuditQuery(limit: 0)), isEmpty);
    });
  });

  group('FirestoreLocationRepository', () {
    test('every location by code, and one by ID', () async {
      final repo = FirestoreLocationRepository(db);
      for (final l in [location('PTB'), location('MNJ'), location('ABC')]) {
        await put(db, FirestorePaths.location(l.code), l.toMap());
      }
      final all = await repo.watchLocations().first;
      expect(all.map((l) => l.code), ['ABC', 'MNJ', 'PTB']);
      expect((await repo.watchLocation('PTB').first)!.name, 'Store PTB');
      expect(await repo.watchLocation('XYZ').first, isNull);
    });
  });

  group('FirestoreUserRepository', () {
    test('all users or one location, by name', () async {
      final repo = FirestoreUserRepository(db);
      for (final u in [
        appUser('u1', name: 'zed'),
        appUser('u2', name: 'Anna', locationId: 'MNJ'),
        appUser('u3', name: 'bob'),
        appUser(
          'admin1',
          name: 'Admin',
          locationId: null,
          roleId: SeedRoles.adminId,
        ),
      ]) {
        await put(
          db,
          FirestorePaths.user(u.uid),
          u.toMap(),
          serverTimes: {'createdAt': DateTime.utc(2026)},
        );
      }
      final all = await repo.watchUsers().first;
      expect(all.map((u) => u.uid), ['admin1', 'u2', 'u3', 'u1']);
      final ptb = await repo.watchUsers(locationId: 'PTB').first;
      expect(ptb.map((u) => u.uid), ['u3', 'u1']);
    });
  });

  group('FirestoreExpenseRepository', () {
    late FirestoreExpenseRepository repo;

    setUp(() async {
      repo = FirestoreExpenseRepository(db);
      for (final e in [
        expense('a', locationId: 'PTB', date: '2026-08-31'),
        expense('b', locationId: 'PTB', date: '2026-09-01'),
        expense('c', locationId: 'PTB', date: '2026-09-30'),
        expense('d', locationId: 'PTB', date: '2026-10-01'),
        expense('e', locationId: 'MNJ', date: '2026-09-15'),
      ]) {
        await putExpense(db, e);
      }
    });

    Future<List<String>> ids({String? loc, String? month}) async => [
      for (final e
          in await repo.watchExpenses(locationId: loc, monthKey: month).first)
        e.id,
    ];

    test('one location and month, newest date first', () async {
      expect(await ids(loc: 'PTB', month: '2026-09'), ['c', 'b']);
    });

    test('a month across locations, or a location across months', () async {
      expect(await ids(month: '2026-09'), ['c', 'e', 'b']);
      expect(await ids(loc: 'PTB'), ['d', 'c', 'b', 'a']);
      expect(await ids(), ['d', 'c', 'e', 'b', 'a']);
    });

    test('reads amounts and timestamps', () async {
      final e = (await repo.watchExpenses(locationId: 'MNJ').first).single;
      expect(e.amount, const Money(100000));
      expect(e.category, ExpenseCategory.rent);
      expect(e.createdAt, isNotNull);
    });

    test('rejects a malformed month', () {
      expect(() => repo.watchExpenses(monthKey: '2026-9'), throwsArgumentError);
    });
  });
}
