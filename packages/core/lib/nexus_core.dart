/// Shared contracts for both apps: enums, models, `Money`, calculators,
/// permission constants and Firestore paths. Pure Dart, no Flutter.
///
/// Owner: central.
///
/// Models read and write plain maps. Timestamps are `DateTime`; the data
/// package converts Firestore `Timestamp` values at the boundary and fills
/// each model's `serverTimestampFields` with `FieldValue.serverTimestamp()`.
library;

export 'src/bill_calculator.dart';
export 'src/business_date.dart';
export 'src/enums.dart';
export 'src/firestore_paths.dart';
export 'src/ids.dart';
export 'src/limits.dart';
export 'src/map_reader.dart';
export 'src/models/admin.dart';
export 'src/models/catalog.dart';
export 'src/models/org.dart';
export 'src/models/sales.dart';
export 'src/models/stock.dart';
export 'src/models/summary.dart';
export 'src/money.dart';
export 'src/permissions.dart';
export 'src/return_calculator.dart';
export 'src/summary_delta.dart';
