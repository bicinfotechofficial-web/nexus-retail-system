import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_data/src/firestore/plan_adapter.dart';

import 'plan_fixtures.dart';

final class _Call {
  _Call(this.method, this.path, this.data, {this.merge});
  final String method;
  final String path;
  final Map<Object, Object?> data;
  final bool? merge;
}

final class _RecordingSink implements PlanSink {
  final List<_Call> calls = [];

  @override
  void set(String path, Map<String, Object?> data, {required bool merge}) =>
      calls.add(_Call('set', path, data, merge: merge));

  @override
  void update(String path, Map<FieldPath, Object?> data) =>
      calls.add(_Call('update', path, data));
}

void main() {
  test('maps every sentinel and DateTime, recursively', () {
    final at = DateTime.utc(2026, 9, 26, 4, 30);
    expect(PlanAdapter.encode(const Increment(-3)), FieldValue.increment(-3));
    expect(PlanAdapter.encode(serverTimestamp), FieldValue.serverTimestamp());
    expect(PlanAdapter.encode(at), Timestamp.fromDate(at));
    expect(
      PlanAdapter.encode({
        'a': [
          {'at': at, 'n': const Increment(2)},
        ],
        'b': {'c': serverTimestamp},
        's': 'x',
        'i': 5,
        'nil': null,
      }),
      {
        'a': [
          {'at': Timestamp.fromDate(at), 'n': FieldValue.increment(2)},
        ],
        'b': {'c': FieldValue.serverTimestamp()},
        's': 'x',
        'i': 5,
        'nil': null,
      },
    );
  });

  test('create is set, setMerge is set(merge), update uses FieldPaths', () {
    final plan = SalesPlans.createReturn(
      ctx: Fx.sm(),
      seq: 3,
      bill: Fx.bill(),
      qtyByProduct: {'puff-veg': 1},
      refunds: const [Payment(mode: PaymentMode.cash, amount: Money(2300))],
      reason: 'Damaged',
    ).plan;
    final sink = _RecordingSink();
    PlanAdapter.apply(plan, sink);

    expect(sink.calls.map((c) => c.path), plan.paths);
    final ret = sink.calls[0];
    expect((ret.method, ret.merge), ('set', false));
    expect(ret.data['serverCreatedAt'], FieldValue.serverTimestamp());
    expect(ret.data['clientCreatedAt'], Timestamp.fromDate(Fx.now));

    final bill = sink.calls[1];
    expect(bill.method, 'update');
    expect(bill.data, {
      FieldPath(const ['returnedQty', 'puff-veg']): FieldValue.increment(1),
      FieldPath(const ['lastReturnId']): 'D01-R000003',
    });

    final stock = sink.calls[2];
    expect((stock.method, stock.merge), ('set', true));
    expect(stock.data['qty'], FieldValue.increment(1));
    expect(stock.data['updatedAt'], FieldValue.serverTimestamp());

    final daily = sink.calls[4];
    expect((daily.method, daily.merge), ('set', true));
    expect(daily.data['byProduct'], {
      'puff-veg': {
        'qty': FieldValue.increment(-1),
        'amount': FieldValue.increment(-2295),
      },
    });

    final device = sink.calls.last;
    expect(device.method, 'update');
    expect(device.data, {
      FieldPath(const ['lastReturnSeq']): 3,
    });
  });

  test('decode turns Timestamps back into UTC DateTimes for fromMap', () {
    final at = DateTime.utc(2026, 9, 26, 4, 30);
    final decoded = PlanAdapter.decodeDoc({
      'clientCreatedAt': Timestamp.fromDate(at),
      'cancel': {'at': Timestamp.fromDate(at)},
      'lines': [
        {'n': 1},
      ],
      'x': 'y',
    });
    expect(decoded, {
      'clientCreatedAt': at,
      'cancel': {'at': at},
      'lines': [
        {'n': 1},
      ],
      'x': 'y',
    });
    // A bill read back from Firestore goes through Bill.fromMap.
    final bill = Fx.bill();
    final stored = PlanAdapter.encodeMap({
      ...bill.toMap(),
      'serverCreatedAt': at,
    });
    final back = Bill.fromMap(bill.id, PlanAdapter.decodeDoc(stored));
    expect(back.clientCreatedAt, bill.clientCreatedAt);
    expect(back.serverCreatedAt, at);
    expect(back.total, bill.total);
  });
}
