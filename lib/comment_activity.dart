import 'package:supabase_flutter/supabase_flutter.dart';

// Сховище на АКАУНТ (таблиця comment_activity_seen), не на пристрій —
// SharedPreferences тут навмисно НЕ використовується: локальне сховище не
// синхронізується між пристроями, тож заходячи з іншого телефону юзер бачив
// би всі раніше переглянуті коментарі знову як нові.
//
// Мітка "переглянуто" — множина конкретних id коментарів, а не єдина мітка
// часу "останній перегляд списку": один спільний курсор не може коректно
// відобразити "відкрив другий запис зі списку, а перший так і лишив
// непрочитаним" (часова мітка монотонна, id-шники — ні). Позначається не
// при відкритті самого списку, а коли юзер справді відкрив конкретний день
// ([SingleEntryScreen]) і побачив тред.
Future<Set<String>> _loadSeenIds(SupabaseClient supabase) async {
  final myId = supabase.auth.currentUser?.id;
  if (myId == null) return {};
  final rows = await supabase
      .from('comment_activity_seen')
      .select('comment_id')
      .eq('user_id', myId);
  return (rows as List).map((r) => r['comment_id'] as String).toSet();
}

/// Скільки подій підвантажувати за раз у [loadCommentActivityPage] — той
/// самий підхід, що [kGuessWindowDays] в PersonDetailScreen/SubjectDetail
/// Screen: не обмеження даних (RLS і так дає повний доступ), суто клієнтське
/// вікно, розширюване через "Показати ще".
const kCommentActivityPageSize = 20;

/// Одна подія в стрічці "Коментарі" — або хтось лишив коментар під МОЇМ
/// днем ([isReply] == false), або хтось відповів на МІЙ коментар під
/// чужим днем ([isReply] == true). Обидва випадки ведуть на той самий
/// єдиний день з тредом коментарів, тому й показуються в одному списку —
/// юзеру не треба самому розрізняти "свій пост / чужий пост", досить
/// одного "хтось написав тобі".
class CommentActivityItem {
  final String commentId;
  final String checkinId;
  final String? subjectId;
  final bool isSubject;
  final bool isOwnPost;
  final String authorName;
  final String body;
  final DateTime createdAt;
  final bool isReply;

  CommentActivityItem({
    required this.commentId,
    required this.checkinId,
    required this.subjectId,
    required this.isSubject,
    required this.isOwnPost,
    required this.authorName,
    required this.body,
    required this.createdAt,
    required this.isReply,
  });
}

class CommentActivityPage {
  final List<CommentActivityItem> items;
  // "Може бути більше" — приблизна оцінка (чи хоч один з двох сирих
  // запитів впирався у ліміт рядків), не точний count. Достатньо, щоб
  // вирішити, чи показувати кнопку "Показати ще".
  final bool hasMore;

  CommentActivityPage({required this.items, required this.hasMore});
}

class _RawRow {
  final String commentId;
  final String checkinId;
  final String? subjectId;
  final bool isSubject;
  final bool isOwnPost;
  final String authorId;
  final String body;
  final DateTime createdAt;
  final bool isReply;

  _RawRow({
    required this.commentId,
    required this.checkinId,
    required this.subjectId,
    required this.isSubject,
    required this.isOwnPost,
    required this.authorId,
    required this.body,
    required this.createdAt,
    required this.isReply,
  });
}

class _RawResult {
  final List<_RawRow> raw;
  final bool hasMore;

  _RawResult({required this.raw, required this.hasMore});
}

