import 'package:nexus_core/nexus_core.dart';

import '../api/admin.dart';
import '../api/failures.dart';
import 'plan_support.dart';
import 'write_plan.dart';

/// Plans for the admin console and the catalog: expenses, products, raw
/// materials, locations and users. Online in practice, but built the same
/// way: one batch, with its audit doc (D-019).
abstract final class AdminPlans {
  /// Expense create ([before] null) or edit: the expense doc, the monthly
  /// summary increments of `SummaryDeltas.forExpense` (two docs when an
  /// edit moves it to another month or location) naming the audit doc, and
  /// the EXPENSE_CREATE / EXPENSE_UPDATE audit `EXP-{id}-{millis}`.
  ///
  /// [expenseId] is the new expense's ID for a create (it must pass
  /// `Ids.isSafeKey`), and must equal `before.id` for an edit. Throws
  /// `DataFailure(ruleViolation)` for a negative amount, a bad or future
  /// date, or a bad location code.
  static PlannedWrite<Expense> saveExpense({
    required PlanContext ctx,
    required String expenseId,
    required ExpenseInput input,
    Expense? before,
  }) {
    if (!Ids.isSafeKey(expenseId) ||
        (before != null && before.id != expenseId)) {
      throw DataFailure(FailureReason.ruleViolation, 'expense id $expenseId');
    }
    if (!Ids.isLocationCode(input.locationId)) {
      throw DataFailure(
        FailureReason.ruleViolation,
        'location ${input.locationId}',
      );
    }
    if (input.amount.isNegative) {
      throw const DataFailure(FailureReason.ruleViolation, 'amount below 0');
    }
    if (!BusinessDate.isValid(input.date) ||
        input.date.compareTo(ctx.businessDate) > 0) {
      throw DataFailure(FailureReason.ruleViolation, 'date ${input.date}');
    }
    final after = Expense(
      id: expenseId,
      locationId: input.locationId,
      category: input.category,
      amount: input.amount,
      date: input.date,
      note: input.note.trim(),
      createdBy: before?.createdBy ?? ctx.uid,
      createdAt: before?.createdAt,
    );
    final path = FirestorePaths.expense(expenseId);
    final auditPath = FirestorePaths.audit(
      Ids.expenseAuditId(input.locationId, expenseId, ctx.now),
    );
    final b = PlanBuilder();
    if (before == null) {
      b.create(
        path,
        withServerTimestamps(after.toMap(), Expense.serverTimestampFields),
      );
    } else {
      b.update(path, {
        'locationId': after.locationId,
        'category': after.category.wire,
        'amount': after.amount.paise,
        'date': after.date,
        'note': after.note,
        'updatedAt': serverTimestamp,
      });
    }
    for (final d in SummaryDeltas.forExpense(after: after, before: before)) {
      addSummaryWrites(
        b,
        locationId: d.locationId,
        monthKey: d.monthKey,
        delta: d.delta,
        lastWriteRef: auditPath,
      );
    }
    b.create(
      auditPath,
      auditDoc(
        action: before == null
            ? AuditAction.expenseCreate
            : AuditAction.expenseUpdate,
        entityPath: path,
        ctx: ctx,
        locationId: after.locationId,
        before: before == null ? null : _expenseFields(before),
        after: _expenseFields(after),
      ),
    );
    return PlannedWrite(after, b.build());
  }

  static Map<String, Object?> _expenseFields(Expense e) => {
    'locationId': e.locationId,
    'category': e.category.wire,
    'amount': e.amount.paise,
    'date': e.date,
    'note': e.note,
  };

  /// A Store Manager's local special (`catalog.suggest`, D-008): PENDING,
  /// no price, scoped to their location, with a proposed price.
  static PlannedWrite<Product> suggestProduct({
    required PlanContext ctx,
    required String productId,
    required String name,
    required String category,
    required Money proposedPrice,
  }) {
    final loc = ctx.requireLocation();
    if (!proposedPrice.isPositive) {
      throw const DataFailure(FailureReason.ruleViolation, 'proposed price');
    }
    final product = Product(
      id: productId,
      name: name.trim(),
      category: category.trim(),
      proposedPrice: proposedPrice,
      scope: loc,
      status: ProductStatus.pending,
      sortOrder: 0,
      createdBy: ctx.uid,
    );
    return PlannedWrite(product, _createProduct(product));
  }

