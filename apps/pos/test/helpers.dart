import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_pos/app/app.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';

/// 10:30 IST on 2026-09-26, as a UTC instant.
final DateTime testNow = DateTime.utc(2026, 9, 26, 5);

FakeBackend fakeBackend({
  SessionContext? session,
  SyncStatus syncStatus = const Online(),
}) => FakeBackend(session: session, syncStatus: syncStatus, now: () => testNow);

/// A Store Manager session whose role has only [permissions].
SessionContext sessionWith(
  List<String> permissions, {
  Location location = Seed.location,
}) => SessionContext(
  user: Seed.storeManager,
  role: Role(
    id: 'CUSTOM',
    name: 'Custom',
    permissions: permissions,
    allLocations: false,
  ),
  location: location,
);

/// Pumps the whole app on a portrait phone screen (360 × 780 dp).
Future<FakeBackend> pumpPos(WidgetTester tester, {FakeBackend? backend}) async {
  final b = backend ?? fakeBackend();
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(overrides: b.overrides, child: const PosApp()),
  );
  await tester.pumpAndSettle();
  return b;
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> enterKey(WidgetTester tester, String key, String text) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.enterText(f, text);
  await tester.pumpAndSettle();
}

/// The text of the [Text] under [key], or of the Text itself.
String textOf(WidgetTester tester, String key) {
  final f = find.byKey(Key(key));
  final own = tester.widget(f);
  if (own is Text) return own.data ?? '';
  return tester
      .widgetList<Text>(find.descendant(of: f, matching: find.byType(Text)))
      .map((t) => t.data ?? '')
      .join(' ');
}

bool isEnabled(WidgetTester tester, String key) {
  final w = tester.widget<ButtonStyleButton>(find.byKey(Key(key)));
  return w.onPressed != null;
}
