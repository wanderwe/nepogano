import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'l10n/app_localizations.dart';
import 'style.dart';

const _commentsLastSeenKey = 'comments_last_seen';

/// Чи є коментар на МОЇХ днях, новіший за останній перегляд власної Історії
/// (локальна мітка часу в SharedPreferences — без окремої таблиці "read
/// receipts"). Власні відповіді (author_id = я) не рахуються — це не "нове
/// повідомлення від когось", хоч і лежать у тій самій таблиці.
Future<bool> hasUnseenComments(SupabaseClient supabase) async {
  final myId = supabase.auth.currentUser?.id;
  if (myId == null) return false;

  final myCheckinRows = await supabase
      .from('checkins')
      .select('id')
      .eq('user_id', myId);
  final myCheckinIds = (myCheckinRows as List)
      .map((r) => r['id'] as String)
      .toList();
  if (myCheckinIds.isEmpty) return false;

  final prefs = await SharedPreferences.getInstance();
  final lastSeenIso = prefs.getString(_commentsLastSeenKey);
  final since = lastSeenIso != null
      ? DateTime.parse(lastSeenIso)
      : DateTime.fromMillisecondsSinceEpoch(0);

  final commentRows = await supabase
      .from('checkin_comments')
      .select('id')
      .inFilter('checkin_id', myCheckinIds)
      .neq('author_id', myId)
      .gt('created_at', since.toUtc().toIso8601String())
      .limit(1);

  return (commentRows as List).isNotEmpty;
}

/// Той самий "новий коментар" запит, що [hasUnseenComments], але повертає
/// **які саме** дні (checkin_id) мають непереглянутий коментар — щоб
/// підсвітити конкретні дні на календарі, а не лише показати загальну
/// крапку "є щось нове" на іконці.
Future<Set<String>> unseenCommentCheckinIds(
  SupabaseClient supabase,
  List<String> checkinIds,
) async {
  final myId = supabase.auth.currentUser?.id;
  if (myId == null || checkinIds.isEmpty) return {};

  final prefs = await SharedPreferences.getInstance();
  final lastSeenIso = prefs.getString(_commentsLastSeenKey);
  final since = lastSeenIso != null
      ? DateTime.parse(lastSeenIso)
      : DateTime.fromMillisecondsSinceEpoch(0);

  final commentRows = await supabase
      .from('checkin_comments')
      .select('checkin_id')
      .inFilter('checkin_id', checkinIds)
      .neq('author_id', myId)
      .gt('created_at', since.toUtc().toIso8601String());

  return (commentRows as List).map((r) => r['checkin_id'] as String).toSet();
}

/// Позначає всі поточні коментарі як переглянуті — викликати, коли юзер
/// відкрив власну Історію (не чужу сутність), де коментарі й видно.
Future<void> markCommentsSeen() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _commentsLastSeenKey,
    DateTime.now().toUtc().toIso8601String(),
  );
}

class CheckinComment {
  final String id;
  final String checkinId;
  final String authorId;
  final String? authorName;
  final String? parentId;
  final String body;
  final DateTime createdAt;
  final DateTime? editedAt;
  final bool isDeleted;

  CheckinComment({
    required this.id,
    required this.checkinId,
    required this.authorId,
    required this.authorName,
    required this.parentId,
    required this.body,
    required this.createdAt,
    required this.editedAt,
    required this.isDeleted,
  });
}

