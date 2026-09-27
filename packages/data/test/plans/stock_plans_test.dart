import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'plan_fixtures.dart';

Map<String, Object?> _stock(StockRef r, int delta, String mid) => {
  'kind': r.kind.wire,
  'refId': r.refId,
  'name': r.name,
  'unit': r.unit.wire,
  'qty': Increment(delta),
  'lastMovementId': mid,
  'updatedAt': serverTimestamp,
};

Map<String, Object?> _movement(
  String type,
  List<Map<String, Object?>> lines, {
  String? reason,
  String? note,
}) => {
  'type': type,
  'lines': lines,
  'reason': reason,
  'note': note,
  'refId': null,
  'businessDate': Fx.today,
  'clientCreatedAt': Fx.now,
  'createdBy': Fx.smUid,
  'deviceId': 'D01',
  'serverCreatedAt': serverTimestamp,
};

Matcher _violation() => throwsA(
  isA<DataFailure>().having(
    (f) => f.reason,
    'reason',
    FailureReason.ruleViolation,
  ),
);

const _m = 'locations/PTB/movements/D01-M000042';
const _device = 'locations/PTB/devices/D01';

void main() {
  test('stockIn: movement with the note, increments, device counter', () {
    final p = StockPlans.stockIn(
      ctx: Fx.sm(),
      seq: 42,
      lines: const [StockQty(Fx.flour, 5000), StockQty(Fx.cream, 1000)],
      note: ' Supplier A ',
    );
    expect(p.value.id, 'D01-M000042');
    expect(p.plan.paths, [
      _m,
      'locations/PTB/stock/RM_flour',
      'locations/PTB/stock/RM_cream',
      _device,
    ]);
    expect(
      p.plan.opAt(_m)!.data,
      _movement('STOCK_IN', [
        {'itemKey': 'RM_flour', 'delta': 5000},
        {'itemKey': 'RM_cream', 'delta': 1000},
      ], note: 'Supplier A'),
    );
    expect(
      p.plan.opAt('locations/PTB/stock/RM_flour')!.data,
      _stock(Fx.flour, 5000, 'D01-M000042'),
    );
    expect(
      p.plan.opAt('locations/PTB/stock/RM_flour')!.kind,
      WriteKind.setMerge,
    );
    expect(p.plan.opAt(_device)!.data, {'lastMovementSeq': 42});
    expect(p.plan.opAt(_device)!.kind, WriteKind.update);
  });

  test('stockIn: a blank note is stored as null', () {
    final p = StockPlans.stockIn(
      ctx: Fx.sm(),
      seq: 42,
      lines: const [StockQty(Fx.flour, 1)],
      note: '  ',
    );
    expect(p.plan.opAt(_m)!.data['note'], isNull);
  });

  test('stockOutRaw: negative deltas with the reason, no audit', () {
    final p = StockPlans.stockOutRaw(
      ctx: Fx.sm(),
      seq: 42,
      lines: const [StockQty(Fx.flour, 700)],
      reason: 'Sent to MNJ',
    );
    expect(p.plan.paths, [_m, 'locations/PTB/stock/RM_flour', _device]);
    expect(
      p.plan.opAt(_m)!.data,
      _movement('STOCK_OUT_RAW', [
        {'itemKey': 'RM_flour', 'delta': -700},
      ], reason: 'Sent to MNJ'),
    );
    expect(
      p.plan.opAt('locations/PTB/stock/RM_flour')!.data,
      _stock(Fx.flour, -700, 'D01-M000042'),
    );
  });

  test('wastage FG: WASTAGE_FG with a WASTAGE audit {loc}-{movementId}', () {
    final p = StockPlans.wastage(
      ctx: Fx.sm(),
      seq: 42,
      kind: StockKind.finished,
      lines: [StockQty(Fx.cakeStock, 1)],
      reason: 'Dropped',
    );
    expect(p.plan.paths, [
      _m,
      'locations/PTB/stock/FG_cake-choco-1kg',
      'auditLog/PTB-D01-M000042',
      _device,
    ]);
    expect(
      p.plan.opAt(_m)!.data,
      _movement('WASTAGE_FG', [
        {'itemKey': 'FG_cake-choco-1kg', 'delta': -1},
      ], reason: 'Dropped'),
    );
    expect(p.plan.opAt('auditLog/PTB-D01-M000042')!.data, {
      'action': 'WASTAGE',
      'entityPath': _m,
      'locationId': 'PTB',
      'before': null,
      'after': {
        'type': 'WASTAGE_FG',
        'lines': {'FG_cake-choco-1kg': -1},
      },
      'reason': 'Dropped',
      'by': Fx.smUid,
      'deviceId': 'D01',
      'clientAt': Fx.now,
      'at': serverTimestamp,
    });
  });

  test('wastage RAW is WASTAGE_RAW', () {
    final p = StockPlans.wastage(
      ctx: Fx.sm(),
      seq: 42,
      kind: StockKind.raw,
      lines: const [StockQty(Fx.cream, 200)],
      reason: 'Spoilt',
    );
    expect(p.value.type, MovementType.wastageRaw);
    expect(p.plan.opAt('auditLog/PTB-D01-M000042'), isNotNull);
  });

  test('produce: consumed raw down, produced FG up, one movement', () {
    final p = StockPlans.produce(
      ctx: Fx.sm(),
      seq: 42,
      consumed: const [StockQty(Fx.flour, 1000), StockQty(Fx.cream, 500)],
      produced: [StockQty(Fx.cakeStock, 2)],
    );
    expect(p.plan.paths, [
      _m,
      'locations/PTB/stock/RM_flour',
      'locations/PTB/stock/RM_cream',
      'locations/PTB/stock/FG_cake-choco-1kg',
      _device,
    ]);
    expect(
      p.plan.opAt(_m)!.data,
      _movement('PRODUCE', [
        {'itemKey': 'RM_flour', 'delta': -1000},
        {'itemKey': 'RM_cream', 'delta': -500},
        {'itemKey': 'FG_cake-choco-1kg', 'delta': 2},
      ]),
    );
    expect(
      p.plan.opAt('locations/PTB/stock/FG_cake-choco-1kg')!.data,
      _stock(Fx.cakeStock, 2, 'D01-M000042'),
    );
  });

  test('adjust: delta = counted − local, before/after, STOCK_ADJUST audit', () {
    final p = StockPlans.adjust(
      ctx: Fx.sm(),
      seq: 42,
      item: Fx.flour,
      localQty: 1200,
      countedQty: 900,
      reason: 'Monthly count',
    );
    expect(p.plan.paths, [
      _m,
      'locations/PTB/stock/RM_flour',
      'auditLog/PTB-D01-M000042',
      _device,
    ]);
    expect(
      p.plan.opAt(_m)!.data,
      _movement('ADJUST', [
        {'itemKey': 'RM_flour', 'delta': -300, 'before': 1200, 'after': 900},
      ], reason: 'Monthly count'),
    );
    expect(
      p.plan.opAt('locations/PTB/stock/RM_flour')!.data,
      _stock(Fx.flour, -300, 'D01-M000042'),
    );
    final audit = p.plan.opAt('auditLog/PTB-D01-M000042')!.data;
    expect(audit['action'], 'STOCK_ADJUST');
    expect(audit['before'], {'itemKey': 'RM_flour', 'qty': 1200});
    expect(audit['after'], {'itemKey': 'RM_flour', 'qty': 900});
    expect(audit['reason'], 'Monthly count');
  });

  test('adjust from a negative local quantity', () {
    final p = StockPlans.adjust(
      ctx: Fx.sm(),
      seq: 1,
      item: Fx.cakeStock,
      localQty: -2,
      countedQty: 0,
      reason: 'Count',
    );
    expect(p.value.lines.single.delta, 2);
  });

  test('setThreshold: set(merge) of identity and lowThreshold, no qty', () {
    final plan = StockPlans.setThreshold(
      ctx: Fx.sm(),
      item: Fx.cream,
      threshold: 2000,
    );
    expect(plan.ops, hasLength(1));
    expect(plan.ops.single.kind, WriteKind.setMerge);
    expect(plan.ops.single.path, 'locations/PTB/stock/RM_cream');
    expect(plan.ops.single.data, {
      'kind': 'RAW',
      'refId': 'cream',
      'name': 'Cream',
      'unit': 'ML',
      'lowThreshold': 2000,
      'updatedAt': serverTimestamp,
    });
    final cleared = StockPlans.setThreshold(
      ctx: Fx.sm(),
      item: Fx.cream,
      threshold: null,
    );
    expect(cleared.ops.single.data['lowThreshold'], isNull);
    expect(cleared.ops.single.data.containsKey('lowThreshold'), isTrue);
  });

  group('refuses', () {
    test('empty, non-positive, duplicate, wrong kind, too many lines', () {
      expect(
        () => StockPlans.stockIn(ctx: Fx.sm(), seq: 1, lines: const []),
        _violation(),
      );
      expect(
        () => StockPlans.stockIn(
          ctx: Fx.sm(),
          seq: 1,
          lines: const [StockQty(Fx.flour, 0)],
        ),
        _violation(),
      );
      expect(
        () => StockPlans.stockIn(
          ctx: Fx.sm(),
          seq: 1,
          lines: const [StockQty(Fx.flour, 1), StockQty(Fx.flour, 2)],
        ),
        _violation(),
      );
      expect(
        () => StockPlans.stockIn(
          ctx: Fx.sm(),
          seq: 1,
          lines: [StockQty(Fx.cakeStock, 1)],
        ),
        _violation(),
      );
      expect(
        () => StockPlans.produce(
          ctx: Fx.sm(),
          seq: 1,
          consumed: const [StockQty(Fx.flour, 1)],
          produced: const [StockQty(Fx.cream, 1)],
        ),
        _violation(),
      );
      final many = [
        for (var i = 0; i < Limits.maxMovementLines + 1; i++)
          StockQty(
            StockRef(
              kind: StockKind.raw,
              refId: 'm$i',
              name: 'M$i',
              unit: StockUnit.g,
            ),
            1,
          ),
      ];
      expect(
        () => StockPlans.stockIn(ctx: Fx.sm(), seq: 1, lines: many),
        _violation(),
      );
      expect(
        StockPlans.stockIn(
          ctx: Fx.sm(),
          seq: 1,
          lines: many.sublist(1),
        ).value.lines,
        hasLength(Limits.maxMovementLines),
      );
    });

    test('a missing reason, a negative count or threshold', () {
      expect(
        () => StockPlans.wastage(
          ctx: Fx.sm(),
          seq: 1,
          kind: StockKind.raw,
          lines: const [StockQty(Fx.flour, 1)],
          reason: ' ',
        ),
        _violation(),
      );
      expect(
        () => StockPlans.stockOutRaw(
          ctx: Fx.sm(),
          seq: 1,
          lines: const [StockQty(Fx.flour, 1)],
          reason: '',
        ),
        _violation(),
      );
      expect(
        () => StockPlans.adjust(
          ctx: Fx.sm(),
          seq: 1,
          item: Fx.flour,
          localQty: 1,
          countedQty: -1,
          reason: 'x',
        ),
        _violation(),
      );
      expect(
        () => StockPlans.setThreshold(
          ctx: Fx.sm(),
          item: Fx.flour,
          threshold: -1,
        ),
        _violation(),
      );
    });

    test('no device registered', () {
      expect(
        () => StockPlans.stockIn(
          ctx: PlanContext(uid: 'u', locationId: 'PTB', now: Fx.now),
          seq: 1,
          lines: const [StockQty(Fx.flour, 1)],
        ),
        throwsA(
          isA<DataFailure>().having(
            (f) => f.reason,
            'reason',
            FailureReason.deviceNotRegistered,
          ),
        ),
      );
    });
  });
}
