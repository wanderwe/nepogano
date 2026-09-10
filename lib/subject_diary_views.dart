import 'package:supabase_flutter/supabase_flutter.dart';

import 'checkin_date.dart';

/// Дата НАЙСВІЖІШОГО чужого запису в цій сутності, який я ще не бачив в
/// Історії. Використовується лише для навігаційної підказки одразу після
/// перемикання чіпа: [markSubjectTabViewed] гасить тільки "сьогоднішню"
/// частину індикатора — якщо після цього [subjectsWithUnseenUpdates] все
/// одно повертає цю сутність, новий запис лежить десь у МИНУЛОМУ, і без
/// цього виклику юзер бачить лише порожній сьогоднішній екран, не знаючи,
/// що саме й де шукати (реальна скарга: "мені треба здогадатись, що ще
/// треба зайти в Історію").
Future<DateTime?> latestUnseenHistoricalEntryDate(String subjectId) async {
  final supabase = Supabase.instance.client;
  final myId = supabase.auth.currentUser?.id;
  if (myId == null) return null;

  final viewRow = await supabase
      .from('subject_diary_views')
      .select('last_history_view_at')
      .eq('subject_id', subjectId)
      .eq('user_id', myId)
      .maybeSingle();
  final cutoffRaw = viewRow?['last_history_view_at'] as String?;
  final seenAt = cutoffRaw != null ? DateTime.parse(cutoffRaw) : null;

  var query = supabase
      .from('subject_checkins')
      .select('created_at, local_date')
      .eq('subject_id', subjectId)
      .neq('author_id', myId);
  // Звужуємо на сервері, коли є з чого — той самий фільтр, що й так
  // застосовується нижче в Dart, просто раніше передавав на клієнт усю
  // історію чужих записів навіть для давнього, вже переглянутого щоденника.
  final checkinRows = seenAt == null
      ? await query
      : await query.gt('created_at', seenAt.toUtc().toIso8601String());

  final today = DateTime.now();
  DateTime? latest;
  for (final row in checkinRows as List) {
    final createdAt = DateTime.parse(row['created_at'] as String);
    if (seenAt != null && !createdAt.isAfter(seenAt)) continue;
    final entryDate = effectiveCheckinDate(row);
    // Сьогоднішні записи сюди не належать — їх гасить last_tab_view_at
    // (markSubjectTabViewed, щойно викликаний перед цим у _switchSubject),
    // не last_history_view_at. Без цього виключення чужий сьогоднішній
    // чек-ін міг переважити справді старий непобачений день і підказка
    // "Переглянути" відкривала б Історію на СЬОГОДНІ замість того дня,
    // який юзер насправді ще не бачив (реальний баг, знайдений ревью).
    final isToday =
        entryDate.year == today.year &&
        entryDate.month == today.month &&
        entryDate.day == today.day;
    if (isToday) continue;
    if (latest == null || entryDate.isAfter(latest)) latest = entryDate;
  }
  return latest;
}

/// Позначає, що я щойно перемкнув чіп на цю сутність (бачив сьогоднішній
/// запис на головному екрані) — гасить лише "сьогоднішню" частину
/// індикатора, не історичну. Див. `docs/subject-diary-views-migration.sql`.
Future<void> markSubjectTabViewed(String subjectId) async {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return;
  await supabase.from('subject_diary_views').upsert({
    'user_id': userId,
    'subject_id': subjectId,
    'last_tab_view_at': DateTime.now().toUtc().toIso8601String(),
  });
}

/// Позначає, що я щойно відкрив повний календар (`HistoryScreen`) цієї
/// сутності — гасить обидві частини індикатора: і сьогоднішню, і історичну.
Future<void> markSubjectHistoryViewed(String subjectId) async {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return;
  final now = DateTime.now().toUtc().toIso8601String();
  await supabase.from('subject_diary_views').upsert({
    'user_id': userId,
    'subject_id': subjectId,
    'last_tab_view_at': now,
    'last_history_view_at': now,
  });
}

/// Які з переданих сутностей мають запис ЧУЖОГО авторства, ще не бачений
/// мною — окремо рахує "сьогодні" (проти `last_tab_view_at`, бо головний
/// екран і так показує сьогоднішній день) і "раніше" (проти
/// `last_history_view_at`, бо старі дні видно лише в Історії). Один
/// спільний timestamp тут не підійшов би: перегляд сьогоднішнього запису
/// на головному екрані інакше помилково гасив би й пропущені старі дні,
/// яких юзер в Історії ще не бачив.
Future<Set<String>> subjectsWithUnseenUpdates(List<String> subjectIds) async {
  if (subjectIds.isEmpty) return {};
  final supabase = Supabase.instance.client;
  final myId = supabase.auth.currentUser?.id;
  if (myId == null) return {};

  final viewRows = await supabase
      .from('subject_diary_views')
      .select('subject_id, last_tab_view_at, last_history_view_at')
      .inFilter('subject_id', subjectIds);
  final viewsBySubject = <String, Map<String, dynamic>>{
    for (final row in viewRows as List)
      row['subject_id'] as String: row as Map<String, dynamic>,
  };

  // neq з null author_id (легасі-записи до фічі співавторів) коректно
  // виключається самим Postgres (author_id <> myId невідомо для null) —
  // запис без відомого автора не рахуємо "чужим".
  final checkinRows = await supabase
      .from('subject_checkins')
      .select('subject_id, created_at, local_date')
      .inFilter('subject_id', subjectIds)
      .neq('author_id', myId);

  final today = DateTime.now();
  final result = <String>{};
  for (final row in checkinRows as List) {
    final subjectId = row['subject_id'] as String;
    final createdAt = DateTime.parse(row['created_at'] as String);
    // Спільний хелпер замість власної копії тієї самої логіки — та сама
    // семантика local_date/created_at-фолбеку, що вже застосовується
    // скрізь у застосунку, без ризику розійтись, якщо цей принцип колись
    // зміниться (напр. черговий timezone-фікс).
    final entryDate = effectiveCheckinDate(row);
    final isToday =
        entryDate.year == today.year &&
        entryDate.month == today.month &&
        entryDate.day == today.day;

    final view = viewsBySubject[subjectId];
    final cutoffRaw = isToday
        ? (view?['last_tab_view_at'] as String?)
        : (view?['last_history_view_at'] as String?);
    final seenAt = cutoffRaw != null ? DateTime.parse(cutoffRaw) : null;
    if (seenAt == null || createdAt.isAfter(seenAt)) {
      result.add(subjectId);
    }
  }
  return result;
}
