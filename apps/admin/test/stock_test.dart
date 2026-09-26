import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_admin/fakes/fake_backend.dart';
import 'package:nexus_admin/fakes/fake_repositories.dart';
import 'package:nexus_admin/stock/stock_screen.dart';
import 'package:nexus_core/nexus_core.dart';

import 'helpers.dart';

Future<void> _openStock(
  WidgetTester tester,
  FakeBackend backend, {
  String email = FakeBackend.adminEmail,
}) async {
  await pumpAdmin(tester, backend);
  await signIn(tester, email: email);
  await goTo(tester, '/stock');
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

StockItem _item(String id, int qty, int? threshold) => StockItem(
  itemKey: 'RM_$id',
  kind: StockKind.raw,
  refId: id,
  name: id,
  unit: StockUnit.g,
  qty: qty,
  lowThreshold: threshold,
);

void main() {
  late FakeBackend backend;
  setUp(() => backend = FakeBackend.seeded(today: testToday));

  testWidgets('low stock across all locations, by location then name', (
    tester,
  ) async {
    await _openStock(tester, backend);

    expect(find.text('Low stock across all locations'), findsOneWidget);
    final rows = tester
        .widget<DataTable>(find.byKey(const Key('low-stock-table')))
        .rows
        .map((r) => (r.key! as ValueKey<String>).value)
        .toList();
    expect(rows, [
      'low-MNJ-RM_cream',
      'low-PTB-FG_chocpastry',
      'low-PTB-RM_eggs',
      'low-PTB-RM_flour',
    ]);
    expect(_text(tester, 'low-qty-MNJ-RM_cream'), '2,500 ml');
    // The closed location isn't part of "All" for current stock.
    expect(find.byKey(const Key('stock-table-KTL')), findsNothing);
  });

  testWidgets('every item per location; negatives in red; thresholds', (
    tester,
  ) async {
    await _openStock(tester, backend);

    expect(find.byKey(const Key('stock-table-PTB')), findsOneWidget);
    expect(find.byKey(const Key('stock-table-MNJ')), findsOneWidget);
    expect(_text(tester, 'qty-PTB-RM_flour'), '4,000 g');
    expect(_text(tester, 'threshold-PTB-RM_flour'), '5,000 g');
    expect(_text(tester, 'threshold-PTB-FG_vegpuff'), '—');
    expect(_text(tester, 'status-PTB-RM_flour'), 'Low');
    expect(find.byKey(const Key('status-PTB-RM_cream')), findsNothing);

    final error = Theme.of(
      tester.element(find.byType(StockScreen)),
    ).colorScheme.error;
    final negative = tester.widget<Text>(
      find.byKey(const Key('qty-PTB-FG_chocpastry')),
    );
    expect(negative.data, '-3 pcs');
    expect(negative.style?.color, error);
    expect(_text(tester, 'status-PTB-FG_chocpastry'), 'Below zero');
    final positive = tester.widget<Text>(
      find.byKey(const Key('qty-PTB-RM_flour')),
    );
    expect(positive.style?.color, isNot(error));
  });

  testWidgets('the type filter narrows the per-location tables', (
    tester,
  ) async {
    await _openStock(tester, backend);

    await tester.tap(find.text('Finished goods'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('qty-PTB-FG_bf1kg')), findsOneWidget);
    expect(find.byKey(const Key('qty-PTB-RM_flour')), findsNothing);
    // The low-stock table is not filtered.
    expect(find.byKey(const Key('low-qty-PTB-RM_flour')), findsOneWidget);

    await tester.tap(find.text('Raw materials'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('qty-PTB-FG_bf1kg')), findsNothing);
    expect(find.byKey(const Key('qty-PTB-RM_flour')), findsOneWidget);
  });

  testWidgets('a single location from the switcher', (tester) async {
    await _openStock(tester, backend);

    await tester.tap(find.byKey(const Key('location-switcher')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manjeri (MNJ)').last);
    await tester.pumpAndSettle();

    expect(find.text('Low stock'), findsOneWidget);
    expect(find.byKey(const Key('stock-table-PTB')), findsNothing);
    expect(find.byKey(const Key('low-qty-MNJ-RM_cream')), findsOneWidget);
  });

  testWidgets('a Store Manager sees only their own location', (tester) async {
    await _openStock(tester, backend, email: FakeBackend.storeManagerEmail);

    expect(find.byKey(const Key('stock-table-PTB')), findsOneWidget);
    expect(find.byKey(const Key('stock-table-MNJ')), findsNothing);
    expect(find.byKey(const Key('low-qty-MNJ-RM_cream')), findsNothing);
  });

  testWidgets('no low items shows a message', (tester) async {
    final quiet = FakeBackend(
      auth: backend.auth,
      locations: backend.locations,
      summaries: backend.summaries,
      catalog: backend.catalog,
      stock: FakeStockRepository({
        'PTB': [_item('flour', 9000, 5000), _item('salt', 10, null)],
      }),
    );
    await _openStock(tester, quiet);
    expect(find.byKey(const Key('low-stock-empty')), findsOneWidget);
    expect(find.text('No stock recorded.'), findsOneWidget); // MNJ
  });

  test('lowStockAcross sorts by location code, then name', () {
    final locs = [
      FakeBackend.location('PTB', 'Pattambi'),
      FakeBackend.location('MNJ', 'Manjeri'),
    ];
    final rows = lowStockAcross(locs, {
      'PTB': [_item('b', -1, null), _item('z', 0, 0), _item('a', 1, 5)],
      'MNJ': [_item('m', 5, 5), _item('n', 6, 5)],
    });
    expect(
      [for (final r in rows) '${r.location.code}:${r.item.name}'],
      // A negative item without a threshold is not "low" (D-015).
      ['MNJ:m', 'PTB:a', 'PTB:z'],
    );
  });
}