  /// Create ([existing] null) or edit a product (`catalog.manage`). An edit
  /// that changes the price writes a PRICE_CHANGE audit. `createdBy` and
  /// `createdAt` are never rewritten on an edit. The caller assigns a new
  /// product's ID and `createdBy` (AD-CR-1).
  static PlannedWrite<Product> saveProduct({
    required PlanContext ctx,
    required Product product,
    Product? existing,
  }) {
    if (existing != null && existing.id != product.id) {
      throw DataFailure(FailureReason.ruleViolation, 'product ${product.id}');
    }
    if (product.status == ProductStatus.active && product.price == null) {
      throw const DataFailure(
        FailureReason.ruleViolation,
        'an active product needs a price',
      );
    }
    if (existing == null) {
      if (product.createdBy != ctx.uid) {
        throw const DataFailure(FailureReason.ruleViolation, 'createdBy');
      }
      return PlannedWrite(product, _createProduct(product));
    }
    final path = FirestorePaths.product(product.id);
    final fields = product.toMap()..remove('createdBy');
    final b = PlanBuilder()
      ..update(path, {...fields, 'updatedAt': serverTimestamp});
    if (existing.price != product.price) {
      b.create(
        FirestorePaths.audit(PlanAuditIds.priceChange(product.id, ctx.now)),
        auditDoc(
          action: AuditAction.priceChange,
          entityPath: path,
          ctx: ctx,
          before: {'price': existing.price?.paise},
          after: {'price': product.price?.paise},
        ),
      );
    }
    return PlannedWrite(product, b.build());
  }

  /// Approves a PENDING product at [price] (`catalog.manage`, D-008), with a
  /// PRODUCT_APPROVE audit.
  static PlannedWrite<Product> approveProduct({
    required PlanContext ctx,
    required Product existing,
    required Money price,
  }) {
    if (existing.status != ProductStatus.pending) {
      throw const DataFailure(FailureReason.ruleViolation, 'not pending');
    }
    if (!price.isPositive) {
      throw const DataFailure(FailureReason.ruleViolation, 'price');
    }
    final path = FirestorePaths.product(existing.id);
    final approved = Product(
      id: existing.id,
      name: existing.name,
      category: existing.category,
      price: price,
      proposedPrice: existing.proposedPrice,
      unit: existing.unit,
      gstRate: existing.gstRate,
      scope: existing.scope,
      status: ProductStatus.active,
      recipe: existing.recipe,
      sortOrder: existing.sortOrder,
      createdBy: existing.createdBy,
      createdAt: existing.createdAt,
    );
    final plan =
        (PlanBuilder()
              ..update(path, {
                'status': ProductStatus.active.wire,
                'price': price.paise,
                'updatedAt': serverTimestamp,
              })
              ..create(
                FirestorePaths.audit(
                  PlanAuditIds.productApprove(existing.id, ctx.now),
                ),
                auditDoc(
                  action: AuditAction.productApprove,
                  entityPath: path,
                  ctx: ctx,
                  before: {
                    'status': existing.status.wire,
                    'price': existing.price?.paise,
                    'proposedPrice': existing.proposedPrice?.paise,
                  },
                  after: {
                    'status': ProductStatus.active.wire,
                    'price': price.paise,
                    'proposedPrice': existing.proposedPrice?.paise,
                  },
                ),
              ))
            .build();
    return PlannedWrite(approved, plan);
  }

  static WritePlan _createProduct(Product p) {
    if (!Ids.isSafeKey(p.id)) {
      throw DataFailure(FailureReason.ruleViolation, 'product id ${p.id}');
    }
    if (p.name.isEmpty) {
      throw const DataFailure(FailureReason.ruleViolation, 'name');
    }
    return (PlanBuilder()..create(
          FirestorePaths.product(p.id),
          withServerTimestamps(p.toMap(), Product.serverTimestampFields),
        ))
        .build();
  }

  /// A new raw material (`rawMaterial.create`). The caller assigns the ID.
  static PlannedWrite<RawMaterial> addRawMaterial({
    required PlanContext ctx,
    required String materialId,
    required String name,
    required StockUnit unit,
  }) {
    if (!Ids.isSafeKey(materialId)) {
      throw DataFailure(FailureReason.ruleViolation, 'material $materialId');
    }
    final m = RawMaterial(
      id: materialId,
      name: name.trim(),
      unit: unit,
      active: true,
      createdBy: ctx.uid,
    );
    if (m.name.isEmpty) {
      throw const DataFailure(FailureReason.ruleViolation, 'name');
    }
    return PlannedWrite(
      m,
      (PlanBuilder()..create(FirestorePaths.rawMaterial(materialId), m.toMap()))
          .build(),
    );
  }

