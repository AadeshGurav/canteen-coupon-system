import 'dart:convert';

import '../../core/app_mode.dart';
import '../../core/role.dart';
import '../../domain/inventory.dart';
import '../../domain/ledger.dart';
import '../../domain/member.dart';
import '../../domain/menu.dart';
import '../../domain/ops.dart';
import 'database.dart' as db;

/// drift row → plain domain object. Host-side services return domain objects
/// so the API boundary (and the client) never sees a drift type (PRD §13.7).

Member memberFromRow(db.Member r) => Member(
      id: r.id,
      type: r.type,
      name: r.name,
      className: r.className,
      rollNumber: r.rollNumber,
      staffId: r.staffId,
      qrCodeId: r.qrCodeId,
      balances: UnitCounts(
        lunch: r.lunchBalance,
        breakfast: r.breakfastBalance,
        brunch: r.brunchBalance,
      ),
      graceAllowanceOverride: r.graceAllowanceOverride,
      status: r.status,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    );

ScanRecord scanFromRow(db.Scan r, String memberName) => ScanRecord(
      id: r.id,
      memberId: r.memberId,
      memberName: memberName,
      mealType: MealType.fromWire(r.mealType),
      scannedAt: r.scannedAt,
      result: r.result,
      viaGrace: r.viaGrace,
      reversed: r.reversed,
      reversedAt: r.reversedAt,
      reversedBy: r.reversedBy,
    );

Topup topupFromRow(db.Topup r) => Topup(
      id: r.id,
      memberId: r.memberId,
      lunchUnits: r.lunchUnits,
      breakfastUnits: r.breakfastUnits,
      brunchUnits: r.brunchUnits,
      amount: r.amount,
      paymentMethod: PaymentMethod.fromWire(r.paymentMethod),
      paymentStatus: r.paymentStatus,
      hasBill: r.billPdfPath != null,
      hasUpiQr: r.upiQrPath != null,
      createdBy: r.createdBy,
      createdAt: r.createdAt,
    );

Refund refundFromRow(db.Refund r) => Refund(
      id: r.id,
      memberId: r.memberId,
      lunchUnits: r.lunchUnits,
      breakfastUnits: r.breakfastUnits,
      brunchUnits: r.brunchUnits,
      refundAmount: r.refundAmount,
      reason: r.reason,
      processedBy: r.processedBy,
      createdAt: r.createdAt,
    );

MenuCategory menuCategoryFromRow(db.MenuCategory r) => MenuCategory(
      id: r.id,
      name: r.name,
      description: r.description,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    );

MenuEntry menuEntryFromRow(db.MenuEntry r) => MenuEntry(
      id: r.id,
      date: r.date,
      mealType: MealType.fromWire(r.mealType),
      categories: (jsonDecode(r.categoriesJson) as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      items: (jsonDecode(r.itemsJson) as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      createdBy: r.createdBy,
    );

Ingredient ingredientFromRow(db.Ingredient r) => Ingredient(
      id: r.id,
      name: r.name,
      unit: r.unit,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    );

Recipe recipeFromRow(db.Recipe r) => Recipe(
      id: r.id,
      dishName: r.dishName,
      ingredients: (jsonDecode(r.ingredientsJson) as List<dynamic>)
          .map((e) => RecipeIngredient.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    );

PurchaseScheduleItem purchaseItemFromRow(db.PurchaseScheduleItem r) =>
    PurchaseScheduleItem(
      id: r.id,
      date: r.date,
      ingredientId: r.ingredientId,
      ingredientName: r.ingredientName,
      ingredientUnit: r.ingredientUnit,
      quantityNote: r.quantityNote,
      source: r.source,
      purchased: r.purchased,
      purchasedBy: r.purchasedBy,
      purchasedAt: r.purchasedAt,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    );

Expense expenseFromRow(db.Expense r) => Expense(
      id: r.id,
      category: r.category,
      description: r.description,
      amount: r.amount,
      date: r.date,
      createdBy: r.createdBy,
    );

AppUser userFromRow(db.User r) => AppUser(
      id: r.id,
      username: r.username,
      role: Role.fromWire(r.role),
      status: r.status,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    );

AppNotification notificationFromRow(db.Notification r) => AppNotification(
      id: r.id,
      type: r.type,
      title: r.title,
      message: r.message,
      createdAt: r.createdAt,
    );
