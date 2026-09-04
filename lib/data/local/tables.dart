import 'package:drift/drift.dart';

/// Relational schema — the on-device SQLite database used only in host mode
/// (PRD §13.3, §13.7). Each table maps conceptually to a v1 MongoDB collection
/// (PRD §8); embedded documents and nested maps are flattened into columns and
/// foreign keys per PRD §13.9.
///
/// Timestamps are stored as UTC `DateTime` (drift persists them as ISO-8601
/// text). Money is stored as `real` — this is not a currency ledger, just
/// bill/refund totals derived from configured unit prices (PRD §5).

// --------------------------------------------------------------------------
// Members (PRD §6.1) — students and staff are ONE entity, `type` distinguishes.
// --------------------------------------------------------------------------
class Members extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 'student' | 'staff'.
  TextColumn get type => text()();
  TextColumn get name => text().withLength(min: 1)();

  // Type-specific (validated in MemberService, not the schema): students carry
  // className/rollNumber, staff carry staffId.
  TextColumn get className => text().nullable()();
  TextColumn get rollNumber => text().nullable()();
  TextColumn get staffId => text().nullable()();

  /// Permanent, generated once, reused on every reprint (PRD §5, §6.2).
  TextColumn get qrCodeId => text().unique()();

  // Flattened balances (v1 embedded `balances` map).
  IntColumn get lunchBalance => integer().withDefault(const Constant(0))();
  IntColumn get breakfastBalance => integer().withDefault(const Constant(0))();
  IntColumn get brunchBalance => integer().withDefault(const Constant(0))();

  /// Per-member grace override; null means "use the global default" (PRD §5).
  IntColumn get graceAllowanceOverride => integer().nullable()();

  /// 'active' | 'inactive' — inactive fails scans with a clear reason.
  TextColumn get status => text().withDefault(const Constant('active'))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

// --------------------------------------------------------------------------
// Scans (PRD §5, §6.4) — one row per accepted scan; audit trail is preserved
// (a reversal flags the row, never deletes it).
// --------------------------------------------------------------------------
class Scans extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get memberId => integer().references(Members, #id)();
  TextColumn get mealType => text()();
  DateTimeColumn get scannedAt => dateTime()();

  /// Currently always 'accepted' — rejected attempts are logged, not stored,
  /// matching v1. Kept as a column so that can change without a migration.
  TextColumn get result => text().withDefault(const Constant('accepted'))();

  /// True when the scan pushed the balance negative — i.e. only possible
  /// because of the grace allowance (PRD §5). Surfaced as a badge in the UI.
  BoolColumn get viaGrace => boolean().withDefault(const Constant(false))();

  BoolColumn get reversed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get reversedAt => dateTime().nullable()();
  TextColumn get reversedBy => text().nullable()();
}

// --------------------------------------------------------------------------
// Top-ups (PRD §6.3) — credit/billing transactions.
// --------------------------------------------------------------------------
class Topups extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get memberId => integer().references(Members, #id)();

  IntColumn get lunchUnits => integer().withDefault(const Constant(0))();
  IntColumn get breakfastUnits => integer().withDefault(const Constant(0))();
  IntColumn get brunchUnits => integer().withDefault(const Constant(0))();

  /// Computed from settings.unitPrices × units — never client-supplied (PRD §6.3).
  RealColumn get amount => real()();

  /// 'cash' | 'upi'.
  TextColumn get paymentMethod => text()();

  /// 'confirmed' (cash, immediate) | 'pending' (upi, until admin confirms).
  TextColumn get paymentStatus => text()();

  /// Filesystem paths on the host device; null if generation failed (isolated
  /// failure — the credit still happened, PRD §6.3 / CLAUDE.md §5).
  TextColumn get billPdfPath => text().nullable()();
  TextColumn get upiQrPath => text().nullable()();

  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
}

// --------------------------------------------------------------------------
// Refunds (PRD §6.7) — unit ledger correction; the payout happens off-app.
// --------------------------------------------------------------------------
class Refunds extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get memberId => integer().references(Members, #id)();

  IntColumn get lunchUnits => integer().withDefault(const Constant(0))();
  IntColumn get breakfastUnits => integer().withDefault(const Constant(0))();
  IntColumn get brunchUnits => integer().withDefault(const Constant(0))();

  RealColumn get refundAmount => real()();
  TextColumn get reason => text().nullable()();
  TextColumn get processedBy => text()();
  DateTimeColumn get createdAt => dateTime()();
}

// --------------------------------------------------------------------------
// Menu planning (PRD §6.5).
// --------------------------------------------------------------------------
class MenuCategories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

class MenuEntries extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Calendar date only (time component is midnight local, stored UTC).
  DateTimeColumn get date => dateTime()();
  TextColumn get mealType => text()();

  /// JSON arrays of strings. Category names are validated against
  /// [MenuCategories] in MenuService before insert; item names are free text
  /// matched case-insensitively against [Recipes.dishNameLower].
  TextColumn get categoriesJson => text()();
  TextColumn get itemsJson => text()();

  TextColumn get createdBy => text()();
}

