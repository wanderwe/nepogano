import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const _channelId = 'daily_reminder';
const _channelName = 'Щоденне нагадування';
const _reminderHour = 20;

// Кожен день у вікні отримує СВІЙ notification id (не один спільний) —
// інакше не можна було б скасувати нагадування конкретно СЬОГОДНІШНЬОГО
// дня, не зачепивши заплановані на завтра/післязавтра. Базове зміщення —
// щоб не перетнутись з жодним іншим (поки не існує, але про всяк випадок)
// id, який колись з'явиться в застосунку.
const _reminderIdBase = 1000;
// iOS дозволяє щонайбільше 64 одночасно запланованих локальних сповіщень
// на застосунок — 30 днів наперед лишає великий запас і покриває місяць
// "тиші", перш ніж лапсд-юзер, що взагалі перестав відкривати застосунок,
// перестане отримувати нагадування.
const _reminderWindowDays = 30;

final _plugin = FlutterLocalNotificationsPlugin();

/// Готує плагін і локальний часовий пояс — виклик один раз при старті
/// застосунку (в main(), до runApp). Саме планування нагадувань (з текстом
/// конкретною мовою і запитом дозволу) — окремо, в scheduleDailyReminders,
/// бо йому потрібен контекст локалізації, якого тут ще нема.
Future<void> initDailyReminder() async {
  tz_data.initializeTimeZones();
  try {
    final timezoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneName.identifier));
  } catch (_) {
    // Не вдалось визначити часовий пояс пристрою — лишаємо дефолтний
    // (UTC) з пакету timezone. Нагадування прийде не рівно о 20:00 за
    // місцевим часом, але принаймні не впаде.
  }

  await _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
  );

  // Прибираємо застарілий notification id=1 з попередніх схем цієї фічі
  // (спершу повторюваний ОС-alarm, тоді одноразове нагадування на
  // найближчі 20:00 — обидва до переходу на поточне вікно з id від
  // `_reminderIdForDate`). Жоден код більше нічого не планує під id=1,
  // тож на пристрої, що не відкривався між тими версіями й цією, він міг
  // назавжди лишитись живим і "застряглим" з текстом старої версії.
  // cancel() безпечний навіть якщо такого id уже нема.
  try {
    await _plugin.cancel(id: 1);
  } catch (_) {}
}

