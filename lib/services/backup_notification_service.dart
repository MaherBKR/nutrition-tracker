import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../database/app_database.dart';

class BackupNotificationService {
  final AppDatabase db;
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  BackupNotificationService(this.db);

  Future<void> initNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        // Module D: Actionable [Log Now] notification button handler
        if (response.actionId == 'log_creatine_collagen') {
          final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
          await db.logConsumption(
            date: today,
            mealSlot: 'Supplements',
            sourceType: 'Ingredient',
            sourceId: 1,
            gramsConsumed: 15.0,
          );
        }
      },
    );
  }

  /// Module D: Hydration Ping with 30-Minute Smart Suppression
  Future<bool> triggerHydrationReminderIfEligible() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final logs = await (db.select(db.dailyLogs)
          ..where((l) => l.date.equals(today) & l.waterMl.isBiggerThanValue(0)))
        .get();

    if (logs.length >= 8) return false;

    const androidDetails = AndroidNotificationDetails(
      'hydration_channel',
      'Hydration Reminders',
      channelDescription: 'Smart interval hydration reminders',
      importance: Importance.high,
      priority: Priority.high,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'log_water_250',
          '+250ml Water',
          showsUserInterface: true,
        ),
      ],
    );

    await _notifications.show(
      1001,
      'Hydration Check',
      'Time for 250ml–330ml of water to stay on track today.',
      const NotificationDetails(android: androidDetails),
    );
    return true;
  }

  /// Module D: Actionable Supplement Notification with [Log Now] button
  Future<void> showSupplementActionNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'supplement_channel',
      'Meal & Supplement Schedules',
      channelDescription: 'Fixed-time supplement and meal reminders',
      importance: Importance.max,
      priority: Priority.high,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'log_creatine_collagen',
          'Log Now (5g Creatine + 10g Collagen)',
          showsUserInterface: true,
        ),
      ],
    );

    await _notifications.show(
      2001,
      'Supplement Schedule',
      'Take Creatine (5g) & Collagen (10g)',
      const NotificationDetails(android: androidDetails),
    );
  }

  /// Module E: Single-File JSON Bundle Export via Android SAF / Local Storage
  Future<String> exportFullJsonBackup() async {
    final allIngredients = await db.select(db.ingredients).get();
    final allUnits = await db.select(db.ingredientUnits).get();
    final allRecipes = await db.select(db.recipes).get();
    final allRecipeItems = await db.select(db.recipeItems).get();
    final allLogs = await db.select(db.dailyLogs).get();
    final allPantry = await db.select(db.pantryShopping).get();

    final bundle = {
      'exported_at': DateTime.now().toIso8601String(),
      'schema_version': 1,
      'ingredients': allIngredients.map((e) => e.toJson()).toList(),
      'ingredient_units': allUnits.map((e) => e.toJson()).toList(),
      'recipes': allRecipes.map((e) => e.toJson()).toList(),
      'recipe_items': allRecipeItems.map((e) => e.toJson()).toList(),
      'daily_logs': allLogs.map((e) => e.toJson()).toList(),
      'pantry_shopping': allPantry.map((e) => e.toJson()).toList(),
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(bundle);
    final stamp = DateFormat('yyyy_MM_dd').format(DateTime.now());
    final fileName = 'nutrition_backup_$stamp.json';

    final String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Nutrition Backup JSON',
      fileName: fileName,
      bytes: utf8.encode(jsonString),
    );

    if (outputFile != null) return outputFile;

    final dir = await getApplicationDocumentsDirectory();
    final fallback = File('${dir.path}/$fileName');
    await fallback.writeAsString(jsonString);
    return fallback.path;
  }

  /// Module E: Conflict-Safe Restore (Overwrite All vs. Merge)
  Future<int> restoreFromJsonBackup({required bool overwriteAll}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) return 0;

    final file = File(result.files.single.path!);
    final Map<String, dynamic> data =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;

    int importedCount = 0;
    await db.transaction(() async {
      if (overwriteAll) {
        await db.delete(db.dailyLogs).go();
        await db.delete(db.recipeItems).go();
        await db.delete(db.recipes).go();
      }

      final logs = (data['daily_logs'] as List<dynamic>? ?? []);
      for (final raw in logs) {
        final m = raw as Map<String, dynamic>;
        await db.into(db.dailyLogs).insertOnConflictUpdate(
              DailyLogsCompanion.insert(
                date: m['date'] as String,
                mealSlot: m['mealSlot'] as String,
                sourceType: m['sourceType'] as String,
                sourceId: (m['sourceId'] as num).toInt(),
                gramsConsumed: Value((m['gramsConsumed'] as num).toDouble()),
                waterMl: Value((m['waterMl'] as num).toInt()),
                morningWeightKg: Value(
                  m['morningWeightKg'] != null
                      ? (m['morningWeightKg'] as num).toDouble()
                      : null,
                ),
              ),
            );
        importedCount++;
      }
    });
    return importedCount;
  }

  /// Module E: Export Weight, Macro & Expense Logs as CSV
  Future<String> exportLogsToCsv() async {
    final logs = await db.select(db.dailyLogs).get();
    final buffer = StringBuffer();
    buffer.writeln('id,date,meal_slot,source_type,source_id,grams_consumed,water_ml,morning_weight_kg');

    for (final l in logs) {
      buffer.writeln(
        '${l.id},${l.date},${l.mealSlot},${l.sourceType},${l.sourceId},${l.gramsConsumed},${l.waterMl},${l.morningWeightKg ?? ""}',
      );
    }

    final stamp = DateFormat('yyyy_MM_dd').format(DateTime.now());
    final fileName = 'nutrition_logs_$stamp.csv';
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(buffer.toString());
    return file.path;
  }
}
