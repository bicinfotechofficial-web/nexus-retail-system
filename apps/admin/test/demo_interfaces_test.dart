import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_admin/fakes/fake_backend.dart';
import 'package:nexus_admin/fakes/overrides.dart';

import 'helpers.dart';

/// `FAKE_DATA=true` shows staff, attendance and orders (D-042, D-043).
void main() {
  Future<void> open(WidgetTester tester, String path) async {
    await pumpAdmin(
      tester,
      FakeBackend.seeded(today: testToday),
      size: const Size(1400, 3200),
      overrides: demoInterfaceOverrides(testToday),
    );
    await signIn(tester);
    await goTo(tester, path);
  }

  testWidgets('the Orders page lists every store\'s demo orders', (
    tester,
  ) async {
    await open(tester, '/orders');
    expect(find.text('6 orders'), findsOneWidget);
    expect(find.byKey(const Key('order-PTB-D01-O000002')), findsOneWidget);
    expect(find.byKey(const Key('order-MNJ-D02-O000002')), findsOneWidget);
  });

  testWidgets('the Attendance page shows PTB marked and MNJ not, today', (
    tester,
  ) async {
    await open(tester, '/attendance');
    expect(find.byKey(const Key('att-store-PTB')), findsOneWidget);
    expect(find.byKey(const Key('att-store-MNJ')), findsOneWidget);
    expect(find.byKey(const Key('att-all-marked')), findsNothing);
  });

  testWidgets('the Staff page has the roster, inactive included', (
    tester,
  ) async {
    await open(tester, '/staff');
    expect(find.byKey(const Key('staff-table')), findsOneWidget);
    expect(find.byKey(const Key('staff-count')), findsOneWidget);
  });
}
