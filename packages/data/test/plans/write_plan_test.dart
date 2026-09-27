import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_data/nexus_data.dart';

void main() {
  group('nestFieldPaths', () {
    test('turns dotted paths into nested maps', () {
      expect(
        nestFieldPaths({
          'billCount': 1,
          'byMode.CASH': 5,
          'byProduct.P1.qty': 2,
          'byProduct.P1.amount': 300,
          'byProduct.P2.qty': 1,
        }),
        {
          'billCount': 1,
          'byMode': {'CASH': 5},
          'byProduct': {
            'P1': {'qty': 2, 'amount': 300},
            'P2': {'qty': 1},
          },
        },
      );
    });

    test('refuses clashing or repeated fields', () {
      expect(() => nestFieldPaths({'a': 1, 'a.b': 2}), throwsArgumentError);
      expect(() => nestFieldPaths({'a.b': 1, 'a': 2}), throwsArgumentError);
    });
  });

  group('JSON encoding', () {
    final at = DateTime.utc(2026, 9, 26, 4, 30);
    final plan = WritePlan([
      WriteOp('a/b', WriteKind.create, {
        'n': 1,
        's': 'x',
        'b': true,
        'nil': null,
        'at': at,
        'list': [
          {'at': at},
        ],
        'st': serverTimestamp,
      }),
      const WriteOp('a/c', WriteKind.setMerge, {
        'm': {'k': Increment(-3)},
      }),
      const WriteOp('a/d', WriteKind.update, {'f.g': Increment(2)}),
    ]);

    test('uses the fixture sentinels', () {
      expect(plan.toJson(), {
        'ops': [
          {
            'path': 'a/b',
            'kind': 'create',
            'data': {
              'n': 1,
              's': 'x',
              'b': true,
              'nil': null,
              'at': {'__op': 'timestamp', 'value': '2026-09-26T04:30:00.000Z'},
              'list': [
                {
                  'at': {
                    '__op': 'timestamp',
                    'value': '2026-09-26T04:30:00.000Z',
                  },
                },
              ],
              'st': {'__op': 'serverTimestamp'},
            },
          },
          {
            'path': 'a/c',
            'kind': 'setMerge',
            'data': {
              'm': {
                'k': {'__op': 'increment', 'by': -3},
              },
            },
          },
          {
            'path': 'a/d',
            'kind': 'update',
            'data': {
              'f.g': {'__op': 'increment', 'by': 2},
            },
          },
        ],
      });
    });

    test('round-trips', () {
      final back = decodePlan(plan.toJson());
      expect(back.paths, plan.paths);
      for (var i = 0; i < plan.ops.length; i++) {
        expect(back.ops[i].kind, plan.ops[i].kind);
        expect(back.ops[i].data, plan.ops[i].data);
      }
    });

    test('a local DateTime is written in UTC', () {
      expect(encodePlanValue(at.toLocal()), {
        '__op': 'timestamp',
        'value': '2026-09-26T04:30:00.000Z',
      });
    });

    test('refuses values Firestore plans never hold', () {
      expect(() => encodePlanValue(1.5), throwsArgumentError);
    });
  });

  test('PlanBuilder refuses a second write to one doc', () {
    final b = PlanBuilder()..create('x/1', {});
    expect(() => b.update('x/1', {}), throwsStateError);
  });

  test('sentinels compare by value', () {
    expect(const Increment(2), const Increment(2));
    expect(const Increment(2), isNot(const Increment(3)));
    expect(const Increment(2).hashCode, const Increment(2).hashCode);
    expect(const ServerTimestamp(), serverTimestamp);
    expect(const ServerTimestamp().hashCode, serverTimestamp.hashCode);
  });
}