/// Спільна вибірка подій — і нові коментарі під власними днями (особистими
/// й сутностей, де я власник/співавтор), і відповіді на мої власні
/// коментарі під чужими днями. RLS (can_comment_on_checkin/
/// can_comment_on_subject_checkin) вже обмежує обидва запити нижче лише
/// тредами, які юзер і так має право бачити — фільтр [onMyPost]/[replyToMe]
/// тут лише розрізняє ДВІ категорії подій всередині вже безпечної вибірки,
/// не є самостійним контролем доступу.
///
/// [rowLimit] — якщо задано, обмежує КОЖЕН з двох сирих запитів (до
/// фільтрації на релевантність) і вмикає [before]-курсор для пагінації;
/// null — без обмежень (пейдж "непереглянуте" для бейджа завжди невеликий
/// сам по собі, пагінація там не потрібна).
Future<_RawResult> _fetchRaw(
  SupabaseClient supabase, {
  required String myId,
  required DateTime since,
  DateTime? before,
  int? rowLimit,
}) async {
  final sinceIso = since.toUtc().toIso8601String();
  final beforeIso = before?.toUtc().toIso8601String();

  final results = await Future.wait([
    supabase.from('checkins').select('id').eq('user_id', myId),
    supabase.from('checkin_comments').select('id').eq('author_id', myId),
    supabase.from('subjects').select('id').eq('owner_id', myId),
    supabase
        .from('subject_coauthors')
        .select('subject_id')
        .eq('coauthor_user_id', myId),
    supabase
        .from('subject_checkin_comments')
        .select('id')
        .eq('author_id', myId),
  ]);

  final myCheckinIds = (results[0] as List)
      .map((r) => r['id'] as String)
      .toSet();
  final myCheckinCommentIds = (results[1] as List)
      .map((r) => r['id'] as String)
      .toSet();
  final mySubjectIds = {
    ...(results[2] as List).map((r) => r['id'] as String),
    ...(results[3] as List).map((r) => r['subject_id'] as String),
  };
  final mySubjectCommentIds = (results[4] as List)
      .map((r) => r['id'] as String)
      .toSet();

  var mySubjectCheckinIds = <String>{};
  if (mySubjectIds.isNotEmpty) {
    final rows = await supabase
        .from('subject_checkins')
        .select('id')
        .inFilter('subject_id', mySubjectIds.toList());
    mySubjectCheckinIds = (rows as List).map((r) => r['id'] as String).toSet();
  }

  final raw = <_RawRow>[];
  var hasMore = false;

  if (myCheckinIds.isNotEmpty || myCheckinCommentIds.isNotEmpty) {
    var query = supabase
        .from('checkin_comments')
        .select('id, checkin_id, author_id, parent_id, body, created_at')
        .neq('author_id', myId)
        .gt('created_at', sinceIso);
    if (beforeIso != null) query = query.lt('created_at', beforeIso);
    var ordered = query.order('created_at', ascending: false);
    final rows = rowLimit == null
        ? await ordered
        : await ordered.limit(rowLimit);
    if (rowLimit != null && (rows as List).length >= rowLimit) hasMore = true;
    for (final row in rows as List) {
      final checkinId = row['checkin_id'] as String;
      final parentId = row['parent_id'] as String?;
      final onMyPost = myCheckinIds.contains(checkinId);
      final replyToMe =
          parentId != null && myCheckinCommentIds.contains(parentId);
      if (!onMyPost && !replyToMe) continue;
      raw.add(
        _RawRow(
          commentId: row['id'] as String,
          checkinId: checkinId,
          subjectId: null,
          isSubject: false,
          isOwnPost: onMyPost,
          authorId: row['author_id'] as String,
          body: row['body'] as String,
          createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
          isReply: !onMyPost && replyToMe,
        ),
      );
    }
  }

  if (mySubjectCheckinIds.isNotEmpty || mySubjectCommentIds.isNotEmpty) {
    var query = supabase
        .from('subject_checkin_comments')
        .select(
          'id, subject_checkin_id, author_id, parent_id, body, created_at',
        )
        .neq('author_id', myId)
        .gt('created_at', sinceIso);
    if (beforeIso != null) query = query.lt('created_at', beforeIso);
    var ordered = query.order('created_at', ascending: false);
    final rows = rowLimit == null
        ? await ordered
        : await ordered.limit(rowLimit);
    if (rowLimit != null && (rows as List).length >= rowLimit) hasMore = true;

    final relevant = <Map<String, dynamic>>[];
    for (final row in rows as List) {
      final checkinId = row['subject_checkin_id'] as String;
      final parentId = row['parent_id'] as String?;
      final onMyPost = mySubjectCheckinIds.contains(checkinId);
      final replyToMe =
          parentId != null && mySubjectCommentIds.contains(parentId);
      if (onMyPost || replyToMe) relevant.add(row);
    }

    if (relevant.isNotEmpty) {
      final checkinIds = relevant
          .map((r) => r['subject_checkin_id'] as String)
          .toSet()
          .toList();
      final subjectRows = await supabase
          .from('subject_checkins')
          .select('id, subject_id')
          .inFilter('id', checkinIds);
      final subjectIdByCheckinId = {
        for (final row in subjectRows as List)
          row['id'] as String: row['subject_id'] as String,
      };

      for (final row in relevant) {
        final checkinId = row['subject_checkin_id'] as String;
        final onMyPost = mySubjectCheckinIds.contains(checkinId);
        raw.add(
          _RawRow(
            commentId: row['id'] as String,
            checkinId: checkinId,
            subjectId: subjectIdByCheckinId[checkinId],
            isSubject: true,
            isOwnPost: onMyPost,
            authorId: row['author_id'] as String,
            body: row['body'] as String,
            createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
            isReply: !onMyPost,
          ),
        );
      }
    }
  }

  return _RawResult(raw: raw, hasMore: hasMore);
}

