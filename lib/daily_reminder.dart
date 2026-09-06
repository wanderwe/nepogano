import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const _channelId = 'daily_reminder';
const _channelName = 'Щоденне нагадування';
const _notificationId = 1;
const _reminderHour = 20;

final _plugin = FlutterLocalNotificationsPlugin();

/// Готує плагін і локальний часовий пояс — виклик один раз при старті
/// застосунку (в main(), до runApp). Саме планування нагадування (з текстом
/// конкретною мовою і запитом дозволу) — окремо, в scheduleDailyReminder,
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
}

/// Питає дозвіл на сповіщення (якщо ще не питали) і планує ОДНОРАЗОВЕ
/// нагадування на найближчі 20:00 за місцевим часом. Неточний режим
/// (inexactAllowWhileIdle) — кілька хвилин різниці не критичні для такого
/// нагадування, а точний вимагав би окремого "чутливого" дозволу
/// SCHEDULE_EXACT_ALARM і супровідної Play-політики.
///
/// Навмисно одноразове, БЕЗ `matchDateTimeComponents` (раніше був
/// повторюваний на рівні ОС alarm) — юзер скаржився, що нагадування
/// приходить о 20:00 навіть якщо він уже відмітив сьогоднішній день:
/// повторюваний alarm ОС показує той самий текст щодня сам, без жодного
/// шансу для коду застосунку втрутитись перед показом (ні iOS, ні Android
/// не дають такого гачка для ЛОКАЛЬНИХ сповіщень). Тому тепер виклик цієї
/// функції — щоденний, з `_AuthGateState._setupDailyReminder` (лише коли
/// сьогоднішній чек-ін ще не збережено), а [cancelDailyReminder]
/// скасовує вже заплановане, щойно юзер таки зберігає день.
Future<bool> scheduleDailyReminder({
  required String title,
  required String body,
}) async {
  final granted = await _requestPermission();
  if (!granted) return false;

  await _plugin.zonedSchedule(
    id: _notificationId,
    title: title,
    body: body,
    scheduledDate: _next20,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(_channelId, _channelName),
      iOS: DarwinNotificationDetails(),
    ),
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
  );
  return true;
}

/// Скасовує сьогоднішнє заплановане нагадування, якщо воно ще не спрацювало
/// — викликається одразу після того, як юзер зберігає свій СЬОГОДНІШНІЙ
/// чек-ін (не чужий/сутності, не редагування вчорашнього), щоб не
/// отримувати "Як пройшов твій день" о 20:00 про день, який уже описаний.
Future<void> cancelDailyReminder() => _plugin.cancel(id: _notificationId);

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

// Навмисно НЕ tz.TZDateTime.now(tz.local) — якщо визначення часового поясу
// в initDailyReminder провалилось (наприклад, tz.getLocation не впізнав
// ідентифікатор від FlutterTimezone), tz.local тихо лишається дефолтним
// UTC пакету timezone, і 20:00 рахувалось як 20:00 UTC, тобто 23:00 в
// Києві влітку — саме так і трапилось на живому пристрої. DateTime.now()
// натомість Dart завжди рахує вірно (системний локальний зсув), незалежно
// від того, чи резолвнулась IANA-назва поясу — тому момент часу тут
// беремо звідси, а tz.local лишається лише міткою для TZDateTime.
tz.TZDateTime get _next20 {
  final now = DateTime.now();
  var scheduledLocal = DateTime(now.year, now.month, now.day, _reminderHour);
  if (scheduledLocal.isBefore(now)) {
    scheduledLocal = scheduledLocal.add(const Duration(days: 1));
  }
  return tz.TZDateTime.from(scheduledLocal, tz.local);
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
