import 'package:supabase_flutter/supabase_flutter.dart';

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
    final localDateStr = row['local_date'] as String?;
    final entryDate = localDateStr != null
        ? DateTime.parse(localDateStr)
        : createdAt.toLocal();
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