Future<List<CommentActivityItem>> _resolveNames(
  SupabaseClient supabase,
  List<_RawRow> raw,
) async {
  final authorIds = raw.map((r) => r.authorId).toSet().toList();
  var nameById = <String, String?>{};
  if (authorIds.isNotEmpty) {
    final nameRows = await supabase
        .from('profiles')
        .select('user_id, display_name')
        .inFilter('user_id', authorIds);
    nameById = {
      for (final row in nameRows as List)
        row['user_id'] as String: row['display_name'] as String?,
    };
  }

  return raw
      .map(
        (r) => CommentActivityItem(
          commentId: r.commentId,
          checkinId: r.checkinId,
          subjectId: r.subjectId,
          isSubject: r.isSubject,
          isOwnPost: r.isOwnPost,
          authorName: nameById[r.authorId] ?? '',
          body: r.body,
          createdAt: r.createdAt,
          isReply: r.isReply,
        ),
      )
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

/// Пагінований перегляд усієї стрічки (весь час, не тільки непереглянуте) —
/// [before] як курсор для "Показати ще" (дата найстарішого вже
/// завантаженого елемента). Позначка "нове" — окремо, через
/// [loadSeenCommentIds], бо це вже питання локального read-стану, не
/// вибірки даних.
Future<CommentActivityPage> loadCommentActivityPage(
  SupabaseClient supabase, {
  DateTime? before,
  int limit = kCommentActivityPageSize,
}) async {
  final myId = supabase.auth.currentUser?.id;
  if (myId == null) return CommentActivityPage(items: [], hasMore: false);

  final result = await _fetchRaw(
    supabase,
    myId: myId,
    since: DateTime.fromMillisecondsSinceEpoch(0),
    before: before,
    rowLimit: limit,
  );
  final items = await _resolveNames(supabase, result.raw);
  return CommentActivityPage(items: items, hasMore: result.hasMore);
}

/// Ідентифікатори коментарів, які юзер уже "переглянув" (відкривав день, де
/// вони є) — для стрічки, щоб позначити крапкою лише справді нові рядки.
Future<Set<String>> loadSeenCommentIds(SupabaseClient supabase) =>
    _loadSeenIds(supabase);

/// Легша перевірка для бейджа — той самий "не в множині переглянутих", але
/// без резолву імен авторів (зайвий запит до profiles заради булевого "є
/// щось нове") і обмежена останніми [kCommentActivityPageSize] подіями —
/// цього досить, щоб дізнатись "є щось нове", не скануючи всю історію.
Future<bool> hasUnseenCommentActivity(SupabaseClient supabase) async {
  final myId = supabase.auth.currentUser?.id;
  if (myId == null) return false;

  final results = await Future.wait([
    _fetchRaw(
      supabase,
      myId: myId,
      since: DateTime.fromMillisecondsSinceEpoch(0),
      rowLimit: kCommentActivityPageSize,
    ),
    _loadSeenIds(supabase),
  ]);
  final raw = (results[0] as _RawResult).raw;
  final seenIds = results[1] as Set<String>;
  return raw.any((r) => !seenIds.contains(r.commentId));
}

/// Позначає конкретні коментарі переглянутими — викликається, коли юзер
/// справді відкрив день з цими коментарями ([SingleEntryScreen]), не при
/// самому відкритті списку. Один день може мати кілька подій у стрічці
/// (наприклад два різні нові коментарі) — усі, що належать одному дню,
/// позначаються разом, бо відкривши тред юзер бачить їх усі одразу.
Future<void> markCommentsSeen(
  SupabaseClient supabase,
  Iterable<String> commentIds,
) async {
  final myId = supabase.auth.currentUser?.id;
  if (myId == null || commentIds.isEmpty) return;
  await supabase.from('comment_activity_seen').upsert([
    for (final id in commentIds) {'user_id': myId, 'comment_id': id},
  ]);
}

/// Позначає переглянутою ВСЮ стрічку одразу (кнопка "Позначити все
/// переглянутим") — не лише завантажену сторінку, а справді все, що коли-
/// небудь адресовано юзеру, тому [rowLimit] тут навмисно не заданий, на
/// відміну від [hasUnseenCommentActivity]. Аварійний вихід для юзера, якщо
/// крапка "нове" з якоїсь причини не зникає при звичайному перегляді дня.
Future<void> markAllCommentsSeen(SupabaseClient supabase) async {
  final myId = supabase.auth.currentUser?.id;
  if (myId == null) return;
  final result = await _fetchRaw(
    supabase,
    myId: myId,
    since: DateTime.fromMillisecondsSinceEpoch(0),
  );
  await markCommentsSeen(supabase, result.raw.map((r) => r.commentId));
}
