import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_pos/app/phone_store.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// POS-16: "Review bill before saving" in Settings, and the "Don't show
/// this review again" box on the review (D-035).
Future<void> chargeOne(WidgetTester tester) async {
  await tapKey(tester, 'product-bf-500');
  await tapKey(tester, 'charge');
  await fillCustomer(tester);
}

Future<void> setReview(WidgetTester tester, {required bool on}) async {
  await openNav(tester, 'Settings');
  final switchTile = tester.widget<SwitchListTile>(
    find.byKey(const Key('review-switch')),
  );
  if (switchTile.value != on) await tapKey(tester, 'review-switch');
  expect(
    tester.widget<SwitchListTile>(find.byKey(const Key('review-switch'))).value,
    on,
  );
}

void main() {
  testWidgets('the review is on by default and Settings shows it', (
    tester,
  ) async {
    await pumpPos(tester);
    await openNav(tester, 'Settings');
    expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
    expect(find.text('Review bill before saving'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('review-switch')))
          .value,
      isTrue,
    );
  });

  testWidgets('the box on the review turns it off: the next bill saves '
      'directly', (tester) async {
    final b = await pumpPos(tester);
    await chargeOne(tester);
    expect(textOf(tester, 'save'), contains('Review'));
    await tapKey(tester, 'save');
    // Ticking the box is not enough on its own: this bill still needs
    // Confirm, and the choice applies from the next bill.
    await tapKey(tester, 'dont-show-again');
    await tapKey(tester, 'confirm');
    expect(b.sales.createCalls, hasLength(1));
    await tapKey(tester, 'new-bill');

    await chargeOne(tester);
    expect(textOf(tester, 'save'), contains('Save'));
    expect(textOf(tester, 'save'), isNot(contains('Review')));
    await tapKey(tester, 'save');
    // Straight to the result screen, with no review in between.
    expect(find.byKey(const Key('confirm')), findsNothing);
    expect(b.sales.createCalls, hasLength(2));
    expect(textOf(tester, 'bill-no'), 'PTB-D01-000002');
  });

  testWidgets('Back with the box ticked changes nothing', (tester) async {
    await pumpPos(tester);
    await chargeOne(tester);
    await tapKey(tester, 'save');
    await tapKey(tester, 'dont-show-again');
    await tapKey(tester, 'review-back');
    expect(textOf(tester, 'save'), contains('Review'));
  });

  testWidgets('the Settings switch turns it off and back on', (tester) async {
    final b = await pumpPos(tester);
    await setReview(tester, on: false);
    await openNav(tester, 'Billing');
    await chargeOne(tester);
    await tapKey(tester, 'save');
    expect(b.sales.createCalls, hasLength(1)); // saved at once
    await tapKey(tester, 'new-bill');

    await setReview(tester, on: true);
    await openNav(tester, 'Billing');
    await chargeOne(tester);
    expect(textOf(tester, 'save'), contains('Review'));
    await tapKey(tester, 'save');
    expect(find.widgetWithText(AppBar, 'Review bill'), findsOneWidget);
    expect(b.sales.createCalls, hasLength(1)); // not yet
    await tapKey(tester, 'confirm');
    expect(b.sales.createCalls, hasLength(2));
  });

  testWidgets('the choice survives a restart, and turning it back on does '
      'too', (tester) async {
    final phone = MemoryPhoneStore();
    var b = await pumpPos(tester, backend: fakeBackend(phoneStore: phone));
    await setReview(tester, on: false);

    // "Restart": a new app on the same phone.
    await tester.pumpWidget(const SizedBox());
    b = await pumpPos(tester, backend: fakeBackend(phoneStore: phone));
    await openNav(tester, 'Settings');
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('review-switch')))
          .value,
      isFalse,
    );
    await openNav(tester, 'Billing');
    await chargeOne(tester);
    expect(textOf(tester, 'save'), contains('Save'));
    expect(b.sales.createCalls, isEmpty);

    // Restart again, turn it back on, and restart once more.
    await tester.pumpWidget(const SizedBox());
    await pumpPos(tester, backend: fakeBackend(phoneStore: phone));
    await setReview(tester, on: true);
    await tester.pumpWidget(const SizedBox());
    await pumpPos(tester, backend: fakeBackend(phoneStore: phone));
    await openNav(tester, 'Settings');
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('review-switch')))
          .value,
      isTrue,
    );
  });

  group('on shared_preferences', () {
    testWidgets('is stored per signed-in user under reviewBeforeSave.<uid>', (
      tester,
    ) async {
      // Another user on this phone turned it off; this one is unaffected.
      SharedPreferences.setMockInitialValues({
        'reviewBeforeSave.someone-else': false,
      });
      await pumpPos(
        tester,
        backend: fakeBackend(phoneStore: const SharedPrefsPhoneStore()),
      );
      await openNav(tester, 'Settings');
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('review-switch')))
            .value,
        isTrue,
      );
      await tapKey(tester, 'review-switch');
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('reviewBeforeSave.${Seed.userId}'), isFalse);
      expect(prefs.getBool('reviewBeforeSave.someone-else'), isFalse);

      // A restart reads it back.
      await tester.pumpWidget(const SizedBox());
      await pumpPos(
        tester,
        backend: fakeBackend(phoneStore: const SharedPrefsPhoneStore()),
      );
      await openNav(tester, 'Settings');
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('review-switch')))
            .value,
        isFalse,
      );
    });
  });
}
