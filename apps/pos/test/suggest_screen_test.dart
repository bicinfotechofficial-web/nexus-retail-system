import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_pos/app/router.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';

import 'helpers.dart';

void main() {
  testWidgets('suggests a local special with name, category and price', (
    tester,
  ) async {
    final b = await pumpPos(tester);
    await openNav(tester, 'Suggest special');
    expect(find.widgetWithText(AppBar, 'Suggest special'), findsOneWidget);
    // The seed's pending Jackfruit Cake is from this store.
    expect(find.byKey(const Key('pending-jack-cake')), findsOneWidget);
    expect(isEnabled(tester, 'save'), isFalse);

    await enterKey(tester, 'suggest-name', 'Tender Coconut Cake 500 g');
    await tapKey(tester, 'category-chip-Cakes');
    await enterKey(tester, 'suggest-price', 'abc');
    expect(find.textContaining('Enter an amount'), findsOneWidget);
    expect(isEnabled(tester, 'save'), isFalse);
    await enterKey(tester, 'suggest-price', '520');
    await tapKey(tester, 'save');

    final created = b.catalog.products.last;
    expect(created.name, 'Tender Coconut Cake 500 g');
    expect(created.category, 'Cakes');
    expect(created.proposedPrice, const Money(52000));
    expect(created.price, isNull);
    expect(created.status, ProductStatus.pending);
    expect(created.scope, Seed.locationId);
    expect(find.byKey(const Key('suggest-sent')), findsOneWidget);
    expect(find.byKey(Key('pending-${created.id}')), findsOneWidget);
    // The form is ready for the next one.
    expect(isEnabled(tester, 'save'), isFalse);

    // Not sellable until approved (D-008).
    await openNav(tester, 'Billing');
    expect(find.text('Tender Coconut Cake 500 g'), findsNothing);
  });

  testWidgets('a new category can be typed', (tester) async {
    final b = await pumpPos(tester);
    await openNav(tester, 'Suggest special');
    await enterKey(tester, 'suggest-name', 'Unniyappam (6)');
    await enterKey(tester, 'suggest-category', 'Kerala Snacks');
    await enterKey(tester, 'suggest-price', '60.50');
    await tapKey(tester, 'save');
    expect(b.catalog.products.last.category, 'Kerala Snacks');
    expect(b.catalog.products.last.proposedPrice, const Money(6050));
  });

  testWidgets('a failed suggestion shows a friendly message', (tester) async {
    final b = await pumpPos(tester);
    b.catalogService.failNext = const DataFailure(FailureReason.notPermitted);
    await openNav(tester, 'Suggest special');
    await enterKey(tester, 'suggest-name', 'Plum Special');
    await tapKey(tester, 'category-chip-Cakes');
    await enterKey(tester, 'suggest-price', '300');
    await tapKey(tester, 'save');
    expect(
      textOf(tester, 'save-error'),
      "You don't have permission to do this.",
    );
    expect(b.catalogService.suggestCalls, hasLength(1));
  });

  testWidgets('hidden without catalog.suggest', (tester) async {
    await pumpPos(
      tester,
      backend: fakeBackend(session: sessionWith([Permission.billCreate])),
    );
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav-Suggest special')), findsNothing);
    expect(
      Routes.redirect(
        AsyncData(sessionWith([Permission.billCreate])),
        '/suggest',
      ),
      '/',
    );
  });
}
