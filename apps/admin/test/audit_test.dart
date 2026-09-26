import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_admin/audit/audit_diff.dart';
import 'package:nexus_admin/audit/audit_screen.dart';
import 'package:nexus_admin/fakes/fake_backend.dart';
import 'package:nexus_admin/fakes/fake_services.dart';
import 'package:nexus_admin/shell/permission_guard.dart';
import 'package:nexus_core/nexus_core.dart';

import 'helpers.dart';

/// The seeded history (FakeBackend._seedAudit), at 10:00 IST unless noted:
///
///  0 LOCATION_UPDATE KTL 17 Aug · 1 USER_CREATE MNJ 27 Aug ·
///  2 USER_DISABLE PTB 1 Sep · 3 PRODUCT_APPROVE 5 Sep · 4 PRICE_CHANGE
///  12 Sep · 5 EXPENSE_CREATE PTB 14 Sep · 6 EXPENSE_UPDATE PTB 15 Sep ·
///  7 THRESHOLD_CHANGE MNJ 17 Sep (sm-MNJ) · 8 STOCK_ADJUST PTB 20 Sep
///  (sm-PTB) · 9 WASTAGE MNJ 22 Sep (sm-MNJ) · 10 OFFLINE_OVERRIDE MNJ
///  23 Sep (sm-MNJ) · 11 BILL_CANCEL PTB 24 Sep (sm-PTB) · 12 RETURN PTB
///  26 Sep 05:00 (sm-PTB). Entries 0 to 6 are by the Admin.
List<String> _rows(WidgetTester tester) => [
  for (final r
      in tester.widget<DataTable>(find.byKey(const Key('audit-table'))).rows)
    (r.key! as ValueKey<String>).value.replaceFirst('audit-seed-audit-', ''),
];

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

Future<void> _open(WidgetTester tester, FakeBackend backend) async {
  await pumpAdmin(tester, backend);
  await signIn(tester);
  await goTo(tester, '/audit');
}