/// Питає дозвіл на сповіщення (якщо ще не питали) і планує ОКРЕМЕ
/// одноразове нагадування на 20:00 КОЖНОГО з наступних [_reminderWindowDays]
/// днів (сьогодні включно, якщо ще не пізно й день ще не відмічено).
///
/// Раніше було ОДНЕ нагадування на найближчі 20:00, що самостійно
/// переплановував `_AuthGateState._setupDailyReminder` при кожному
/// відкритті застосунку — але це означало, що юзер, який просто відкрив
/// застосунок і щось у ньому зробив (тим самим скасувавши сьогоднішнє
/// нагадування), а завтра застосунок НЕ відкрив, взагалі не отримав би
/// нагадування назавтра: нічого не запланувало б наступний день. Тобто
/// сама дія в застосунку сьогодні тихо "вимикала" нагадування назавжди,
/// поки юзер не відкриє застосунок знову — а саме лапсд-юзери, які не
/// відкривають застосунок, і є головна ціль нагадування. Тепер наперед
/// планується ціле вікно днів одразу, з окремим id на кожен день
/// (`_reminderIdForDate`) — тож навіть якщо застосунок більше не
/// відкриють, усі вже заплановані дні все одно спрацюють по черзі. Кожне
/// відкриття застосунку (`_setupDailyReminder`, раз на календарний день)
/// лише "доливає" вікно ще на `_reminderWindowDays` вперед від поточного
/// дня — застосунок, який відкривають регулярно, завжди має повний запас
/// наперед; той, який покинули, доспрацьовує вже заплановане і замовкає.
///
/// Неточний режим (inexactAllowWhileIdle) — кілька хвилин різниці не
/// критичні для такого нагадування, а точний вимагав би окремого
/// "чутливого" дозволу SCHEDULE_EXACT_ALARM і супровідної Play-політики.
Future<bool> scheduleDailyReminders({
  required String title,
  required String body,
}) async {
  final granted = await _requestPermission();
  if (!granted) return false;

  // cancelAll() спершу — не лише зручність, а обов'язковий крок:
  // `_reminderIdForDate` уже двічі мінявся за час розробки цієї фічі
  // (спершу local-based різниця дат, тепер UTC-based, знайдено повторним
  // аудитом — local-based давала інший id, ніж UTC-based, для тієї самої
  // календарної дати, коли поточний зсув літнього/зимового часу
  // відрізняється від зсуву на момент якоря). Без cancelAll() пристрій,
  // що вже мав заплановані нагадування під СТАРОЮ формулою id, ніколи не
  // отримав би їх скасованими новим кодом (`cancelTodayReminder` рахує
  // ЛИШЕ поточну формулу) — вони або дублювались би з новими, або
  // `cancelTodayReminder` випадково скасовував би НЕ той день. Це не
  // разовий патч під конкретну зміну формули, а загальний захист: яка б
  // формула не була наступного разу, стара її версія завжди зачищається
  // тут, перш ніж вікно планується заново. У застосунку нема інших
  // локальних сповіщень (перевірено — це єдиний файл, що використовує
  // flutter_local_notifications), тож нічого зайвого не зачепить.
  await _plugin.cancelAll();

  final now = DateTime.now();
  final todayMidnight = DateTime(now.year, now.month, now.day);
  final alreadyCheckedInToday = await hasCheckedInToday();

  for (var i = 0; i < _reminderWindowDays; i++) {
    // DateTime(y, m, d + i), НЕ todayMidnight.add(Duration(days: i)) —
    // `.add(Duration)` рахує абсолютний, не календарний, час: якщо між
    // сьогодні і датою через `i` днів трапляється перехід на літній/зимовий
    // час, результат може зсунутись на ±1 годину відносно справжньої
    // півночі того дня, і `date.day` інколи вкаже не той календарний день
    // — реальний баг, знайдений повторним аудитом (це саме зробило б
    // `_reminderIdForDate` для дня зі зсувом іншим за той, що порахує
    // `cancelTodayReminder`, коли той самий день настане насправді).
    // Конструктор DateTime сам коректно нормалізує "день + i" як
    // календарну арифметику, без цієї пастки.
    final date = DateTime(
      todayMidnight.year,
      todayMidnight.month,
      todayMidnight.day + i,
    );
    if (i == 0 && alreadyCheckedInToday) continue;

    final scheduledLocal = DateTime(
      date.year,
      date.month,
      date.day,
      _reminderHour,
    );
    if (scheduledLocal.isBefore(now)) continue;

    await _plugin.zonedSchedule(
      id: _reminderIdForDate(date),
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(scheduledLocal, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(_channelId, _channelName),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
  return true;
}

/// Скасовує СЬОГОДНІШНЄ заплановане нагадування, якщо воно ще не
/// спрацювало — викликається одразу після того, як юзер зберігає свій
/// СЬОГОДНІШНІЙ чек-ін (не чужий/сутності, не редагування вчорашнього),
/// щоб не отримувати "Як пройшов твій день" о 20:00 про день, який уже
/// описаний. Не чіпає жоден із запланованих майбутніх днів вікна.
Future<void> cancelTodayReminder() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return _plugin.cancel(id: _reminderIdForDate(today));
}

int _reminderIdForDate(DateTime date) {
  // Різниця рахується через DateTime.utc, не сирі локальні DateTime —
  // `.difference().inDays` на локальних датах чутливий до кумулятивного
  // зсуву літнього/зимового часу між "сьогодні" й якорем (2024-01-01):
  // рівно опівнічні локальні дати все одно можуть відрізнятись на
  // ціле число днів ± дрібна частка години, і ціла частина `.inDays`
  // могла б округлитись не в той бік. UTC не знає літнього часу, тож
  // різниця завжди рівно ціле число днів.
  final anchor = DateTime.utc(2024, 1, 1);
  final dateUtc = DateTime.utc(date.year, date.month, date.day);
  return _reminderIdBase + dateUtc.difference(anchor).inDays;
}

/// Чи юзер уже зберіг ВЛАСНИЙ чек-ін за сьогодні (локальна дата) — від
/// цього залежить, чи взагалі планувати нагадування на сьогоднішні 20:00.
/// Той самий принцип local_date/created_at-fallback, що й у
/// `_CheckInScreenState._loadEntryForEffectiveDate` (main.dart) — там для
/// довільної дати й довільного щоденника (свій/сутність), тут — вужче,
/// лише "я, сьогодні", бо саме про це нагадування.
Future<bool> hasCheckedInToday() async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return false;

  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);
  final startOfNextDay = DateTime(now.year, now.month, now.day + 1);
  final localDate = startOfDay.toIso8601String().split('T').first;

  try {
    final rows = await Supabase.instance.client
        .from('checkins')
        .select('id')
        .eq('user_id', user.id)
        .or(
          'local_date.eq.$localDate,'
          'and(local_date.is.null,'
          'created_at.gte.${startOfDay.toUtc().toIso8601String()},'
          'created_at.lt.${startOfNextDay.toUtc().toIso8601String()})',
        )
        .limit(1);
    return (rows as List).isNotEmpty;
  } catch (_) {
    // Мережа/помилка запиту — краще все ж запланувати нагадування (fail
    // open у бік показу), ніж мовчки нічого не нагадати юзеру, який
    // насправді ще не відмітив день.
    return false;
  }
}

Future<bool> _requestPermission() async {
  if (Platform.isAndroid) {
    final impl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await impl?.requestNotificationsPermission() ?? false;
  }
  if (Platform.isIOS) {
    final impl = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    return await impl?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        false;
  }
  return false;
}