// --------------------------------------------------------------------------
// Ingredients, recipes, purchase schedule (PRD §6.5.1).
// --------------------------------------------------------------------------
class Ingredients extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  TextColumn get unit => text()(); // free text: "kg", "litre", "pcs"
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

class Recipes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get dishName => text()();

  /// Normalized (trimmed, lower-cased) — unique so two recipes can't shadow
  /// each other for what a menu entry treats as the same dish (PRD §6.5.1).
  TextColumn get dishNameLower => text().unique()();

  /// JSON array of {ingredientId:int, quantityNote:string}.
  TextColumn get ingredientsJson => text()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

class PurchaseScheduleItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()();
  IntColumn get ingredientId => integer().references(Ingredients, #id)();

  // Denormalized so a deleted ingredient doesn't blank the shopping list.
  TextColumn get ingredientName => text()();
  TextColumn get ingredientUnit => text()();
  TextColumn get quantityNote => text()();

  /// 'auto' (from the menu calendar) | 'manual' (ad-hoc).
  TextColumn get source => text()();

  BoolColumn get purchased => boolean().withDefault(const Constant(false))();
  TextColumn get purchasedBy => text().nullable()();
  DateTimeColumn get purchasedAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

// --------------------------------------------------------------------------
// Expenses (PRD §6.6).
// --------------------------------------------------------------------------
class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get category => text()();
  TextColumn get description => text()();
  RealColumn get amount => real()();
  DateTimeColumn get date => dateTime()();
  TextColumn get createdBy => text()();
}

// --------------------------------------------------------------------------
// Users & sessions (PRD §4).
// --------------------------------------------------------------------------
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get username => text().unique()();
  TextColumn get passwordHash => text()(); // salt$digest, pbkdf2-hmac-sha256
  TextColumn get role => text()(); // 'admin' | 'counter' | 'scanner'
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

class Sessions extends Table {
  /// Opaque random token (not a JWT) — PRD §8. Revoke by deleting the row.
  TextColumn get token => text()();
  IntColumn get userId => integer().references(Users, #id)();
  TextColumn get username => text()();
  TextColumn get role => text()();
  DateTimeColumn get createdAt => dateTime()();

  /// Expired rows are swept opportunistically by AuthService (no cron), the
  /// same "no scheduled job" reasoning as the v1 TTL index (PRD §8).
  DateTimeColumn get expiresAt => dateTime()();

  @override
  Set<Column> get primaryKey => {token};
}

// --------------------------------------------------------------------------
// Notifications (PRD §6.5.2) — persistent in-app reminders.
// --------------------------------------------------------------------------
class Notifications extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 'prep_reminder' | 'purchase_due'.
  TextColumn get type => text()();

  /// The (type, dateKey, mealType) triple is the idempotency key used by
  /// NotificationService's upsert. `dateKey` is an ISO date string.
  TextColumn get dateKey => text()();
  TextColumn get mealType => text().nullable()();

  TextColumn get title => text()();
  TextColumn get message => text()();

  /// JSON array of role names that can see this reminder.
  TextColumn get visibleRolesJson => text()();

  /// JSON array of usernames that dismissed it (per-user, PRD §6.5.2).
  TextColumn get dismissedByJson => text().withDefault(const Constant('[]'))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {type, dateKey, mealType},
      ];
}

// --------------------------------------------------------------------------
// Settings (PRD §6.8) — a single row (id = 0). Nested v1 maps (meal windows,
// unit prices) are flattened to explicit, type-checked columns per §13.9.
// --------------------------------------------------------------------------
class AppSettings extends Table {
  IntColumn get id => integer().withDefault(const Constant(0))();

  BoolColumn get graceAllowanceEnabled =>
      boolean().withDefault(const Constant(false))();
  IntColumn get graceAllowanceUnits =>
      integer().withDefault(const Constant(0))();
  IntColumn get reversalWindowMinutes =>
      integer().withDefault(const Constant(10))();

  TextColumn get breakfastStart =>
      text().withDefault(const Constant('07:00'))();
  TextColumn get breakfastEnd => text().withDefault(const Constant('09:30'))();
  TextColumn get lunchStart => text().withDefault(const Constant('12:00'))();
  TextColumn get lunchEnd => text().withDefault(const Constant('14:30'))();
  TextColumn get brunchStart => text().withDefault(const Constant('09:00'))();
  TextColumn get brunchEnd => text().withDefault(const Constant('12:00'))();

  /// IANA name (PRD §6.8). Validated against the tz database before write.
  TextColumn get localTimezone => text().withDefault(const Constant('UTC'))();

  TextColumn get upiId => text().withDefault(const Constant(''))();
  TextColumn get upiPayeeName => text().withDefault(const Constant(''))();

  RealColumn get lunchPrice => real().withDefault(const Constant(0))();
  RealColumn get breakfastPrice => real().withDefault(const Constant(0))();
  RealColumn get brunchPrice => real().withDefault(const Constant(0))();

  /// Branding shown in the app bar / tab title (PRD §6.8).
  TextColumn get appName => text().withDefault(const Constant('Tiffin'))();

  IntColumn get prepLeadMinutes => integer().withDefault(const Constant(60))();
  IntColumn get purchaseLeadDays => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}
