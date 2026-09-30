import 'package:nexus_core/nexus_core.dart';

import '../api/admin.dart';
import '../api/catalog.dart';
import '../api/failures.dart';
import '../plans/admin_plans.dart';
import '../plans/pin_hasher.dart';
import 'write_env.dart';

/// [CatalogService] on Firestore. A Store Manager's suggestion and a new
/// raw material work offline like any POS write; product edits and
/// approvals are Admin actions (`catalog.manage`).
final class FirestoreCatalogService implements CatalogService {
  FirestoreCatalogService(this._env);

  final WriteEnv _env;

  @override
  Future<Product> suggest({
    required String name,
    required String category,
    required Money proposedPrice,
  }) async {
    final loc = _env.requireAtOwnLocation(Permission.catalogSuggest);
    final planned = AdminPlans.suggestProduct(
      ctx: _env.context(_env.requireSession(), locationId: loc, at: _env.now()),
      productId: _env.ids.next('p'),
      name: name,
      category: category,
      proposedPrice: proposedPrice,
    );
    await _env.write(
      planned.plan,
      label: 'Suggested product "${planned.value.name}"',
    );
    return planned.value;
  }

  @override
  Future<Product> save(Product product) async {
    final s = _env.require(Permission.catalogManage);
    if (!Ids.isSafeKey(product.id)) {
      throw DataFailure(FailureReason.ruleViolation, 'product ${product.id}');
    }
    final existing = await _env.reads.product(product.id);
    final planned = AdminPlans.saveProduct(
      ctx: _env.context(s, at: _env.now()),
      product: product,
      existing: existing,
    );
    await _env.write(planned.plan, label: 'Product "${product.name}"');
    return planned.value;
  }

  @override
  Future<Product> approve({
    required String productId,
    required Money price,
  }) async {
    final s = _env.require(Permission.catalogManage);
    final existing = await _env.reads.product(productId);
    if (existing == null) {
      throw DataFailure(FailureReason.notFound, 'product $productId');
    }
    final planned = AdminPlans.approveProduct(
      ctx: _env.context(s, at: _env.now()),
      existing: existing,
      price: price,
    );
    await _env.write(planned.plan);
    return planned.value;
  }

  @override
  Future<RawMaterial> addRawMaterial({
    required String name,
    required StockUnit unit,
  }) async {
    final s = _env.require(Permission.rawMaterialCreate);
    final planned = AdminPlans.addRawMaterial(
      ctx: _env.context(s, at: _env.now()),
      materialId: _env.ids.next('m'),
      name: name,
      unit: unit,
    );
    await _env.write(
      planned.plan,
      label: 'Raw material "${planned.value.name}"',
    );
    return planned.value;
  }
}

/// [ExpenseService] on Firestore (`expense.manage` at the expense's
/// location, before and after an edit).
final class FirestoreExpenseService implements ExpenseService {
  FirestoreExpenseService(this._env);

  final WriteEnv _env;

  @override
  Future<Expense> save(ExpenseInput input) async {
    final s = _env.requireAt(Permission.expenseManage, input.locationId);
    Expense? before;
    final id = input.id;
    if (id != null) {
      before = await _env.reads.expense(id);
      if (before == null) {
        throw DataFailure(FailureReason.notFound, 'expense $id');
      }
      _env.requireAt(Permission.expenseManage, before.locationId);
    }
    final planned = AdminPlans.saveExpense(
      ctx: _env.context(s, at: _env.now()),
      expenseId: id ?? _env.ids.next('e'),
      input: input,
      before: before,
    );
    await _env.write(planned.plan);
    return planned.value;
  }
}

/// [LocationService] on Firestore (`location.manage`). An edit writes the
/// editable fields only, never `nextDeviceNo` (QA-035), and replaces the PIN
/// hash only when a new PIN is given.
final class FirestoreLocationService implements LocationService {
  FirestoreLocationService(this._env, {PinHasher? hasher})
    : _hasher = hasher ?? PinHasher();

  final WriteEnv _env;
  final PinHasher _hasher;

  @override
  Future<Location> save(Location location, {String? newPin}) async {
    final s = _env.requireAt(Permission.locationManage, location.code);
    if (newPin != null) PinHasher.checkPin(newPin);
    final existing = await _env.reads.location(location.code);
    final hash = newPin == null ? null : await _hasher.hash(newPin);
    final planned = AdminPlans.saveLocation(
      ctx: _env.context(s, at: _env.now()),
      location: location,
      existing: existing,
      newPinHash: hash,
    );
    await _env.write(planned.plan);
    return planned.value;
  }
}