/// Коментарі під конкретним чек-іном — навмисно лише один рівень вкладеності
/// (корінь + максимум одна відповідь на нього, і все). Необмежені треди
/// пробували раніше — вже з 2-3 рівнями вкладеності це нечитабельно на
/// телефоні, тож модель свідомо спрощена (і те саме гарантовано на рівні
/// БД — унікальний індекс на parent_id, checkin-comments-simplify-migration.sql
/// / subject-guessing-comments-migration.sql).
///
/// [canComment] вирішує викликач: друг/учасник кола — лише якщо вже вгадав
/// саме цей день (той самий "спойлер"-принцип, що ховає настрій до
/// вгадування). Власник дня (і співавтор сутності) — завжди.
///
/// [isOwner] — це екран власника дня чи глядача. Симетрично для обох
/// таблиць (checkin-comments-owner-root-migration.sql /
/// subject-comments-owner-root-migration.sql): будь-хто, кому canComment,
/// може лишити і кореневий коментар, і відповідь — раніше власник міг лише
/// відповідати, але виявилось незручно навіть на власному дні (запізніле
/// уточнення до вже збереженого запису), не тільки на сутності. [isOwner]
/// далі впливає лише на те, кому доступна кнопка "Відповісти" під чужим
/// кореневим коментарем (лише власнику/співавтору, не глядачу).
///
/// [showWhenEmpty] — чи показувати секцію взагалі без жодного коментаря.
/// Глядач (друг/учасник кола) завжди бачить — це запрошення до розмови.
/// Власник за замовчуванням не бачить порожню секцію (`showWhenEmpty:
/// false` від викликача) — АЛЕ `_effectiveShowWhenEmpty` це перекриває:
/// раз власник теж може лишити перший коментар, ховати єдину точку входу
/// до цього безглуздо.
class CommentsSection extends StatefulWidget {
  final String checkinId;
  final bool canComment;
  final bool isOwner;
  final bool showWhenEmpty;
  // Той самий віджет обслуговує і checkin_comments (реальні люди), і
  // subject_checkin_comments (сутності) — моделі й UI ідентичні, різниться
  // лише таблиця й назва FK-колонки, тож не дублюємо весь файл.
  final bool isSubject;

  const CommentsSection({
    super.key,
    required this.checkinId,
    required this.canComment,
    required this.isOwner,
    this.showWhenEmpty = true,
    this.isSubject = false,
  });

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  final _supabase = Supabase.instance.client;
  String get _table =>
      widget.isSubject ? 'subject_checkin_comments' : 'checkin_comments';
  String get _idColumn =>
      widget.isSubject ? 'subject_checkin_id' : 'checkin_id';
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  bool _loading = true;
  List<CheckinComment> _comments = [];
  bool _sending = false;
  // Згорнуто за замовчуванням — інакше тред роздуває кожен запис у списку
  // днів. Кількість все одно вантажимо одразу, щоб показати "Коментарі (3)"
  // ще до розгортання.
  bool _expanded = false;
  // Ціль поточної відповіді — null означає "пишу новий кореневий коментар".
  // Раніше поле вводу ще й ховалось окремим прапорцем _composing, поки не
  // тапнеш "Додати коментар"/"Відповісти" — це давало два джерела правди
  // (чи видно поле, і кому воно адресовано) і плутало, коли розходились.
  // Тепер поле завжди видно, щойно секція розгорнута — саме поле не
  // фокусується (клавіатура не вилазить), поки не тапнути в нього, тож
  // просто перегляд коментарів так само не інтрузивний.
  String? _replyToId;
  String? _replyToName;

