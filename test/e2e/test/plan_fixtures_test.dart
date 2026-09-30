/// QA-5 through the backend's WritePlan fixtures (PLAN P-03, S2-1..S2-5,
/// S5-5): every JSON plan in `firebase/test/fixtures/plans/` is applied to
/// an in-memory store with Firestore's write semantics
/// (`support/plan_store.dart`), and then
///
/// * the summaries equal the sum of the docs: for each fixture on its own,
///   the change in every daily and monthly summary equals the change in
///   what the bill, return and expense docs add up to; and for the chains
///   of fixtures that tell one story (a bill then its cancel; a bill then
///   two returns; an expense then an edit), the stored summaries equal the
///   docs outright;
/// * each op matches 03-SYNC §2 and 02-DATA-MODEL: stock is only ever
///   `setMerge` with an increment tied to a new movement of the same delta,
///   summaries are only increments naming a new doc of the batch, device
///   counters move with the IDs they belong to, audit IDs have the D-032
///   shape of their action, returns chain `prevReturnId`, and a location
///   edit never writes `nextDeviceNo`;
/// * every stock doc's `qty` equals the sum of its movements.
///
/// The oracle is written from 02-DATA-MODEL, like P-01's, and reads the docs
/// with the `nexus_core` models the apps use.
library;

import 'package:nexus_core/nexus_core.dart';
import 'package:test/test.dart';

import 'support/plan_store.dart';

