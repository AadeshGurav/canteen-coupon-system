import '../core/role.dart';

/// Expenses, users, notifications, auth payloads (PRD §6.6, §4, §6.5.2).

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ---------------------------------------------------------------------------
// Expenses & revenue
// ---------------------------------------------------------------------------

class Expense {
  const Expense({
    required this.id,
    required this.category,
    required this.description,
    required this.amount,
    required this.date,
    required this.createdBy,
  });

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: j['id'] as int,
        category: j['category'] as String,
        description: j['description'] as String,
        amount: (j['amount'] as num).toDouble(),
        date: DateTime.parse(j['date'] as String),
        createdBy: j['createdBy'] as String,
      );

  final int id;
  final String category;
  final String description;
  final double amount;
  final DateTime date;
  final String createdBy;

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'description': description,
        'amount': amount,
        'date': _ymd(date),
        'createdBy': createdBy,
      };
}

class ExpenseDraft {
  const ExpenseDraft({
    required this.category,
    required this.description,
    required this.amount,
    required this.date,
    required this.createdBy,
  });

  factory ExpenseDraft.fromJson(Map<String, dynamic> j) => ExpenseDraft(
        category: j['category'] as String,
        description: j['description'] as String,
        amount: (j['amount'] as num).toDouble(),
        date: DateTime.parse(j['date'] as String),
        createdBy: j['createdBy'] as String,
      );

  final String category;
  final String description;
  final double amount;
  final DateTime date;
  final String createdBy;

  Map<String, dynamic> toJson() => {
        'category': category,
        'description': description,
        'amount': amount,
        'date': _ymd(date),
        'createdBy': createdBy,
      };
}

class ProfitSummary {
  const ProfitSummary({
    required this.revenue,
    required this.expenses,
    required this.profit,
  });

  factory ProfitSummary.fromJson(Map<String, dynamic> j) => ProfitSummary(
        revenue: (j['revenue'] as num).toDouble(),
        expenses: (j['expenses'] as num).toDouble(),
        profit: (j['profit'] as num).toDouble(),
      );

  final double revenue;
  final double expenses;
  final double profit;

  Map<String, dynamic> toJson() =>
      {'revenue': revenue, 'expenses': expenses, 'profit': profit};
}

// ---------------------------------------------------------------------------
// Users & auth
// ---------------------------------------------------------------------------

class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.role,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as int,
        username: j['username'] as String,
        role: Role.fromWire(j['role'] as String),
        status: j['status'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
      );

  final int id;
  final String username;
  final Role role;
  final String status; // 'active' | 'inactive'
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'role': role.wire,
        'status': status,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };
}

class UserDraft {
  const UserDraft({
    required this.username,
    required this.password,
    required this.role,
  });

  factory UserDraft.fromJson(Map<String, dynamic> j) => UserDraft(
        username: j['username'] as String,
        password: j['password'] as String,
        role: Role.fromWire(j['role'] as String),
      );

  final String username;
  final String password;
  final Role role;

  Map<String, dynamic> toJson() =>
      {'username': username, 'password': password, 'role': role.wire};
}

class UserPatch {
  const UserPatch({this.password, this.role, this.status});

  factory UserPatch.fromJson(Map<String, dynamic> j) => UserPatch(
        password: j['password'] as String?,
        role: j['role'] == null ? null : Role.fromWire(j['role'] as String),
        status: j['status'] as String?,
      );

  final String? password;
  final Role? role;
  final String? status;

  Map<String, dynamic> toJson() => {
        if (password != null) 'password': password,
        if (role != null) 'role': role!.wire,
        if (status != null) 'status': status,
      };
}

class AuthSession {
  const AuthSession({
    required this.token,
    required this.username,
    required this.role,
  });

  factory AuthSession.fromJson(Map<String, dynamic> j) => AuthSession(
        token: j['token'] as String,
        username: j['username'] as String,
        role: Role.fromWire(j['role'] as String),
      );

  final String token;
  final String username;
  final Role role;

  Map<String, dynamic> toJson() =>
      {'token': token, 'username': username, 'role': role.wire};
}

// ---------------------------------------------------------------------------
// Notifications (PRD §6.5.2)
// ---------------------------------------------------------------------------

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as int,
        type: j['type'] as String,
        title: j['title'] as String,
        message: j['message'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );

  final int id;
  final String type; // 'prep_reminder' | 'purchase_due'
  final String title;
  final String message;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'message': message,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };
}