  @override
  void initState() {
    super.initState();
    if (widget.canComment) _load();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _supabase
          .from(_table)
          .select(
            'id, $_idColumn, author_id, parent_id, body, created_at, edited_at, deleted_at',
          )
          .eq(_idColumn, widget.checkinId)
          // За замовчуванням .order() у Supabase сортує ascending: false
          // (новіші перші) — без явного true коментарі йшли у зворотному,
          // заплутаному порядку.
          .order('created_at', ascending: true);

      final authorIds = (rows as List)
          .map((r) => r['author_id'] as String)
          .toSet()
          .toList();
      final nameById = <String, String?>{};
      if (authorIds.isNotEmpty) {
        final profileRows = await _supabase
            .from('profiles')
            .select('user_id, display_name')
            .inFilter('user_id', authorIds);
        for (final row in profileRows as List) {
          nameById[row['user_id'] as String] = row['display_name'] as String?;
        }
      }

      final comments = rows.map((row) {
        return CheckinComment(
          id: row['id'] as String,
          checkinId: row[_idColumn] as String,
          authorId: row['author_id'] as String,
          authorName: nameById[row['author_id'] as String],
          parentId: row['parent_id'] as String?,
          body: row['body'] as String,
          createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
          editedAt: row['edited_at'] == null
              ? null
              : DateTime.parse(row['edited_at'] as String).toLocal(),
          isDeleted: row['deleted_at'] != null,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _comments = comments;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).couldNotLoadComments),
          ),
        );
      }
    }
  }

  Future<void> _post() async {
    final body = _inputController.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _supabase.from(_table).insert({
        _idColumn: widget.checkinId,
        'author_id': _supabase.auth.currentUser!.id,
        'parent_id': widget.isOwner ? _replyToId : null,
        'body': body,
      });
      _inputController.clear();
      _clearReplyTarget();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).couldNotPostComment),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _setReplyTarget(String replyToId, String replyToName) {
    setState(() {
      _replyToId = replyToId;
      _replyToName = replyToName;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocusNode.requestFocus();
    });
  }

  // Повертає поле вводу в режим нового кореневого коментаря — після
  // відправки, і так само по "×" біля банера "Відповідаєш X" (сам компоузер
  // при цьому лишається відкритим, не закривається).
  void _clearReplyTarget() {
    setState(() {
      _replyToId = null;
      _replyToName = null;
    });
  }

  Future<void> _openCommentMenu(CheckinComment comment) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => Navigator.of(context).pop('edit'),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        PhosphorIconsLight.pencilSimple,
                        size: 20,
                        color: AppColors.ink,
                      ),
                      const SizedBox(width: 16),
                      Text(l10n.edit, style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: () => Navigator.of(context).pop('delete'),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        PhosphorIconsLight.trash,
                        size: 20,
                        color: Colors.redAccent,
                      ),
                      const SizedBox(width: 16),
                      Text(
                        l10n.delete,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == 'edit') {
      await _editComment(comment);
    } else if (choice == 'delete') {
      await _deleteComment(comment);
    }
  }

  Future<void> _editComment(CheckinComment comment) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: comment.body);
    final newBody = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AppDialog(
          title: l10n.edit,
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: appFieldDecoration(l10n.commentHint),
            onChanged: (_) => setState(() {}),
          ),
          primaryLabel: l10n.save,
          onPrimary: controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(controller.text.trim()),
          secondaryLabel: l10n.cancel,
          onSecondary: () => Navigator.of(context).pop(),
        ),
      ),
    );

    if (newBody == null || newBody.isEmpty || newBody == comment.body) return;

    try {
      await _supabase
          .from(_table)
          .update({
            'body': newBody,
            'edited_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', comment.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).couldNotEditComment),
          ),
        );
      }
    }
  }

  Future<void> _deleteComment(CheckinComment comment) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: l10n.deleteCommentConfirmTitle,
        content: Text(
          l10n.deleteCommentConfirmBody,
          style: const TextStyle(color: AppColors.inkMuted),
        ),
        primaryLabel: l10n.cancel,
        onPrimary: () => Navigator.of(context).pop(false),
        secondaryLabel: l10n.delete,
        secondaryColor: Colors.redAccent,
        onSecondary: () => Navigator.of(context).pop(true),
      ),
    );
    if (confirmed != true) return;

    try {
      await _supabase
          .from(_table)
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', comment.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).couldNotDeleteComment),
          ),
        );
      }
    }
  }

  String _timeLabel(DateTime dt) {
    final now = DateTime.now();
    final sameDay =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (sameDay) return '$hh:$mm';
    return '${dt.day}.${dt.month} $hh:$mm';
  }

  List<CheckinComment> get _topLevel =>
      _comments.where((c) => c.parentId == null).toList();

  CheckinComment? _replyFor(String topLevelId) {
    for (final c in _comments) {
      if (c.parentId == topLevelId) return c;
    }
    return null;
  }

  // Рахуємо лише те, що реально рендериться (корінь + пряма відповідь на
  // нього) — а не всі рядки в базі. Стара модель дозволяла необмежену
  // глибину, тож у тестових даних могли лишитись відповіді-на-відповідь,
  // яких нова модель просто не показує; без цього лічильник розходився б
  // із тим, що видно на екрані.
  int get _visibleCount {
    final roots = _topLevel;
    var count = roots.length;
    for (final r in roots) {
      if (_replyFor(r.id) != null) count++;
    }
    return count;
  }

  void _handleToggleTap() {
    if (_expanded) {
      // Знімаємо фокус ЯВНО, до того, як поле вводу зникне з дерева разом
      // із секцією. Без цього Flutter, побачивши, що досі сфокусоване поле
      // от-от буде видалено, сам переносив фокус (а з ним і клавіатуру, і
      // автоскрол "покажи сфокусоване поле") на найближче ІНШЕ текстове
      // поле, яке ще лишилось на екрані — часто чужого запису вище чи нижче.
      _inputFocusNode.unfocus();
      // Згортання шевроном — єдиний спосіб "закрити" секцію, і він же
      // відкидає незбережену ціль відповіді (окрема "×" для цього була б
      // дублюючим елементом керування — вона вже є, але лише для самої
      // цілі відповіді, не для згортання).
      setState(() {
        _expanded = false;
        _replyToId = null;
        _replyToName = null;
      });
      return;
    }
    setState(() => _expanded = true);
    if (_visibleCount == 0) {
      // Немає ще жодного коментаря — одразу фокусуємось у полі, а не
      // змушуємо ще раз тапати саме поле, яке й так уже видно.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocusNode.requestFocus();
      });
    }
  }

  // Спершу власник дня міг лише відповідати, друг — лише лишити корінь.
  // Тепер обидві таблиці (реальні люди й сутності) симетричні: будь-хто,
  // кому взагалі можна коментувати ([canComment]), може лишити і корінь, і
  // відповідь — той самий SQL-дозвіл, що вже є для сутностей
  // (checkin-comments-owner-root-migration.sql, дзеркалить
  // subject-comments-owner-root-migration.sql).
  //
  // Секцію більше не можна ховати, поки коментарів немає, якщо дивиться
  // власник — тепер і йому є що почати самому (call site і далі передає
  // showWhenEmpty: false за замовчуванням, тут це перекривається).
  bool get _effectiveShowWhenEmpty => widget.showWhenEmpty || widget.isOwner;

  @override
  Widget build(BuildContext context) {
    if (!widget.canComment || _loading) return const SizedBox.shrink();
    if (_visibleCount == 0 && !_effectiveShowWhenEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final topLevel = _topLevel;
    final visibleCount = _visibleCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Divider(color: AppColors.divider, height: 1),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _handleToggleTap,
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              Icon(
                PhosphorIconsLight.chatCircle,
                size: 14,
                color: AppColors.inkMuted,
              ),
              const SizedBox(width: 6),
              Text(
                // Один і той самий напис завжди — розкриття/згортання ("чи є
                // тут коментарі") і сам заклик "додати" це різні речі: перше
                // не повинно міняти назву залежно від стану.
                visibleCount > 0
                    ? l10n.commentsCount(visibleCount)
                    : l10n.commentsLabel,
                style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
              ),
              const Spacer(),
              Icon(
                _expanded
                    ? PhosphorIconsLight.caretUp
                    : PhosphorIconsLight.caretDown,
                size: 14,
                color: AppColors.inkMuted,
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 10),
          ...topLevel.map((c) => _buildThread(c)),
          // Єдине місце в усій секції, де рендериться поле вводу — і для
          // нового кореневого коментаря, і для відповіді (яку саме визначає
          // [_replyToId], видно з банера "Відповідаєш X" усередині
          // _buildComposer). Завжди видно, щойно секція розгорнута — не
          // ховається за окремим тапом "Додати коментар": поле саме по собі
          // не фокусується, поки в нього не тапнути, тож перегляд без наміру
          // писати лишається таким самим не інтрузивним.
          _buildComposer(),
        ],
      ],
    );
  }

  Widget _buildThread(CheckinComment comment) {
    final reply = _replyFor(comment.id);
    final replying = _replyToId == comment.id;
    final canReply =
        widget.isOwner &&
        !comment.isDeleted &&
        reply == null &&
        comment.authorId != _supabase.auth.currentUser!.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCommentRow(
            comment,
            showReply: canReply && !replying,
            highlighted: replying,
            onReply: () =>
                _setReplyTarget(comment.id, comment.authorName ?? ''),
          ),
          if (reply != null)
            _buildNested(_buildCommentRow(reply, showReply: false)),
        ],
      ),
    );
  }

  // Візуальний зв'язок "до чого відноситься" відповідь — вертикальна лінія
  // зліва, той самий патерн, що тред-гайди в Slack/Reddit, а не просто
  // відступ (з ним на око губилось, чия саме це відповідь, коли коментарів
  // під днем декілька підряд).
  Widget _buildNested(Widget child) {
    return Container(
      margin: const EdgeInsets.only(left: 10, top: 10),
      padding: const EdgeInsets.only(left: 12),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.divider, width: 2)),
      ),
      child: child,
    );
  }

  Widget _buildCommentRow(
    CheckinComment comment, {
    required bool showReply,
    bool highlighted = false,
    VoidCallback? onReply,
  }) {
    final l10n = AppLocalizations.of(context);
    final isMine =
        comment.authorId == _supabase.auth.currentUser!.id &&
        !comment.isDeleted;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              comment.authorName ?? '',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            Text(
              _timeLabel(comment.createdAt),
              style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
            ),
            if (comment.editedAt != null && !comment.isDeleted) ...[
              const SizedBox(width: 4),
              Text(
                l10n.editedLabel,
                style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          comment.isDeleted ? l10n.commentDeleted : comment.body,
          style: TextStyle(
            fontSize: 14,
            color: comment.isDeleted ? AppColors.inkMuted : AppColors.ink,
            fontStyle: comment.isDeleted ? FontStyle.italic : FontStyle.normal,
          ),
        ),
        if (showReply) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: onReply,
            child: Text(
              l10n.reply,
              style: const TextStyle(fontSize: 12, color: AppColors.accent),
            ),
          ),
        ],
      ],
    );

    // Підсвітка — щоб було однозначно видно, ДО ЯКОГО коментаря відноситься
    // банер "Відповідаєш X" унизу, а не лише читати ім'я в банері.
    final wrapped = highlighted
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            margin: const EdgeInsets.symmetric(vertical: -6, horizontal: -8),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: content,
          )
        : content;

    if (!isMine) return wrapped;
    // Довге натискання на весь коментар відкриває те саме меню, що й "⋯" —
    // той самий патерн, що вже скрізь у застосунку для власних елементів
    // списку (щоденники, кола): тап виконує основну дію, довге натискання
    // відкриває керування. У коментаря основної дії на тап нема, тож весь
    // рядок можна віддати під довге натискання, а не тільки малу іконку.
    return GestureDetector(
      onLongPress: () => _openCommentMenu(comment),
      behavior: HitTestBehavior.opaque,
      child: wrapped,
    );
  }

  // Єдиний композер на всю секцію — і для нового кореневого коментаря, і
  // для відповіді. Банер над полем — завжди, в обох режимах: якщо показувати
  // його лише під час відповіді, то поле в звичайному стані нічим не
  // підказує, що звичайний ввід — це НЕ продовження щойно прочитаного
  // коментаря вище (виглядало, ніби пишеш у відповідь на нього). "×" у
  // банері відповіді знімає лише ціль відповіді (назад у кореневий режим),
  // не закриває поле вводу; повне закриття/скасування чернетки лишається
  // за шевроном угорі секції.
  Widget _buildComposer() {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _replyToId == null
                ? Text(
                    l10n.addComment,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inkMuted,
                    ),
                  )
                : Row(
                    children: [
                      Text(
                        l10n.replyingTo(_replyToName ?? ''),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.inkMuted,
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: _clearReplyTarget,
                        behavior: HitTestBehavior.opaque,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            PhosphorIconsLight.x,
                            size: 12,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          _buildInputField(),
        ],
      ),
    );
  }

  Widget _buildInputField() {
    final l10n = AppLocalizations.of(context);
    return TextField(
      controller: _inputController,
      focusNode: _inputFocusNode,
      minLines: 1,
      maxLines: 4,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => _sending ? null : _post(),
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: l10n.commentHint,
        // Без цього підказка (не сам текст, а саме hint) переносилась на 2
        // рядки на вузьких полях (відповідь під тредом-гайдом лінією зліва
        // забирає ще трохи ширини) — і порожнє поле виглядало вдвічі вищим,
        // ніж мало бути, поки нічого не написано.
        hintMaxLines: 1,
        hintStyle: const TextStyle(fontSize: 14, color: AppColors.inkMuted),
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        suffixIcon: _sending
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                onPressed: _post,
                icon: const Icon(PhosphorIconsLight.paperPlaneRight),
                tooltip: l10n.postComment,
              ),
      ),
    );
  }
}