Future<void> _pick(WidgetTester tester, String filter, String item) async {
  await tester.tap(find.byKey(Key(filter)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

void main() {
  late FakeBackend backend;
  setUp(() => backend = FakeBackend.seeded(today: testToday));

  testWidgets('lists every entry, newest first, with user names', (
    tester,
  ) async {
    await _open(tester, backend);

    expect(_rows(tester), [for (var i = 12; i >= 0; i--) '$i']);
    expect(_text(tester, 'audit-action-seed-audit-12'), 'Return');
    expect(find.text('Store Manager PTB'), findsWidgets);
    expect(find.text('26 Sep 2026, 5:00 AM'), findsOneWidget);
    expect(find.byKey(const Key('audit-truncated')), findsNothing);
  });

  testWidgets('filters by location and action, and clears', (tester) async {
    await _open(tester, backend);

    await _pick(tester, 'audit-location', 'Manjeri (MNJ)');
    expect(_rows(tester), ['10', '9', '7', '1']);
    expect(backend.audit.lastQuery!.locationId, 'MNJ');

    await _pick(tester, 'audit-action', 'Wastage');
    expect(_rows(tester), ['9']);
    expect(backend.audit.lastQuery!.action, AuditAction.wastage);

    await _pick(tester, 'audit-location', 'Pattambi (PTB)');
    expect(find.byKey(const Key('audit-empty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('audit-clear')));
    await tester.pumpAndSettle();
    expect(_rows(tester), hasLength(13));
    expect(find.byKey(const Key('audit-clear')), findsNothing);
  });

  testWidgets('filters by user', (tester) async {
    await _open(tester, backend);

    await _pick(
      tester,
      'audit-user',
      'Store Manager PTB (manager.ptb@caramelcottage.in)',
    );
    expect(_rows(tester), ['12', '11', '8']);
    expect(backend.audit.lastQuery!.userId, 'sm-PTB');
  });

  testWidgets('filters by an IST date range, both days included', (
    tester,
  ) async {
    await _open(tester, backend);

    await tester.tap(find.byKey(const Key('audit-dates')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('24').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('20 Sep 2026 – 24 Sep 2026'), findsOneWidget);
    expect(_rows(tester), ['11', '10', '9', '8']);
    final q = backend.audit.lastQuery!;
    // 20 Sep 00:00 IST to the end of 24 Sep IST.
    expect(q.from, DateTime.utc(2026, 9, 19, 18, 30));
    expect(
      q.to,
      DateTime.utc(
        2026,
        9,
        24,
        18,
        30,
      ).subtract(const Duration(microseconds: 1)),
    );
  });

  testWidgets('an entry opens its before/after diff', (tester) async {
    await _open(tester, backend);

    await tester.tap(find.text('Expense edited'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('audit-diff')), findsOneWidget);
    expect(_text(tester, 'diff-amount-before'), '₹6,200.00');
    expect(_text(tester, 'diff-amount-after'), '₹6,400.00');
    expect(_text(tester, 'diff-amount-kind'), 'changed');
    expect(_text(tester, 'diff-note-before'), 'Power');
    expect(_text(tester, 'diff-note-after'), 'Electricity');
    expect(_text(tester, 'diff-category-kind'), '');

    await tester.tap(find.byKey(const Key('audit-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('audit-diff')), findsNothing);

    // A create has only "after" values.
    await tester.tap(find.text('User created'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'diff-email-before'), '—');
    expect(_text(tester, 'diff-email-kind'), 'added');
  });

  testWidgets('says when only the newest page is shown', (tester) async {
    final at = DateTime.utc(2026, 9, 1);
    final busy = FakeBackend(
      auth: backend.auth,
      locations: backend.locations,
      summaries: backend.summaries,
      stock: backend.stock,
      catalog: backend.catalog,
      users: backend.users,
      audit: FakeAuditTrail(
        seeded: [
          for (var i = 0; i < AuditFilter.pageSize + 5; i++)
            AuditEntry(
              id: 'a$i',
              action: AuditAction.priceChange,
              entityPath: 'products/p$i',
              by: 'admin-0001',
              clientAt: at.add(Duration(minutes: i)),
            ),
        ],
      ),
    );
    await _open(tester, busy);
    expect(
      tester.widget<DataTable>(find.byKey(const Key('audit-table'))).rows,
      hasLength(AuditFilter.pageSize),
    );
    expect(find.byKey(const Key('audit-truncated')), findsOneWidget);
  });

  testWidgets('needs audit.view', (tester) async {
    await pumpAdmin(tester, backend);
    await signIn(tester, email: FakeBackend.storeManagerEmail);
    expect(find.text('Audit log'), findsNothing);
    await goTo(tester, '/audit');
    expect(find.byType(NotPermitted), findsOneWidget);
  });

  group('auditDiff', () {
    test('a create adds every field, nested maps flattened', () {
      final rows = auditDiff(null, {
        'amount': 500,
        'byMode': {'CASH': 300, 'UPI': 200},
      });
      expect(
        [for (final r in rows) r.path],
        ['amount', 'byMode.CASH', 'byMode.UPI'],
      );
      expect(rows.every((r) => r.kind == DiffKind.added), isTrue);
    });

    test('changed, unchanged, added and removed', () {
      final rows = {
        for (final r in auditDiff(
          {
            'price': 60000,
            'name': 'Cake',
            'old': true,
            'tags': [1, 2],
          },
          {
            'price': 65000,
            'name': 'Cake',
            'new': 'x',
            'tags': [1, 2],
          },
        ))
          r.path: r.kind,
      };
      expect(rows, {
        'name': DiffKind.unchanged,
        'new': DiffKind.added,
        'old': DiffKind.removed,
        'price': DiffKind.changed,
        'tags': DiffKind.unchanged,
      });
    });

    test('a field set to null is still a change', () {
      final rows = auditDiff({'lowThreshold': 5}, {'lowThreshold': null});
      expect(rows.single.kind, DiffKind.changed);
    });

    test('money fields are shown in rupees, others as they are', () {
      expect(formatDiffValue('price', 65000), '₹650.00');
      expect(formatDiffValue('lines.0.amount', 12050), '₹120.50');
      expect(formatDiffValue('lowThreshold', 3000), '3000');
      expect(formatDiffValue('active', false), 'false');
      expect(formatDiffValue('x', null), '—');
      expect(formatDiffValue('x', [1, 'a']), '[1,"a"]');
    });
  });

  test('the date filter covers whole IST days', () {
    final q = const AuditFilter(
      fromDate: '2026-09-20',
      toDate: '2026-09-20',
    ).toQuery();
    // 20 Sep 00:00 IST is 19 Sep 18:30 UTC; 23:59 IST is still in.
    expect(q.from, DateTime.utc(2026, 9, 19, 18, 30));
    expect(q.to!.isAfter(DateTime.utc(2026, 9, 20, 18, 29, 59)), isTrue);
    expect(q.to!.isBefore(DateTime.utc(2026, 9, 20, 18, 30)), isTrue);
    expect(q.limit, AuditFilter.pageSize);
  });
}