  /// The location fields an edit may write: never `code` or `nextDeviceNo`
  /// (QA-035), and `overridePinHash` only with a new PIN.
  static const List<String> editableLocationFields = [
    'name',
    'address',
    'phone',
    'gstin',
    'offlineLimitHours',
    'overrideExtensionHours',
    'maxDiscountPct',
    'receiptFooter',
    'active',
  ];

  /// Create ([existing] null) or edit a location (`location.manage`), with a
  /// LOCATION_UPDATE audit that never holds the PIN hash.
  ///
  /// A create writes every field with `nextDeviceNo: 0` and needs
  /// [newPinHash]; an edit writes [editableLocationFields] only, plus
  /// `overridePinHash` when [newPinHash] is given. Hash the PIN with
  /// `PinHasher` first (PBKDF2, 02-DATA-MODEL).
  static PlannedWrite<Location> saveLocation({
    required PlanContext ctx,
    required Location location,
    Location? existing,
    String? newPinHash,
  }) {
    final code = location.code;
    if (!Ids.isLocationCode(code) ||
        (existing != null && existing.code != code)) {
      throw DataFailure(FailureReason.ruleViolation, 'code $code');
    }
    if (existing == null && newPinHash == null) {
      throw const DataFailure(
        FailureReason.ruleViolation,
        'a new location needs a PIN',
      );
    }
    final stored = Location(
      code: code,
      name: location.name,
      address: location.address,
      phone: location.phone,
      gstin: location.gstin,
      offlineLimitHours: location.offlineLimitHours,
      overridePinHash: newPinHash ?? existing!.overridePinHash,
      overrideExtensionHours: location.overrideExtensionHours,
      maxDiscountPct: location.maxDiscountPct,
      receiptFooter: location.receiptFooter,
      nextDeviceNo: existing?.nextDeviceNo ?? 0,
      active: location.active,
    );
    final path = FirestorePaths.location(code);
    final all = stored.toMap();
    final b = PlanBuilder();
    if (existing == null) {
      b.create(path, all);
    } else {
      b.update(path, {
        for (final f in editableLocationFields) f: all[f],
        'overridePinHash': ?newPinHash,
      });
    }
    b.create(
      FirestorePaths.audit(PlanAuditIds.locationUpdate(code, ctx.now)),
      auditDoc(
        action: AuditAction.locationUpdate,
        entityPath: path,
        ctx: ctx,
        locationId: code,
        before: existing == null ? null : _locationAudit(existing),
        after: {
          ..._locationAudit(stored),
          if (newPinHash != null && existing != null) 'pinChanged': true,
        },
      ),
    );
    return PlannedWrite(stored, b.build());
  }

  static Map<String, Object?> _locationAudit(Location l) {
    final m = l.toMap();
    return {for (final f in editableLocationFields) f: m[f]};
  }

  /// Enables or disables a user (`user.manage`, D-018), with a USER_DISABLE
  /// or USER_ENABLE audit (`Ids.userAuditId`, D-032, QA-046). Nobody
  /// changes their own `active` (04-PERMISSIONS #3).
  static PlannedWrite<AppUser> setUserActive({
    required PlanContext ctx,
    required AppUser user,
    required bool active,
  }) {
    if (user.uid == ctx.uid) {
      throw const DataFailure(
        FailureReason.ruleViolation,
        'you cannot change your own active flag',
      );
    }
    final updated = AppUser(
      uid: user.uid,
      name: user.name,
      email: user.email,
      roleId: user.roleId,
      locationId: user.locationId,
      active: active,
      createdBy: user.createdBy,
      createdAt: user.createdAt,
    );
    final path = FirestorePaths.user(user.uid);
    final b = PlanBuilder()..update(path, {'active': active});
    b.create(
      FirestorePaths.audit(Ids.userAuditId(user.locationId, user.uid, ctx.now)),
      auditDoc(
        action: active ? AuditAction.userEnable : AuditAction.userDisable,
        entityPath: path,
        ctx: ctx,
        locationId: user.locationId,
        before: {'active': user.active},
        after: {'active': active},
      ),
    );
    return PlannedWrite(updated, b.build());
  }
}
