import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const _channelId = 'daily_reminder';
const _channelName = 'Щоденне нагадування';
const _notificationId = 1;
const _reminderHour = 20;

const _letterChannelId = 'time_capsule';
const _letterChannelName = 'Капсули часу';

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

/// Питає дозвіл на сповіщення (якщо ще не питали) і планує щоденне
/// нагадування о 20:00 за місцевим часом. Неточний режим
/// (inexactAllowWhileIdle) — кілька хвилин різниці не критичні для такого
/// нагадування, а точний вимагав би окремого "чутливого" дозволу
/// SCHEDULE_EXACT_ALARM і супровідної Play-політики.
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
    matchDateTimeComponents: DateTimeComponents.time,
  );
  return true;
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

/// Одноразова нотифікація на дату розкриття конкретної капсули часу — на
/// відміну від щоденного нагадування, не повторюється й не має
/// matchDateTimeComponents. `id` виводиться з UUID листа (a не з рахунку),
/// щоб не збігтись із daily reminder (id=1) і щоб скасування/переплановування
/// одного листа не чіпало інші. inexactAllowWhileIdle — той самий компроміс,
/// що й для щоденного нагадування: кілька хвилин різниці не критичні, а
/// точний режим вимагав би окремого чутливого дозволу.
Future<void> scheduleLetterUnlockNotification({
  required String letterId,
  required DateTime unlockAt,
  required String title,
  required String body,
}) async {
  final granted = await _requestPermission();
  if (!granted) return;

  await _plugin.zonedSchedule(
    id: letterId.hashCode & 0x7FFFFFFF,
    title: title,
    body: body,
    scheduledDate: tz.TZDateTime.from(unlockAt, tz.local),
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(_letterChannelId, _letterChannelName),
      iOS: DarwinNotificationDetails(),
    ),
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
  );
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
