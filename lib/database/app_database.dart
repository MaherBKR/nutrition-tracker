import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;

part 'app_database.g.dart';

class Ingredients extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get category => text()();
  TextColumn get prepMethod => text().withDefault(const Constant('Raw'))();
  RealColumn get calPer100g => real()();
  RealColumn get pPer100g => real()();
  RealColumn get cPer100g => real()();
  RealColumn get fPer100g => real()();
  IntColumn get defaultUnitId => integer().nullable()();
  RealColumn get unitPrice => real().withDefault(const Constant(0.0))();
  RealColumn get pricePerKg => real().withDefault(const Constant(0.0))();
}

class IngredientUnits extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get ingredientId =>
      integer().references(Ingredients, #id, onDelete: KeyAction.cascade)();
  TextColumn get unitName => text()();
  RealColumn get gramEquivalent => real()();
}

class Recipes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  RealColumn get totalCookedWeightG => real().withDefault(const Constant(0.0))();
  IntColumn get servings => integer().withDefault(const Constant(1))();
  IntColumn get fridgeQueueCount => integer().withDefault(const Constant(0))();
  TextColumn get prepNotes => text().withDefault(const Constant(''))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
}

class RecipeItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get recipeId =>
      integer().references(Recipes, #id, onDelete: KeyAction.cascade)();
  IntColumn get ingredientId => integer().references(Ingredients, #id)();
  IntColumn get unitId => integer().references(IngredientUnits, #id)();
  RealColumn get quantity => real()();
  RealColumn get calculatedGrams => real()();
}

class DailyLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()(); // Format: YYYY-MM-DD
  TextColumn get mealSlot => text()(); // Breakfast, Lunch, Dinner, Snack, Supplements
  TextColumn get sourceType => text()(); // Ingredient or Recipe
  IntColumn get sourceId => integer()();
  RealColumn get gramsConsumed => real().withDefault(const Constant(0.0))();
  IntColumn get waterMl => integer().withDefault(const Constant(0))();
  RealColumn get morningWeightKg => real().nullable()();
}

class PantryShopping extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get ingredientId =>
      integer().references(Ingredients, #id, onDelete: KeyAction.cascade)();
  RealColumn get currentStockG => real().withDefault(const Constant(0.0))();
  RealColumn get minThresholdG => real().withDefault(const Constant(200.0))();
  RealColumn get toBuyQty => real().withDefault(const Constant(0.0))();
  RealColumn get estimatedCost => real().withDefault(const Constant(0.0))();
  TextColumn get purchasedDate => text().nullable()();
  RealColumn get actualPricePaid => real().nullable()();
}

class Reminders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => text()(); // Water, Meal, Supplement
  TextColumn get title => text()();
  TextColumn get scheduleType => text()(); // Fixed Time / Interval
  TextColumn get timeOrInterval => text()(); // e.g., "08:30" or "90"
  TextColumn get daysActive => text().withDefault(const Constant('1,2,3,4,5,6,7'))();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
}

class MacroSummary {
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double cost;

  const MacroSummary({
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.cost = 0,
  });

  MacroSummary operator +(MacroSummary other) => MacroSummary(
        calories: calories + other.calories,
        protein: protein + other.protein,
        carbs: carbs + other.carbs,
        fat: fat + other.fat,
        cost: cost + other.cost,
      );

  MacroSummary scale(double factor) => MacroSummary(
        calories: calories * factor,
        protein: protein * factor,
        carbs: carbs * factor,
        fat: fat * factor,
        cost: cost * factor,
      );
}

