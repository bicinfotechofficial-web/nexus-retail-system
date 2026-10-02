// Per-scenario setup: an emptied, seeded emulator and named-app devices
// signed in and registered through the `nexus_data` interfaces.

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'backend.dart';
import 'emulator.dart';
import 'fixtures.dart';

/// Every scenario may take a while: seeding, two devices, sync passes.
const Timeout scenarioTimeout = Timeout(Duration(minutes: 5));

final class Scenario {
  Scenario._(this.target, this.admin, this.uids);

  /// Empties the emulator and writes the seed. Call at the start of a test
  /// and `addTearDown(s.close)`.
  static Future<Scenario> open() async {
    final target = EmulatorTarget.fromEnvironment();
    final admin = EmulatorAdmin(target);
    await admin.reset();
    final uids = await writeSeed(admin);
    return Scenario._(target, admin, uids);
  }

  final EmulatorTarget target;
  final EmulatorAdmin admin;

  /// uid by actor key (`Fx.smPtb.key` ...).
  final Map<String, String> uids;

  final List<TestDevice> _devices = [];
  static int _apps = 0;

  /// The business date the devices bill on (IST, D-022).
  String get today => BusinessDate.of(DateTime.now());

  /// A new install on its own named app, signed in as [actor] (online) and
  /// registered at the actor's location. Devices opened in turn at one
  /// location get D01, D02, ... (registration takes nextDeviceNo + 1).
  Future<TestDevice> device(Actor actor, {required String label}) async {
    final app = await Firebase.initializeApp(
      name:
          'qa-${label.toLowerCase().replaceAll(' ', '-')}-${_apps++}-'
          '${DateTime.now().microsecondsSinceEpoch}',
      options: FirebaseOptions(
        apiKey: 'demo-api-key',
        appId: '1:000000000000:android:0000000000000000',
        messagingSenderId: '000000000000',
        projectId: target.projectId,
      ),
    );
    final d = await openDevice(app, target: target);
    _devices.add(d);
    await d.auth.signIn(email: actor.email, password: Actor.password);
    await d.devices.register(locationId: actor.locationId!, label: label);
    await d.sync.syncNow();
    return d;
  }

  /// Keeps a restarted device in the list [close] disposes.
  TestDevice track(TestDevice restarted) {
    _devices.add(restarted);
    return restarted;
  }

  /// Sets `users/{uid}.active` directly, as `UserService.setActive` would
  /// from the Admin console (D-018).
  Future<void> setActive(Actor actor, {required bool active}) =>
      admin.update(FirestorePaths.user(uids[actor.key]!), {'active': active});

  Future<void> close() async {
    for (final d in _devices.reversed) {
      try {
        await d.dispose();
      } on Object {
        // Already disposed by a restart.
      }
    }
    admin.close();
  }
}

/// A bill for [cart] paid in full: cash, or cash plus UPI when [split].
NewBill paidBill(
  List<CartLine> cart, {
  DiscountInput? discount,
  bool split = false,
}) {
  final total = BillCalculator.compute(cart, discount: discount).total;
  if (!split || total.paise < 200) {
    return NewBill(
      cart: cart,
      discount: discount,
      payments: [Payment(mode: PaymentMode.cash, amount: total)],
      cashTendered: total,
      customer: _customer,
    );
  }
  final cash = Money.rupees(total.paise ~/ 200);
  return NewBill(
    cart: cart,
    discount: discount,
    payments: [
      Payment(mode: PaymentMode.cash, amount: cash),
      Payment(mode: PaymentMode.upi, amount: total - cash),
    ],
    cashTendered: cash,
    customer: _customer,
  );
}

/// The customer on every scenario bill.
final BillCustomer _customer = BillCustomer(
  name: 'Test Customer',
  phone: '9876543210',
  whatsapp: '9876543210',
);

/// Refunds for returning [qty] of [bill], all in cash.
List<Payment> cashRefund(Bill bill, Map<String, int> qty) {
  final refund = ReturnCalculator.compute(bill, qty).refundTotal;
  return refund.isPositive
      ? [Payment(mode: PaymentMode.cash, amount: refund)]
      : const [];
}

/// The value a stream holds now: its first event, which the `nexus_data`
/// streams emit on listen (the POS's StreamProviders rely on it).
Future<T> current<T>(Stream<T> stream) =>
    stream.first.timeout(const Duration(seconds: 30));

/// Brings each device online and runs a sync pass, in the given order.
Future<void> syncInOrder(List<TestDevice> devices) async {
  for (final d in devices) {
    await d.goOnline();
    await d.sync.syncNow();
  }
}

/// A device's sync errors after its last pass.
Future<List<String>> syncErrorPaths(TestDevice d) async => [
  for (final e in await current(d.sync.errors)) e.path,
];