void main() {
  final fixtures = loadPlanFixtures();

  test('the fixtures are there and cover the P-01 operation types', () {
    expect(
      fixtures.keys,
      containsAll([
        'bill_create',
        'bill_create_max',
        'bill_cancel',
        'return_first',
        'return_second',
        'expense_create',
        'expense_edit',
        'stock_in',
        'stock_out_raw',
        'wastage_raw',
        'wastage_fg',
        'produce',
        'adjust',
        'threshold_set',
        'location_create',
        'location_edit',
      ]),
    );
  });

  group('each fixture on its own', () {
    for (final f in fixtures.values) {
      group(f.name, () {
        late DocStore before;
        late DocStore after;
        setUp(() {
          before = seededStore();
          f.arrange.forEach(before.put);
          after = before.copy()..applyBatch(f.ops);
        });

        test('writes each doc once', () {
          final paths = [for (final o in f.ops) o.path];
          expect(paths.toSet(), hasLength(paths.length));
        });

        test('summary change equals the change in the docs', () {
          expectSummaryDeltas(before, after, f.name);
        });

        test('stock is setMerge + increment, tied to a new movement', () {
          checkStockOps(f);
        });

        test('summaries are increments naming a new doc of the batch', () {
          checkSummaryOps(f, before);
        });

        test('audit IDs have the D-032 shape of their action', () {
          checkAuditOps(f, after);
        });

        test('device counters move with the IDs they belong to', () {
          checkDeviceOps(f);
        });

        test('writers are the fixture user', () => checkWriters(f));

        test('stock qty equals the sum of the movements', () {
          expectStockEqualsMovements(after, f.name);
        });

        test(
          'every stock doc it leaves reads as a StockItem',
          () => expectStockReadable(after, f.name),
        );
      });
    }
  });

  group('returns', () {
    for (final name in ['return_first', 'return_second']) {
      test(
        '$name: prevReturnId, returnedQty and the refund (D-024, D-029)',
        () {
          final f = fixtures[name]!;
          final create = f.ops.firstWhere(
            (o) => o.collection == 'returns' && o.kind == OpKind.create,
          );
          final billPath =
              'locations/${create.locationId}/bills/'
              '${create.data['billId']}';
          final bill = Bill.fromMap(
            billPath.split('/').last,
            DocStore()._putPlain(billPath, f.arrange[billPath]!),
          );
          expect(create.data['prevReturnId'], bill.lastReturnId);

          final lines = [
            for (final l in create.data['lines']! as List<Object?>)
              l! as Map<String, Object?>,
          ];
          final qty = {
            for (final l in lines) l['productId']! as String: l['qty']! as int,
          };
          final totals = ReturnCalculator.compute(bill, qty);
          expect(create.data['refundTotal'], totals.refundTotal.paise);
          expect(
            [for (final l in lines) l['amount']],
            [for (final l in totals.lines) l.amount.paise],
          );

          final update = f.opAt(billPath)!;
          expect(update.kind, OpKind.update);
          expect(update.data, {
            for (final e in qty.entries) 'returnedQty.${e.key}': isA<Inc>(),
            'lastReturnId': create.id,
          });
          for (final e in qty.entries) {
            expect(e.value, greaterThan(0), reason: 'never writes a 0');
            expect((update.data['returnedQty.${e.key}']! as Inc).by, e.value);
          }
        },
      );
    }
  });

  test('location create writes nextDeviceNo 0, an edit never writes it', () {
    final create = fixtures['location_create']!.ops.firstWhere(
      (o) => o.collection == 'locations',
    );
    expect(create.kind, OpKind.create);
    expect(create.data['nextDeviceNo'], 0);
    final edit = fixtures['location_edit']!.ops.firstWhere(
      (o) => o.collection == 'locations',
    );
    expect(edit.kind, OpKind.update);
    expect(edit.data.keys, isNot(contains('nextDeviceNo')));
    expect(edit.data.keys, isNot(contains('code')));
  });

  group('chains: summaries equal the docs outright', () {
    const chains = {
      'bill then same-day cancel': ['bill_create', 'bill_cancel'],
      'bill then two returns': ['bill_create', 'return_first', 'return_second'],
      'expense then an edit to another month and location': [
        'expense_create',
        'expense_edit',
      ],
    };
    for (final MapEntry(key: name, value: chain) in chains.entries) {
      test(name, () {
        final store = seededStore();
        fixtures[chain.first]!.arrange.forEach(store.put);
        for (var i = 0; i < chain.length; i++) {
          final f = fixtures[chain[i]]!;
          if (i > 0) {
            // The next fixture must have been built on what the previous
            // one left: every doc it arranges and then writes is the same,
            // server times aside. Device docs are left out: each fixture
            // sets its own counters to fit the IDs it uses.
            for (final op in f.ops) {
              final arranged = f.arrange[op.path];
              if (arranged == null || op.collection == 'devices') continue;
              expect(
                withoutTimes(store.docs[op.path]),
                withoutTimes(DocStore()._putPlain(op.path, arranged)),
                reason: '${f.name} arranges ${op.path} as the chain left it',
              );
            }
          }
          store
            ..serverTime = store.serverTime.add(const Duration(minutes: 5))
            ..applyBatch(f.ops);
        }
        expectSummariesEqualDocs(store, name);
        expectStockEqualsMovements(store, name);
      });
    }
  });
}

// ---------------------------------------------------------------------------
// The oracle: summary figures from the bill, return and expense docs.
// ---------------------------------------------------------------------------