@DriftDatabase(tables: [
  Ingredients,
  IngredientUnits,
  Recipes,
  RecipeItems,
  DailyLogs,
  PantryShopping,
  Reminders,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'nutrition_tracker_db'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          await seedFromBundle();
        },
      );

  Future<void> seedFromBundle() async {
    final existing = await select(ingredients).get();
    if (existing.isNotEmpty) return;

    final rawJson = await rootBundle.loadString('assets/seed_ingredients.json');
    final List<dynamic> list = jsonDecode(rawJson) as List<dynamic>;

    await transaction(() async {
      for (final item in list) {
        final map = item as Map<String, dynamic>;
        final priceKg = (map['price_per_kg'] as num).toDouble();
        final ingId = await into(ingredients).insert(
          IngredientsCompanion.insert(
            name: map['name'] as String,
            category: map['category'] as String,
            prepMethod: Value(map['prep_method'] as String),
            calPer100g: (map['cal_per_100g'] as num).toDouble(),
            pPer100g: (map['p_per_100g'] as num).toDouble(),
            cPer100g: (map['c_per_100g'] as num).toDouble(),
            fPer100g: (map['f_per_100g'] as num).toDouble(),
            pricePerKg: Value(priceKg),
            unitPrice: Value(priceKg / 10.0), // Cost per 100g
          ),
        );

        int? firstUnitId;
        final units = map['units'] as List<dynamic>;
        for (final u in units) {
          final uMap = u as Map<String, dynamic>;
          final uId = await into(ingredientUnits).insert(
            IngredientUnitsCompanion.insert(
              ingredientId: ingId,
              unitName: uMap['unit_name'] as String,
              gramEquivalent: (uMap['gram_equivalent'] as num).toDouble(),
            ),
          );
          firstUnitId ??= uId;
        }

        if (firstUnitId != null) {
          await (update(ingredients)..where((t) => t.id.equals(ingId)))
              .write(IngredientsCompanion(defaultUnitId: Value(firstUnitId)));
        }

        await into(pantryShopping).insert(
          PantryShoppingCompanion.insert(
            ingredientId: ingId,
            currentStockG: const Value(500.0),
            minThresholdG: const Value(200.0),
            estimatedCost: Value(priceKg * 0.5),
          ),
        );
      }
    });
  }

  /// Normalizes any ingredient + gram amount into exact macros and monetary cost
  MacroSummary calculateIngredientMacros(Ingredient ing, double grams) {
    final factor = grams / 100.0;
    return MacroSummary(
      calories: ing.calPer100g * factor,
      protein: ing.pPer100g * factor,
      carbs: ing.cPer100g * factor,
      fat: ing.fPer100g * factor,
      cost: (ing.pricePerKg / 1000.0) * grams,
    );
  }

  /// Calculates total batch macros, per-serving macros, or cooked-weight yield proportion
  Future<MacroSummary> calculateRecipeMacros(int recipeId, {double? consumedGrams}) async {
    final recipe = await (select(recipes)..where((r) => r.id.equals(recipeId))).getSingle();
    final rows = await (select(recipeItems)..where((ri) => ri.recipeId.equals(recipeId))).get();

    MacroSummary batchTotal = const MacroSummary();
    double rawWeightSum = 0;

    for (final item in rows) {
      final ing = await (select(ingredients)..where((i) => i.id.equals(item.ingredientId))).getSingle();
      batchTotal = batchTotal + calculateIngredientMacros(ing, item.calculatedGrams);
      rawWeightSum += item.calculatedGrams;
    }

    if (consumedGrams != null && consumedGrams > 0) {
      final effectiveBatchWeight =
          recipe.totalCookedWeightG > 0 ? recipe.totalCookedWeightG : rawWeightSum;
      if (effectiveBatchWeight <= 0) return batchTotal;
      return batchTotal.scale(consumedGrams / effectiveBatchWeight);
    }

    return batchTotal;
  }

  /// Clones an existing recipe so you can tweak an ingredient on the fly
  Future<int> cloneRecipe(int sourceRecipeId, String newName) async {
    return transaction(() async {
      final src = await (select(recipes)..where((r) => r.id.equals(sourceRecipeId))).getSingle();
      final items = await (select(recipeItems)..where((ri) => ri.recipeId.equals(sourceRecipeId))).get();

      final newId = await into(recipes).insert(
        RecipesCompanion.insert(
          name: newName,
          totalCookedWeightG: Value(src.totalCookedWeightG),
          servings: Value(src.servings),
          prepNotes: Value(src.prepNotes),
        ),
      );

      for (final item in items) {
        await into(recipeItems).insert(
          RecipeItemsCompanion.insert(
            recipeId: newId,
            ingredientId: item.ingredientId,
            unitId: item.unitId,
            quantity: item.quantity,
            calculatedGrams: item.calculatedGrams,
          ),
        );
      }
      return newId;
    });
  }

  /// Logs food and optionally auto-deducts from Pantry stock
  Future<void> logConsumption({
    required String date,
    required String mealSlot,
    required String sourceType,
    required int sourceId,
    required double gramsConsumed,
    bool autoDeductPantry = true,
  }) async {
    await transaction(() async {
      await into(dailyLogs).insert(
        DailyLogsCompanion.insert(
          date: date,
          mealSlot: mealSlot,
          sourceType: sourceType,
          sourceId: sourceId,
          gramsConsumed: Value(gramsConsumed),
        ),
      );

      if (autoDeductPantry && sourceType == 'Ingredient') {
        final pantryRow = await (select(pantryShopping)
              ..where((p) => p.ingredientId.equals(sourceId)))
            .getSingleOrNull();
        if (pantryRow != null) {
          final updatedStock = (pantryRow.currentStockG - gramsConsumed).clamp(0.0, 999999.0);
          final needsRestock = updatedStock < pantryRow.minThresholdG;
          await (update(pantryShopping)..where((p) => p.id.equals(pantryRow.id))).write(
            PantryShoppingCompanion(
              currentStockG: Value(updatedStock),
              toBuyQty: needsRestock
                  ? Value((pantryRow.minThresholdG * 2) - updatedStock)
                  : Value(pantryRow.toBuyQty),
            ),
          );
        }
      }
    });
  }
}
