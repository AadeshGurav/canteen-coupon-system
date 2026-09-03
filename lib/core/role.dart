/// Login roles (PRD §4). Ordered widest → narrowest privilege.
enum Role {
  admin,
  counter,
  scanner;

  static Role fromWire(String value) => Role.values.firstWhere(
        (r) => r.name == value,
        orElse: () => throw ArgumentError('Unknown role: $value'),
      );

  String get wire => name;

  /// Can scan at the serving point.
  bool get canScan => true; // all three roles

  /// Can take payments / run top-ups and billing.
  bool get canBill => this == admin || this == counter;

  /// Can view + act on the purchase schedule (PRD §6.5.1).
  bool get canUsePurchaseSchedule => this == admin || this == counter;

  /// Everything else — member CRUD, menu planning, expenses, refunds,
  /// settings, user management, scan reversal.
  bool get isAdmin => this == admin;
}
