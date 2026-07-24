import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'l10n/app_localizations.dart';
import 'style.dart';

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

/// Коментарі (з необмеженими тредами відповідей) під конкретним чек-іном
/// реальної людини. [canComment] вирішує викликач: власник дня — завжди,
/// друг — лише якщо вже вгадав саме цей день (той самий "спойлер"-принцип,
/// що ховає настрій до вгадування). Коли false, віджет узагалі нічого не
/// показує й не запитує — RLS і так заблокує читання, тут просто не
/// витрачаємо запит на порожній результат.
class CommentsSection extends StatefulWidget {
  final String checkinId;
  final bool canComment;

  const CommentsSection({
    super.key,
    required this.checkinId,
    required this.canComment,
  });

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  final _supabase = Supabase.instance.client;
  final _inputController = TextEditingController();
  bool _loading = true;
  List<CheckinComment> _comments = [];
  String? _replyToId;
  String? _replyToName;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    if (widget.canComment) _load();
  }

  @override
  void dispose() {
    _inputController.dispose();
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
          .order('created_at');

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
        'parent_id': _replyToId,
        'body': body,
      });
      _inputController.clear();
      _replyToId = null;
      _replyToName = null;
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

  void _startReply(CheckinComment comment) {
    setState(() {
      _replyToId = comment.id;
      _replyToName = comment.authorName ?? '';
    });
  }

  void _cancelReply() {
    setState(() {
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

  Map<String?, List<CheckinComment>> get _byParent {
    final map = <String?, List<CheckinComment>>{};
    for (final c in _comments) {
      map.putIfAbsent(c.parentId, () => []).add(c);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canComment) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final byParent = _byParent;
    final topLevel = byParent[null] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Divider(color: AppColors.divider, height: 1),
        const SizedBox(height: 12),
        ...topLevel.map((c) => _buildCommentTile(c, byParent, 0)),
        if (_replyToId != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.replyingTo(_replyToName ?? ''),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _cancelReply,
                  child: const Icon(
                    PhosphorIconsLight.x,
                    size: 14,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                minLines: 1,
                maxLines: 4,
                style: const TextStyle(fontSize: 14),
                decoration: appFieldDecoration(l10n.commentHint),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _sending ? null : _post,
              icon: const Icon(PhosphorIconsLight.paperPlaneRight),
              tooltip: l10n.postComment,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCommentTile(
    CheckinComment comment,
    Map<String?, List<CheckinComment>> byParent,
    int depth,
  ) {
    final l10n = AppLocalizations.of(context);
    final myId = _supabase.auth.currentUser!.id;
    final isMine = comment.authorId == myId && !comment.isDeleted;
    final replies = byParent[comment.id] ?? [];
    final indent = depth.clamp(0, 3) * 16.0;

    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                comment.authorName ?? '',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
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
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.inkMuted,
                  ),
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
              fontStyle: comment.isDeleted
                  ? FontStyle.italic
                  : FontStyle.normal,
            ),
          ),
          if (!comment.isDeleted) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                GestureDetector(
                  onTap: () => _startReply(comment),
                  child: Text(
                    l10n.reply,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.accent,
                    ),
                  ),
                ),
                if (isMine) ...[
                  const SizedBox(width: 12),
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
          ...replies.map((r) => _buildCommentTile(r, byParent, depth + 1)),
        ],
      ),
    );
  }
}