/// The summary [loc] should hold for the dates [inPeriod] accepts, from the
/// docs alone, as `SummaryDeltas.increments` flattens it (zeros left out).
/// Definitions from 02-DATA-MODEL summaries (see P-01's oracle):
/// as-billed figures from every bill of the period; `cancelled` from bills
/// whose cancel is in the period; `returns` by the return's own date
/// (D-012); `byMode` and `byProduct` net of cancellations and returns;
/// `expenses` in the monthly docs only.
Map<String, int> oracle(
  DocStore s,
  String loc,
  bool Function(String date) inPeriod, {
  required bool monthly,
}) {
  var billCount = 0, cancelCount = 0, returnCount = 0;
  var gross = 0, discounts = 0, roundOff = 0, netSales = 0;
  var returns = 0, cancelled = 0, expenses = 0;
  final byMode = <PaymentMode, int>{};
  final qty = <String, int>{};
  final amount = <String, int>{};
  final byCategory = <ExpenseCategory, int>{};

  for (final e in s.collection('locations/$loc/bills').entries) {
    final b = Bill.fromMap(e.key, e.value);
    if (inPeriod(b.businessDate)) {
      billCount++;
      gross += b.subtotal.paise;
      discounts += b.discountAmount.paise;
      roundOff += b.roundOff.paise;
      netSales += b.total.paise;
      if (b.status == BillStatus.completed) {
        for (final p in b.payments) {
          byMode[p.mode] = (byMode[p.mode] ?? 0) + p.amount.paise;
        }
        final nets = BillCalculator.lineNetAmounts(b);
        expect(
          nets.fold<int>(0, (a, n) => a + n.paise),
          (b.total - b.roundOff).paise,
          reason: '${b.id}: line nets add up to the net (D-024 c)',
        );
        for (var i = 0; i < b.lines.length; i++) {
          final id = b.lines[i].productId;
          qty[id] = (qty[id] ?? 0) + b.lines[i].qty;
          amount[id] = (amount[id] ?? 0) + nets[i].paise;
        }
      }
    }
    final cancel = b.cancel;
    if (b.status == BillStatus.cancelled && cancel != null) {
      if (inPeriod(cancel.businessDate)) {
        cancelCount++;
        cancelled += b.total.paise;
      }
    }
  }
  for (final e in s.collection('locations/$loc/returns').entries) {
    final r = SaleReturn.fromMap(e.key, e.value);
    if (!inPeriod(r.businessDate)) continue;
    returnCount++;
    returns += r.refundTotal.paise;
    for (final p in r.refunds) {
      byMode[p.mode] = (byMode[p.mode] ?? 0) - p.amount.paise;
    }
    for (final l in r.lines) {
      qty[l.productId] = (qty[l.productId] ?? 0) - l.qty;
      amount[l.productId] = (amount[l.productId] ?? 0) - l.amount.paise;
    }
  }
  if (monthly) {
    for (final e in s.collection('expenses').entries) {
      final x = Expense.fromMap(e.key, e.value);
      if (x.locationId != loc || !inPeriod(x.date)) continue;
      expenses += x.amount.paise;
      byCategory[x.category] = (byCategory[x.category] ?? 0) + x.amount.paise;
    }
  }
  return SummaryDeltas.increments(
    Summary(
      billCount: billCount,
      cancelCount: cancelCount,
      returnCount: returnCount,
      grossSales: Money(gross),
      discounts: Money(discounts),
      roundOff: Money(roundOff),
      netSales: Money(netSales),
      returns: Money(returns),
      cancelled: Money(cancelled),
      byMode: {for (final e in byMode.entries) e.key: Money(e.value)},
      byProduct: {
        for (final id in {...qty.keys, ...amount.keys})
          id: ProductTally(qty: qty[id] ?? 0, amount: Money(amount[id] ?? 0)),
      },
      expenses: Money(expenses),
      byExpenseCategory: {
        for (final e in byCategory.entries) e.key: Money(e.value),
      },
    ),
  );
}

/// A stored summary doc, flattened like `SummaryDeltas.increments`
/// (`byMode.CASH`, `byProduct.P1.qty`), zeros and `lastWriteRef` left out.
/// Also checks that the app's model reads the doc the same way.
Map<String, int> storedFlat(DocStore s, String path) {
  final doc = s.docs[path];
  if (doc == null) return const {};
  final out = <String, int>{};
  void walk(String prefix, Map<String, Object?> m) {
    for (final e in m.entries) {
      final k = prefix.isEmpty ? e.key : '$prefix.${e.key}';
      final v = e.value;
      if (k == 'lastWriteRef') continue;
      if (v is Map<String, Object?>) {
        walk(k, v);
      } else if (v is int) {
        if (v != 0) out[k] = v;
      } else {
        fail('$path: $k is ${v.runtimeType}, not a number');
      }
    }
  }

  walk('', doc);
  expect(
    SummaryDeltas.increments(Summary.fromMap(path.split('/').last, doc)),
    out,
    reason: '$path reads back through Summary.fromMap',
  );
  return out;
}

Map<String, int> minus(Map<String, int> a, Map<String, int> b) {
  final out = <String, int>{...a};
  for (final e in b.entries) {
    final v = (out[e.key] ?? 0) - e.value;
    if (v == 0) {
      out.remove(e.key);
    } else {
      out[e.key] = v;
    }
  }
  return out;
}

