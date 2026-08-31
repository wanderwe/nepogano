/// Ефективна (локальна) дата чек-іну — `local_date`, якщо клієнт її вже
/// записав при створенні, інакше наближення через `created_at.toLocal()`
/// для легасі-рядків без цього поля. Той самий принцип, що вже застосовують
/// RLS-функції на бекенді (`coalesce(local_date, created_at::date)`,
/// `checkin-local-date-timezone-fix-migration.sql`) — клієнт має рахувати
/// "який це день" так само, як сервер, інакше дії, що записують чи шукають
/// дату (вгадування, скрол до дня), можуть розійтись із тим, що бекенд
/// вважає правильним, і сервер відхилить те, що клієнт вважав коректним
/// (саме так одного разу мовчки відхилявся коментар після нібито вдалого
/// вгадування — `circle_guesses.target_date` рахувався з сирого
/// `created_at`, а RLS звіряв проти `local_date`).
DateTime effectiveCheckinDate(Map<String, dynamic> row) {
  final localDateStr = row['local_date'] as String?;
  if (localDateStr != null) return DateTime.parse(localDateStr);
  final createdAt = DateTime.parse(row['created_at'] as String).toLocal();
  return DateTime(createdAt.year, createdAt.month, createdAt.day);
}
