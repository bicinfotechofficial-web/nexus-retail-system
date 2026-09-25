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
