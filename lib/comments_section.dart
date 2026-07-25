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

/// Коментарі під конкретним чек-іном реальної людини — навмисно лише один
/// рівень: друг лишає (кореневий) коментар, автор дня може відповісти на
/// нього максимум один раз, і все. Необмежені треди пробували раніше —
/// вже з 2-3 рівнями вкладеності це нечитабельно на телефоні, тож модель
/// свідомо спрощена (і те саме гарантовано на рівні БД — унікальний індекс
/// на parent_id в checkin-comments-simplify-migration.sql).
///
/// [canComment] вирішує викликач: друг — лише якщо вже вгадав саме цей
/// день (той самий "спойлер"-принцип, що ховає настрій до вгадування).
/// [isOwner] — це екран власника дня чи друга: визначає, чи можна лишати
/// нові кореневі коментарі (тільки друг) чи тільки відповідати (тільки
/// власник).
///
/// [showWhenEmpty] — чи показувати секцію взагалі без жодного коментаря.
/// На чужому дні (друг щойно вгадав) це запрошення до розмови — доречно.
/// На власному щойно збереженому пості пропозиція відповісти нікому — ні,
/// тож там false: секція з'являється лише коли хтось інший уже щось написав.
class CommentsSection extends StatefulWidget {
  final String checkinId;
  final bool canComment;
  final bool isOwner;
  final bool showWhenEmpty;

  const CommentsSection({
    super.key,
    required this.checkinId,
    required this.canComment,
    required this.isOwner,
    this.showWhenEmpty = true,
  });

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  final _supabase = Supabase.instance.client;
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  bool _loading = true;
  List<CheckinComment> _comments = [];
  bool _sending = false;
  // Згорнуто за замовчуванням — інакше тред роздуває кожен запис у списку
  // днів. Кількість все одно вантажимо одразу, щоб показати "Коментарі (3)"
  // ще до розгортання.
  bool _expanded = false;
  // Поле вводу теж не висить відкритим за замовчуванням — з'являється лише
  // по тапу на "Додати коментар" (друг) чи "Відповісти" (власник), і
  // ховається назад після відправки.
  bool _composing = false;
  // Кому саме відповідає власник дня — null означає "друг пише кореневий
  // коментар", не використовується власником взагалі.
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
          .from('checkin_comments')
          .select(
            'id, checkin_id, author_id, parent_id, body, created_at, edited_at, deleted_at',
          )
          .eq('checkin_id', widget.checkinId)
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
          checkinId: row['checkin_id'] as String,
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
      await _supabase.from('checkin_comments').insert({
        'checkin_id': widget.checkinId,
        'author_id': _supabase.auth.currentUser!.id,
        'parent_id': widget.isOwner ? _replyToId : null,
        'body': body,
      });
      _inputController.clear();
      _closeCompose();
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

  void _startCompose({String? replyToId, String? replyToName}) {
    setState(() {
      _replyToId = replyToId;
      _replyToName = replyToName;
      _composing = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocusNode.requestFocus();
    });
  }

  void _closeCompose() {
    setState(() {
      _composing = false;
      _replyToId = null;
      _replyToName = null;
    });
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
          .from('checkin_comments')
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
          .from('checkin_comments')
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
    if (!_expanded && _visibleCount == 0) {
      // Немає ще жодного коментаря — одразу відкриваємо поле вводу, а не
      // змушуємо тапати двічі (спершу розгорнути, тоді ще раз "Додати
      // коментар" всередині).
      setState(() => _expanded = true);
      _startCompose();
    } else if (_expanded) {
      // Згортання шевроном — єдиний спосіб "закрити" секцію, і він же
      // відкидає незбережену чернетку (окрема "×" для цього була б
      // дублюючим елементом керування).
      setState(() {
        _expanded = false;
        _composing = false;
        _replyToId = null;
        _replyToName = null;
      });
    } else {
      setState(() => _expanded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canComment || _loading) return const SizedBox.shrink();
    if (_visibleCount == 0 && !widget.showWhenEmpty) {
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
          if (!widget.isOwner) ...[
            if (!_composing)
              GestureDetector(
                onTap: () => _startCompose(),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    l10n.addComment,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              )
            else
              _buildComposer(),
          ],
        ],
      ],
    );
  }

  Widget _buildThread(CheckinComment comment) {
    final reply = _replyFor(comment.id);
    final replying = widget.isOwner && _composing && _replyToId == comment.id;
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
            onReply: () => _startCompose(
              replyToId: comment.id,
              replyToName: comment.authorName ?? '',
            ),
          ),
          if (reply != null)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 10),
              child: _buildCommentRow(reply, showReply: false),
            ),
          if (replying)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 10),
              child: _buildComposer(),
            ),
        ],
      ),
    );
  }

  Widget _buildCommentRow(
    CheckinComment comment, {
    required bool showReply,
    VoidCallback? onReply,
  }) {
    final l10n = AppLocalizations.of(context);
    final isMine =
        comment.authorId == _supabase.auth.currentUser!.id &&
        !comment.isDeleted;

    return Column(
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
        if (showReply || isMine) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              if (showReply)
                GestureDetector(
                  onTap: onReply,
                  child: Text(
                    l10n.reply,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              if (isMine) ...[
                if (showReply) const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _editComment(comment),
                  child: Text(
                    l10n.edit,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _deleteComment(comment),
                  child: Text(
                    l10n.delete,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  // Спільний для обох сценаріїв (відповідь власника на конкретний коментар
  // і новий коментар друга) — щоб банер "Відповідаєш X" не дублювався у
  // двох місцях з ризиком розійтись. Закриття незбереженого чернетки —
  // лише через той самий шеврон вгорі секції (не окрема "×" поруч, яка
  // робила б те саме іншою іконкою).
  Widget _buildComposer() {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_replyToId != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                l10n.replyingTo(_replyToName ?? ''),
                style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
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
