import '../core/logging.dart';
import '../data/local/database.dart';
import '../services/artifact_store.dart';
import '../services/auth_service.dart';
import '../services/billing_service.dart';
import '../services/expense_service.dart';
import '../services/ingredient_service.dart';
import '../services/member_service.dart';
import '../services/menu_service.dart';
import '../services/notification_service.dart';
import '../services/purchase_schedule_service.dart';
import '../services/qr_service.dart';
import '../services/recipe_service.dart';
import '../services/refund_service.dart';
import '../services/scan_service.dart';
import '../services/settings_service.dart';
import '../services/topup_service.dart';
import '../services/user_service.dart';

/// Owns the database and every service — the single wiring point for host mode
/// (CLAUDE.md §5: dependencies injected, constructed once). Both the embedded
/// server's routes and the in-process HostBackend read from the same instance,
/// so business rules run in exactly one place (PRD §13.7).
class HostContainer {
  HostContainer._({
    required this.db,
    required this.artifacts,
    required this.auth,
    required this.settings,
    required this.members,
    required this.scans,
    required this.topups,
    required this.refunds,
    required this.menu,
    required this.expenses,
    required this.users,
    required this.ingredients,
    required this.recipes,
    required this.purchaseSchedule,
    required this.notifications,
  });

  /// [documentsDir] is where the SQLite file and generated artifacts live.
  factory HostContainer.create({
    required AppDatabase db,
    required String documentsDir,
    required Duration sessionTtl,
  }) {
    final artifacts = ArtifactStore(documentsDir);
    final qr = QrService();
    final billing = BillingService();
    final auth = AuthService(db, sessionTtl: sessionTtl);
    final settings = SettingsService(db);

    return HostContainer._(
      db: db,
      artifacts: artifacts,
      auth: auth,
      settings: settings,
      members: MemberService(db, qr),
      scans: ScanService(db, settings),
      topups: TopupService(db, settings, billing, qr, artifacts),
      refunds: RefundService(db, settings),
      menu: MenuService(db),
      expenses: ExpenseService(db),
      users: UserService(db, auth),
      ingredients: IngredientService(db),
      recipes: RecipeService(db),
      purchaseSchedule: PurchaseScheduleService(db),
      notifications: NotificationService(db, settings),
    );
  }

  final AppDatabase db;
  final ArtifactStore artifacts;
  final AuthService auth;
  final SettingsService settings;
  final MemberService members;
  final ScanService scans;
  final TopupService topups;
  final RefundService refunds;
  final MenuService menu;
  final ExpenseService expenses;
  final UserService users;
  final IngredientService ingredients;
  final RecipeService recipes;
  final PurchaseScheduleService purchaseSchedule;
  final NotificationService notifications;

  final _log = log('host');

  /// Runs once when the host starts: create the initial admin if there are no
  /// users yet. Returns a generated password to show the operator once, or null
  /// if an admin already existed or a password was configured.
  Future<String?> bootstrap({
    required String initialAdminUsername,
    String? initialAdminPassword,
  }) async {
    final generated = await auth.bootstrapInitialAdmin(
      username: initialAdminUsername,
      password: initialAdminPassword,
    );
    _log.info('host_container_ready');
    return generated;
  }

  Future<void> dispose() => db.close();
}