/// Every (location, day) and (location, month) either store knows about:
/// from summary doc IDs and from the dates on bills, cancels, returns and
/// expenses.
({Set<(String, String)> days, Set<(String, String)> months}) periodsOf(
  Iterable<DocStore> stores,
) {
  final days = <(String, String)>{};
  final months = <(String, String)>{};
  void day(String loc, String d) {
    days.add((loc, d));
    months.add((loc, BusinessDate.monthOf(d)));
  }

  for (final s in stores) {
    for (final p in s.docs.keys) {
      final seg = p.split('/');
      if (seg.length != 4 || seg.first != 'locations') continue;
      final (loc, col, id) = (seg[1], seg[2], seg[3]);
      final d = s.docs[p]!;
      switch (col) {
        case 'dailySummary':
          day(loc, id);
        case 'monthlySummary':
          months.add((loc, id));
        case 'bills':
          day(loc, d['businessDate']! as String);
          final c = d['cancel'];
          if (c is Map<String, Object?>) day(loc, c['businessDate']! as String);
        case 'returns':
          day(loc, d['businessDate']! as String);
      }
    }
    for (final x in s.collection('expenses').values) {
      months.add((
        x['locationId']! as String,
        BusinessDate.monthOf(x['date']! as String),
      ));
    }
  }
  return (days: days, months: months);
}

void expectSummaryDeltas(DocStore before, DocStore after, String why) {
  final p = periodsOf([before, after]);
  for (final (loc, d) in p.days) {
    final path = 'locations/$loc/dailySummary/$d';
    bool on(String x) => x == d;
    expect(
      minus(storedFlat(after, path), storedFlat(before, path)),
      minus(
        oracle(after, loc, on, monthly: false),
        oracle(before, loc, on, monthly: false),
      ),
      reason: '$why: $path',
    );
  }
  for (final (loc, m) in p.months) {
    final path = 'locations/$loc/monthlySummary/$m';
    bool on(String x) => BusinessDate.monthOf(x) == m;
    expect(
      minus(storedFlat(after, path), storedFlat(before, path)),
      minus(
        oracle(after, loc, on, monthly: true),
        oracle(before, loc, on, monthly: true),
      ),
      reason: '$why: $path',
    );
  }
}

void expectSummariesEqualDocs(DocStore s, String why) {
  final p = periodsOf([s]);
  expect(p.days.length + p.months.length, greaterThan(0));
  for (final (loc, d) in p.days) {
    final path = 'locations/$loc/dailySummary/$d';
    expect(
      storedFlat(s, path),
      oracle(s, loc, (x) => x == d, monthly: false),
      reason: '$why: $path',
    );
  }
  for (final (loc, m) in p.months) {
    final path = 'locations/$loc/monthlySummary/$m';
    expect(
      storedFlat(s, path),
      oracle(s, loc, (x) => BusinessDate.monthOf(x) == m, monthly: true),
      reason: '$why: $path',
    );
  }
}

// ---------------------------------------------------------------------------
// Stock: qty only by increment, and equal to the movements (D-005).
// ---------------------------------------------------------------------------

void expectStockEqualsMovements(DocStore s, String why) {
  for (final loc in s.locationIds) {
    final sums = <String, int>{};
    for (final m in s.collection('locations/$loc/movements').values) {
      for (final l in m['lines']! as List<Object?>) {
        final line = l! as Map<String, Object?>;
        final k = line['itemKey']! as String;
        sums[k] = (sums[k] ?? 0) + (line['delta']! as int);
      }
    }
    final stock = s.collection('locations/$loc/stock');
    for (final k in sums.keys) {
      expect(stock, contains(k), reason: '$why: $loc $k has movements');
    }
    for (final e in stock.entries) {
      expect(
        e.value['qty'] ?? 0,
        sums[e.key] ?? 0,
        reason: '$why: $loc/stock/${e.key} = Σ movement deltas',
      );
    }
  }
}

