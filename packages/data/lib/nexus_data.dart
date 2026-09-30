/// Firestore repositories, batch builders, the counter store and the sync
/// service. The only package that writes to Firestore.
///
/// `src/api/` is the contract the apps build against; the central agent owns
/// it, and changes go through docs/CHANGE-REQUESTS.md. The backend agent
/// implements it (BE-8 to BE-13).
library;

export 'src/api/admin.dart';
export 'src/api/catalog.dart';
export 'src/api/device.dart';
export 'src/api/failures.dart';
export 'src/api/reports.dart';
export 'src/api/sales.dart';
export 'src/api/session.dart';
export 'src/api/stock.dart';
export 'src/api/sync.dart';
export 'src/convert/firestore_values.dart';
export 'src/counters/counter_store.dart';
export 'src/counters/durable_store.dart';
export 'src/firestore/device_service.dart'
    show
        DeviceBackend,
        DeviceTxn,
        FirestoreDeviceBackend,
        FirestoreDeviceService;
export 'src/firestore/failure_mapping.dart';
export 'src/firestore/firebase_auth_service.dart';
export 'src/firestore/firestore_admin_repositories.dart';
export 'src/firestore/firestore_audit_repository.dart';
export 'src/firestore/firestore_catalog_repository.dart';
export 'src/firestore/firestore_sales_repository.dart';
export 'src/firestore/firestore_stock_repository.dart';
export 'src/firestore/firestore_summary_repository.dart';
export 'src/firestore/firestore_user_service.dart';
export 'src/plans/admin_plans.dart';
export 'src/plans/device_plans.dart';
export 'src/plans/offline_plans.dart';
export 'src/plans/pin_hasher.dart';
export 'src/plans/plan_support.dart';
export 'src/plans/sales_plans.dart';
export 'src/plans/stock_plans.dart';
export 'src/plans/write_plan.dart';
export 'src/sync/connectivity.dart';
export 'src/sync/firestore_sync_service.dart';
export 'src/sync/local_offline_guard.dart';
export 'src/sync/local_sync_state.dart';
export 'src/sync/sync_ledger.dart';
export 'src/write/firestore_admin_services.dart';
export 'src/write/firestore_sales_service.dart';
export 'src/write/firestore_stock_service.dart';
export 'src/write/plan_committer.dart';
export 'src/write/write_env.dart';
export 'src/write/write_reads.dart';
