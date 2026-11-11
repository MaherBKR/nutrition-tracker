import '../database/app_database.dart';

class MacroTargets {
  final String profileName;
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;

  const MacroTargets({
    required this.profileName,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });
}

class WeightTrendPoint {
  final String date;
  final double rawWeightKg;
  final double ema7DayKg;

  const WeightTrendPoint({
    required this.date,
    required this.rawWeightKg,
    required this.ema7DayKg,
  });
}

class ReverseMacroSuggestion {
  final String title;
  final String portionDescription;
  final double calories;
  final double proteinG;
  final double cost;

  const ReverseMacroSuggestion({
    required this.title,
    required this.portionDescription,
    required this.calories,
    required this.proteinG,
    required this.cost,
  });
}

class NutritionEngine {
  // Feature 5.1: Training vs. Rest Day Macro Cycling
  static const MacroTargets trainingDayTargets = MacroTargets(
    profileName: 'Training / Match Day',
    calories: 2650,
    proteinG: 185,
    carbsG: 310,
    fatG: 72,
  );

  static const MacroTargets restDayTargets = MacroTargets(
    profileName: 'Rest / Recovery Day',
    calories: 2150,
    proteinG: 185,
    carbsG: 195,
    fatG: 70,
  );

  static MacroTargets getTargetsForWeekday(int weekday, {Set<int> trainingDays = const {1, 3, 5, 6}}) {
    return trainingDays.contains(weekday) ? trainingDayTargets : restDayTargets;
  }

  // Module A: 7-Day Rolling Exponential Moving Average (EMA) Weight Trend
  static List<WeightTrendPoint> compute7DayWeightEma(List<DailyLog> weightLogs) {
    final sorted = weightLogs.where((l) => l.morningWeightKg != null).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    if (sorted.isEmpty) return [];

    const double alpha = 2.0 / (7.0 + 1.0); // 7-day EMA smoothing factor (0.25)
    double currentEma = sorted.first.morningWeightKg!;
    final List<WeightTrendPoint> points = [];

    for (final log in sorted) {
      final raw = log.morningWeightKg!;
      currentEma = (raw * alpha) + (currentEma * (1.0 - alpha));
      points.add(
        WeightTrendPoint(
          date: log.date,
          rawWeightKg: raw,
          ema7DayKg: double.parse(currentEma.toStringAsFixed(2)),
        ),
      );
    }
    return points;
  }

  // Module C: Cost per 100g & Cost per 20g of Protein efficiency metric
  static double costPer20gProtein(Ingredient ing) {
    if (ing.pPer100g <= 0) return double.infinity;
    final gramsNeededFor20gP = (20.0 / ing.pPer100g) * 100.0;
    return (ing.pricePerKg / 1000.0) * gramsNeededFor20gP;
  }

  // Feature 5.4: Raw-to-Cooked Weight Converter Widget
  static const Map<String, double> cookingYieldRatios = {
    'Chicken / Turkey Breast (Air-Fried/Grilled)': 0.75, // 25% moisture loss
    'Lean Beef (Grilled/Pan-Seared)': 0.72,
    'Rice / Basmati (Boiled)': 2.80, // Absorbs water ~2.8x
    'Whole-Wheat Pasta (Boiled)': 2.25,
    'Lentils / Chickpeas (Boiled from dry)': 2.50,
    'Oats (Cooked Porridge)': 3.20,
  };

  static double convertRawToCooked({
    required double weightGrams,
    required String presetKey,
    required bool isRawToCooked,
  }) {
    final ratio = cookingYieldRatios[presetKey] ?? 1.0;
    return isRawToCooked ? weightGrams * ratio : weightGrams / ratio;
  }

  // Feature 5.2: "Hit My Remaining Macros" Reverse Calculator
  static List<ReverseMacroSuggestion> suggestFoodsForRemainingMacros({
    required double remainingProteinG,
    required double remainingCalories,
    required List<Ingredient> catalog,
  }) {
    if (remainingProteinG <= 2) return [];
    final List<ReverseMacroSuggestion> suggestions = [];

    for (final ing in catalog) {
      if (ing.pPer100g < 10.0) continue;
      final neededGrams = (remainingProteinG / ing.pPer100g) * 100.0;
      final resultingCalories = (neededGrams / 100.0) * ing.calPer100g;

      if (resultingCalories <= remainingCalories * 1.25) {
        final cost = (ing.pricePerKg / 1000.0) * neededGrams;
        String portionText = '${neededGrams.round()}g';
        if (ing.name.contains('Whey')) {
          final scoops = (neededGrams / 30.0).toStringAsFixed(1);
          portionText = '$scoops scoops (${neededGrams.round()}g)';
        } else if (ing.name.contains('Tuna')) {
          final cans = (neededGrams / 110.0).toStringAsFixed(1);
          portionText = '$cans drained cans (${neededGrams.round()}g)';
        } else if (ing.name.contains('Egg')) {
          final units = (neededGrams / 33.0).toStringAsFixed(1);
          portionText = '$units egg whites / units (${neededGrams.round()}g)';
        }

        suggestions.add(
          ReverseMacroSuggestion(
            title: '${ing.name} (${ing.prepMethod})',
            portionDescription: portionText,
            calories: resultingCalories,
            proteinG: remainingProteinG,
            cost: cost,
          ),
        );
      }
    }

    suggestions.sort((a, b) => (a.calories - remainingCalories).abs().compareTo(
          (b.calories - remainingCalories).abs(),
        ));
    return suggestions.take(5).toList();
  }
}