void expectStockReadable(DocStore s, String why) {
  for (final loc in s.locationIds) {
    for (final e in s.collection('locations/$loc/stock').entries) {
      expect(
        () => StockItem.fromMap(e.key, e.value),
        returnsNormally,
        reason: '$why: $loc/stock/${e.key}',
      );
    }
  }
}

void checkStockOps(PlanFixture f) {
  final movements = {
    for (final o in f.ops)
      if (o.collection == 'movements') o.path: o,
  };
  final stockOps = [
    for (final o in f.ops)
      if (o.collection == 'stock') o,
  ];
  for (final o in stockOps) {
    final why = '${f.name}: ${o.path}';
    expect(o.kind, OpKind.setMerge, reason: '$why is always set(merge)');
    final d = o.data;
    for (final k in ['kind', 'refId', 'name', 'unit']) {
      expect(d[k], isA<String>(), reason: '$why writes $k (02 stock)');
    }
    final prefix = d['kind'] == 'RAW' ? 'RM_' : 'FG_';
    expect(o.id, '$prefix${d['refId']}', reason: why);
    expect(d['updatedAt'], isA<ServerTs>(), reason: why);
    if (!d.containsKey('qty')) {
      expect(d.containsKey('lastMovementId'), isFalse, reason: why);
      continue;
    }
    expect(d['qty'], isA<Inc>(), reason: '$why: qty only by increment');
    final mPath = 'locations/${o.locationId}/movements/${d['lastMovementId']}';
    final m = movements[mPath];
    expect(m, isNotNull, reason: '$why: lastMovementId is new in the batch');
    expect(m!.kind, OpKind.create, reason: why);
    final line = (m.data['lines']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .where((l) => l['itemKey'] == o.id);
    expect(line, hasLength(1), reason: '$why: one movement line per item');
    expect((d['qty']! as Inc).by, line.single['delta'], reason: why);
  }
  for (final m in movements.values) {
    for (final l
        in (m.data['lines']! as List<Object?>).cast<Map<String, Object?>>()) {
      expect(
        stockOps.map((o) => o.id),
        contains(l['itemKey']),
        reason: '${f.name}: ${m.path} line ${l['itemKey']} has a stock write',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Summaries: increments only, naming a doc created in the same batch.
// ---------------------------------------------------------------------------

void checkSummaryOps(PlanFixture f, DocStore before) {
  for (final o in f.ops) {
    final daily = o.collection == 'dailySummary';
    if (!daily && o.collection != 'monthlySummary') continue;
    final why = '${f.name}: ${o.path}';
    expect(o.kind, OpKind.setMerge, reason: why);
    void allIncrements(String prefix, Map<String, Object?> m) {
      for (final e in m.entries) {
        final k = '$prefix${e.key}';
        if (k == 'lastWriteRef') continue;
        final v = e.value;
        if (v is Map<String, Object?>) {
          allIncrements('$k.', v);
        } else {
          expect(v, isA<Inc>(), reason: '$why: $k only by increment');
        }
      }
    }

    allIncrements('', o.data);
    final ref = o.data['lastWriteRef'];
    expect(ref, isA<String>(), reason: why);
    final target = f.opAt(ref! as String);
    expect(target?.kind, OpKind.create, reason: '$why: $ref is new');
    expect(before.docs.containsKey(ref), isFalse, reason: why);
    final loc = o.locationId!;
    final t = target!;
    final String date;
    switch (t.collection) {
      case 'bills':
      case 'returns':
        expect(t.locationId, loc, reason: why);
        date = t.data['businessDate']! as String;
      case 'movements':
        expect(t.locationId, loc, reason: why);
        expect(
          t.data['type'],
          'CANCEL',
          reason: '$why: only a CANCEL (QA-039)',
        );
        expect(t.id, '${t.data['refId']}-X', reason: why);
        final bill = before.docs['locations/$loc/bills/${t.data['refId']}']!;
        date = bill['businessDate']! as String;
      case 'auditLog':
        expect(t.data['action'], startsWith('EXPENSE_'), reason: why);
        // An expense edit that moves it names the one audit doc from both
        // locations' summaries (D-032, #9): the month before or after.
        final expenseMonths = {
          for (final x in [
            ...before.collection('expenses').values,
            for (final e in f.ops)
              if (e.collection == 'expenses') e.data,
          ])
            if (x['locationId'] == loc)
              BusinessDate.monthOf(x['date']! as String),
        };
        expect(daily, isFalse, reason: '$why: expenses are monthly only');
        expect(expenseMonths, contains(o.id), reason: why);
        continue;
      default:
        fail('$why: lastWriteRef ${t.path}');
    }
    expect(
      o.id,
      daily ? date : BusinessDate.monthOf(date),
      reason: '$why: the doc of the event\'s date',
    );
  }
}

// ---------------------------------------------------------------------------
// Audit IDs (D-028, D-032, 02 auditLog) and the entities they belong to.
// ---------------------------------------------------------------------------

/// The ID pattern of each action, from the 02-DATA-MODEL table. A location
/// event's ID is tied to its action, so no other action can take it
/// (QA-044).
RegExp auditIdPattern(String action, String? loc) {
  final l = loc == null ? '' : RegExp.escape(loc);
  const key = '[A-Za-z0-9_-]+';
  const millis = r'[0-9]+';
  return RegExp(switch (action) {
    'BILL_CANCEL' => '^$l-D[0-9]{2}-[0-9]{6}-X\$',
    'RETURN' => '^$l-D[0-9]{2}-R[0-9]{6}\$',
    'WASTAGE' || 'STOCK_ADJUST' => '^$l-D[0-9]{2}-M[0-9]{6}\$',
    'OFFLINE_OVERRIDE' => '^$l-D[0-9]{2}-OVR-$millis\$',
    'EXPENSE_CREATE' || 'EXPENSE_UPDATE' => '^$l-EXP-$key-$millis\$',
    'LOCATION_UPDATE' => '^$l-LOC-$millis\$',
    'USER_CREATE' ||
    'USER_DISABLE' ||
    'USER_ENABLE' => loc == null ? '^USR-.+-$millis\$' : '^$l-USR-.+-$millis\$',
    'PRICE_CHANGE' => '^PRICE-$key-$millis\$',
    'PRODUCT_APPROVE' => '^APPROVE-$key-$millis\$',
    _ => throw ArgumentError.value(action, 'action'),
  });
}

const Set<String> globalActions = {'PRICE_CHANGE', 'PRODUCT_APPROVE'};
const Set<String> userActions = {'USER_CREATE', 'USER_DISABLE', 'USER_ENABLE'};

void checkAuditOps(PlanFixture f, DocStore after) {
  final audits = [
    for (final o in f.ops)
      if (o.collection == 'auditLog') o,
  ];
  for (final a in audits) {
    final why = '${f.name}: ${a.path}';
    expect(a.kind, OpKind.create, reason: '$why is create-only');
    final action = a.data['action']! as String;
    final loc = a.data['locationId'] as String?;
    if (globalActions.contains(action)) {
      expect(loc, isNull, reason: why);
    } else if (!userActions.contains(action)) {
      expect(loc, isNotNull, reason: '$why: a location event (QA-037)');
    }
    expect(a.id, matches(auditIdPattern(action, loc)), reason: why);
    expect(a.data['at'], isA<ServerTs>(), reason: why);
    expect(a.data['clientAt'], isA<DateTime>(), reason: why);
    expect(
      after.docs.containsKey(a.data['entityPath']! as String) ||
          (a.data['entityPath']! as String).startsWith('users/'),
      isTrue,
      reason: '$why: entityPath ${a.data['entityPath']} exists after',
    );
  }

  // Entities that must carry their audit doc `{loc}-{same id}` (04 #10).
  for (final o in f.ops) {
    if (o.kind != OpKind.create) continue;
    final String? action = switch (o.collection) {
      'returns' => 'RETURN',
      'movements' => switch (o.data['type']) {
        'CANCEL' => 'BILL_CANCEL',
        'WASTAGE_RAW' || 'WASTAGE_FG' => 'WASTAGE',
        'ADJUST' => 'STOCK_ADJUST',
        _ => null,
      },
      _ => null,
    };
    if (action == null) continue;
    final auditPath = 'auditLog/${o.locationId}-${o.id}';
    final a = f.opAt(auditPath);
    expect(a, isNotNull, reason: '${f.name}: ${o.path} needs $auditPath');
    expect(a!.data['action'], action, reason: auditPath);
    expect(a.data['locationId'], o.locationId, reason: auditPath);
    final entity = action == 'BILL_CANCEL'
        ? 'locations/${o.locationId}/bills/${o.data['refId']}'
        : o.path;
    expect(a.data['entityPath'], entity, reason: auditPath);
  }
}

// ---------------------------------------------------------------------------
// Device counters (03-SYNC §3, 02 devices) and writers.
// ---------------------------------------------------------------------------

void checkDeviceOps(PlanFixture f) {
  final expected = <String, Map<String, int>>{};
  void want(String? loc, String id, String field, int seq) =>
      (expected['locations/$loc/devices/${id.split('-').first}'] ??=
              {})[field] =
          seq;

  for (final o in f.ops) {
    if (o.kind != OpKind.create) continue;
    final id = o.id;
    switch (o.collection) {
      case 'bills':
        want(o.locationId, id, 'lastBillSeq', int.parse(id.split('-')[1]));
      case 'returns':
        want(o.locationId, id, 'lastReturnSeq', int.parse(id.split('-R')[1]));
      case 'movements' when id.contains('-M'):
        want(o.locationId, id, 'lastMovementSeq', int.parse(id.split('-M')[1]));
    }
  }
  final actual = <String, Map<String, Object?>>{
    for (final o in f.ops)
      if (o.collection == 'devices' && o.kind != OpKind.create) o.path: o.data,
  };
  if (f.name == 'device_retire') {
    expect(actual.values.single, {'retired': true});
    return;
  }
  expect(actual, expected, reason: '${f.name}: device counter writes');
  for (final o in f.ops) {
    if (o.collection == 'devices' && o.kind != OpKind.create) {
      expect(o.kind, OpKind.update, reason: '${f.name}: ${o.path}');
    }
  }
}

void checkWriters(PlanFixture f) {
  for (final o in f.ops) {
    if (o.kind != OpKind.create) continue;
    final d = o.data;
    for (final k in ['createdBy', 'by', 'registeredBy']) {
      if (d.containsKey(k) && o.collection != 'products') {
        expect(d[k], f.uid, reason: '${f.name}: ${o.path} $k');
      }
    }
    final served = d['servedBy'];
    if (served is Map<String, Object?>) {
      expect(served['uid'], f.uid, reason: '${f.name}: servedBy');
    }
  }
  for (final o in f.ops) {
    final cancel = o.data['cancel'];
    if (cancel is Map<String, Object?>) {
      expect(cancel['by'], f.uid, reason: '${f.name}: cancel.by');
    }
  }
}

// ---------------------------------------------------------------------------

/// [v] with every DateTime replaced by a marker, for comparing docs whose
/// server times differ.
Object? withoutTimes(Object? v) => switch (v) {
  DateTime() => '<time>',
  Map<String, Object?>() => {
    for (final e in v.entries) e.key: withoutTimes(e.value),
  },
  List<Object?>() => [for (final x in v) withoutTimes(x)],
  _ => v,
};

extension on DocStore {
  /// Puts [data] at [path] and returns the stored (resolved) doc.
  Map<String, Object?> _putPlain(String path, Map<String, Object?> data) {
    put(path, data);
    return docs[path]!;
  }
}

/// The docs the rules suite seeds before every fixture
/// (`firebase/test/support/fixtures.js`), as far as the plans update them.
DocStore seededStore() => DocStore()
  ..put('locations/PTB', {'code': 'PTB', 'nextDeviceNo': 0, 'active': true})
  ..put('locations/MNJ', {'code': 'MNJ', 'nextDeviceNo': 0, 'active': true})
  ..put('users/sm-ptb', {'locationId': 'PTB', 'active': true})
  ..put('users/admin', {'locationId': null, 'active': true});
