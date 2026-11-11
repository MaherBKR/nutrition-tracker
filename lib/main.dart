import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'database/app_database.dart';
import 'services/backup_notification_service.dart';
import 'services/nutrition_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase();
  final backupService = BackupNotificationService(db);
  await backupService.initNotifications();
  runApp(NutritionTrackerApp(db: db, backupService: backupService));
}

class NutritionTrackerApp extends StatelessWidget {
  final AppDatabase db;
  final BackupNotificationService backupService;

  const NutritionTrackerApp({
    super.key,
    required this.db,
    required this.backupService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nutrition & Batch Prep Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF10B981),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: MainNavigationShell(db: db, backupService: backupService),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  final AppDatabase db;
  final BackupNotificationService backupService;

  const MainNavigationShell({
    super.key,
    required this.db,
    required this.backupService,
  });

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _selectedIndex = 0;
  bool _isTrainingDay = true;
  int _waterConsumedMl = 1250;
  final int _waterTargetMl = 3000;

  @override
  Widget build(BuildContext context) {
    final targets = _isTrainingDay
        ? NutritionEngine.trainingDayTargets
        : NutritionEngine.restDayTargets;

    final pages = [
      _buildDashboardTab(targets),
      _buildRecipeAndBatchTab(),
      _buildPantryAndFinanceTab(),
      _buildAnalyticsAndBackupTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(targets.profileName),
        actions: [
          Row(
            children: [
              const Text('Rest', style: TextStyle(fontSize: 12)),
              Switch(
                value: _isTrainingDay,
                onChanged: (val) => setState(() => _isTrainingDay = val),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Text('Train', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.donut_large), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.restaurant_menu), label: 'Batch & Recipes'),
          NavigationDestination(icon: Icon(Icons.shopping_cart), label: 'Pantry & Cost'),
          NavigationDestination(icon: Icon(Icons.insights), label: 'Analytics & Backup'),
        ],
      ),
    );
  }

  // MODULE A: Dashboard, Macro Rings, Hydration & Reverse Calculator
  Widget _buildDashboardTab(MacroTargets targets) {
    return FutureBuilder<List<Ingredient>>(
      future: widget.db.select(widget.db.ingredients).get(),
      builder: (context, snapshot) {
        final catalog = snapshot.data ?? [];
        const double eatenCal = 1820;
        const double eatenP = 142;
        const double eatenC = 185;
        const double eatenF = 52;

        final remP = (targets.proteinG - eatenP).clamp(0.0, 500.0);
        final remCal = (targets.calories - eatenCal).clamp(0.0, 5000.0);
        final suggestions = NutritionEngine.suggestFoodsForRemainingMacros(
          remainingProteinG: remP,
          remainingCalories: remCal,
          catalog: catalog,
        );

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${eatenCal.round()} / ${targets.calories.round()} kcal',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            Text('${remCal.round()} kcal remaining today'),
                          ],
                        ),
                        SizedBox(
                          height: 76,
                          width: 76,
                          child: PieChart(
                            PieChartData(
                              centerSpaceRadius: 24,
                              sectionsSpace: 2,
                              sections: [
                                PieChartSectionData(
                                  value: eatenCal,
                                  color: Colors.tealAccent,
                                  radius: 12,
                                  showTitle: false,
                                ),
                                PieChartSectionData(
                                  value: remCal,
                                  color: Colors.white12,
                                  radius: 12,
                                  showTitle: false,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _macroBar('Protein', eatenP, targets.proteinG, Colors.greenAccent),
                    const SizedBox(height: 8),
                    _macroBar('Carbs', eatenC, targets.carbsG, Colors.amberAccent),
                    const SizedBox(height: 8),
                    _macroBar('Fats', eatenF, targets.fatG, Colors.purpleAccent),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Hydration Tracker with Quick-Add Buttons
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hydration: $_waterConsumedMl / $_waterTargetMl ml',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: (_waterConsumedMl / _waterTargetMl).clamp(0.0, 1.0),
                      minHeight: 10,
                      color: Colors.lightBlueAccent,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [250, 330, 500].map((ml) {
                        return FilledButton.tonal(
                          onPressed: () => setState(() => _waterConsumedMl += ml),
                          child: Text('+${ml}ml'),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Feature 5.2: Hit My Remaining Macros Reverse Calculator
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hit Remaining Macros (${remP.round()}g P / ${remCal.round()} kcal left)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (suggestions.isEmpty)
                      const Text('Loading seed catalog suggestions...')
                    else
                      ...suggestions.map(
                        (s) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(s.title),
                          subtitle: Text(
                            '${s.portionDescription} • ${s.calories.round()} kcal • Cost: ${s.cost.toStringAsFixed(2)}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Logged ${s.title}')),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _macroBar(String label, double eaten, double target, Color color) {
    final pct = (eaten / target).clamp(0.0, 1.0);
    final rem = (target - eaten).clamp(0.0, 999.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$label: ${eaten.round()}g / ${target.round()}g'),
            Text('${rem.round()}g left (${(pct * 100).round()}%)'),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: pct, color: color, minHeight: 8),
      ],
    );
  }

  // MODULE B & FEATURE 5.3 / 5.4: Recipe Builder, Fridge Prep Queue & Raw-to-Cooked Converter
  Widget _buildRecipeAndBatchTab() {
    double rawInputG = 500;
    String selectedPreset = NutritionEngine.cookingYieldRatios.keys.first;
    int fridgeWrapsRemaining = 4;

    return StatefulBuilder(
      builder: (context, setInnerState) {
        final cookedEq = NutritionEngine.convertRawToCooked(
          weightGrams: rawInputG,
          presetKey: selectedPreset,
          isRawToCooked: true,
        );

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.kitchen, color: Colors.tealAccent),
                title: const Text('Fridge Batch Prep Queue: High-Protein Chicken Wraps'),
                subtitle: Text('$fridgeWrapsRemaining prepped wraps remaining in fridge (515 kcal | 46g P each)'),
                trailing: FilledButton(
                  onPressed: fridgeWrapsRemaining > 0
                      ? () => setInnerState(() => fridgeWrapsRemaining--)
                      : null,
                  child: const Text('1-Tap Log'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Raw-to-Cooked Yield Converter',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: selectedPreset,
                      items: NutritionEngine.cookingYieldRatios.keys
                          .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setInnerState(() => selectedPreset = val);
                      },
                    ),
                    Slider(
                      value: rawInputG,
                      min: 50,
                      max: 1500,
                      divisions: 29,
                      label: '${rawInputG.round()}g Raw',
                      onChanged: (v) => setInnerState(() => rawInputG = v),
                    ),
                    Text(
                      '${rawInputG.round()}g Raw  →  ${cookedEq.round()}g Cooked Batch Yield',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // MODULE C: Pantry Stock, Price per 20g Protein & Smart Shopping List
  Widget _buildPantryAndFinanceTab() {
    return FutureBuilder<List<Ingredient>>(
      future: widget.db.select(widget.db.ingredients).get(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? [];
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final ing = items[index];
            final costPer20gP = NutritionEngine.costPer20gProtein(ing);
            final costText = costPer20gP.isFinite
                ? '${costPer20gP.toStringAsFixed(2)} per 20g P'
                : 'Low protein';

            return Card(
              child: ListTile(
                title: Text('${ing.name} (${ing.prepMethod})'),
                subtitle: Text(
                  '${ing.calPer100g.round()} kcal | ${ing.pPer100g}g P | ${ing.cPer100g}g C | ${ing.fPer100g}g F per 100g',
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${ing.pricePerKg.toStringAsFixed(2)}/kg'),
                    Text(
                      costText,
                      style: const TextStyle(fontSize: 12, color: Colors.tealAccent),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // MODULE A (Graphs), MODULE D (Notifications) & MODULE E (SAF JSON/CSV Backups)
  Widget _buildAnalyticsAndBackupTab() {
    final sampleWeights = [78.4, 78.1, 78.3, 77.9, 77.8, 77.6, 77.5];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Morning Scale Weight vs. 7-Day Rolling EMA (kg)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 180,
                  child: LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: true),
                      titlesData: const FlTitlesData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: List.generate(
                            sampleWeights.length,
                            (i) => FlSpot(i.toDouble(), sampleWeights[i]),
                          ),
                          isCurved: true,
                          color: Colors.tealAccent,
                          barWidth: 3,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Smart Reminders & Backup Portability',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.notifications_active),
                      label: const Text('Test [Log Now] Supplement Push'),
                      onPressed: () =>
                          widget.backupService.showSupplementActionNotification(),
                    ),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Export JSON Backup'),
                      onPressed: () async {
                        final path =
                            await widget.backupService.exportFullJsonBackup();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Saved backup: $path')),
                          );
                        }
                      },
                    ),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.download),
                      label: const Text('Restore JSON (Merge)'),
                      onPressed: () => widget.backupService
                          .restoreFromJsonBackup(overwriteAll: false),
                    ),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.table_chart),
                      label: const Text('Export CSV'),
                      onPressed: () async {
                        final path = await widget.backupService.exportLogsToCsv();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Exported CSV: $path')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
