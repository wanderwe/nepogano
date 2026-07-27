import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
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

tz.TZDateTime get _next20 {
  final now = tz.TZDateTime.now(tz.local);
  var scheduled = tz.TZDateTime(
    tz.local,
    now.year,
    now.month,
    now.day,
    _reminderHour,
  );
  if (scheduled.isBefore(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }
  return scheduled;
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
