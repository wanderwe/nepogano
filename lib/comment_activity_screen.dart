import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'comment_activity.dart';
import 'comments_section.dart';
import 'history_screen.dart';
import 'l10n/app_localizations.dart';
import 'main.dart';
import 'photo_storage.dart';
import 'style.dart';

String _relativeDay(DateTime dateTime, AppLocalizations l10n) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dateTime.year, dateTime.month, dateTime.day);
  final diff = today.difference(day).inDays;

  if (diff == 0) return l10n.today;
  if (diff == 1) return l10n.yesterday;
  return '${dateTime.day}.${dateTime.month}';
}

/// Єдина стрічка подій "хтось написав тобі в коментарях" — і нові
/// коментарі під власними днями, і відповіді на власні коментарі під
/// чужими, в одному хронологічному списку. Тап веде напряму на той самий
/// день ([SingleEntryScreen]), без пошуку по чужих списках/пагінації.
class CommentActivityScreen extends StatefulWidget {
  const CommentActivityScreen({super.key});

  @override
  State<CommentActivityScreen> createState() => _CommentActivityScreenState();
}

class _CommentActivityScreenState extends State<CommentActivityScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  bool _loadingMore = false;
  bool _error = false;
  bool _hasMore = false;
  List<CommentActivityItem> _items = [];
  // Які саме коментарі юзер уже відкривав — на відміну від єдиної мітки
  // часу "останній перегляд списку", тут можна коректно позначити рівно
  // той запис, у який справді заходили, не чіпаючи решту. Оновлюється й
  // локально одразу після повернення з SingleEntryScreen (щоб крапка
  // зникла без повторного запиту), і незалежно перечитується при
  // наступному відкритті цього екрана.
  Set<String> _seenIds = {};
  bool _markingAllRead = false;

  bool get _hasUnseen =>
      _items.any((item) => !_seenIds.contains(item.commentId));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _markAllRead() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _markingAllRead = true);
    try {
      await markAllCommentsSeen(_supabase);
      if (!mounted) return;
      setState(() {
        _seenIds = {..._seenIds, ..._items.map((i) => i.commentId)};
        _markingAllRead = false;
      });
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.commentActivityMarkedAllRead)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _markingAllRead = false);
      messenger.showSnackBar(SnackBar(content: Text(l10n.somethingWentWrong)));
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final results = await Future.wait([
        loadCommentActivityPage(_supabase),
        loadSeenCommentIds(_supabase),
      ]);
      if (!mounted) return;
      final page = results[0] as CommentActivityPage;
      setState(() {
        _items = page.items;
        _hasMore = page.hasMore;
        _seenIds = results[1] as Set<String>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_items.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await loadCommentActivityPage(
        _supabase,
        before: _items.last.createdAt,
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(PhosphorIconsLight.arrowLeft, size: 20),
                    tooltip: l10n.back,
                  ),
                  const SizedBox(width: 4),
                  Text(l10n.commentsLabel, style: appScreenTitle()),
                  const Spacer(),
                  if (!_loading && _hasUnseen)
                    IconButton(
                      onPressed: _markingAllRead ? null : _markAllRead,
                      tooltip: l10n.commentActivityMarkAllRead,
                      icon: _markingAllRead
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(PhosphorIconsLight.checks, size: 20),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error)
                Expanded(
                  child: Center(
                    child: Text(
                      l10n.couldNotLoadComments,
                      style: const TextStyle(color: AppColors.inkMuted),
                    ),
                  ),
                )
              else if (_items.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      l10n.commentActivityEmpty,
                      style: const TextStyle(color: AppColors.inkMuted),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    children: [
                      for (final item in _items) ...[
                        _buildRow(item),
                        const SizedBox(height: 10),
                      ],
                      if (_hasMore)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: _loadingMore
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : TextButton(
                                    onPressed: _loadMore,
                                    child: Text(l10n.showMore),
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(CommentActivityItem item) {
    final l10n = AppLocalizations.of(context);
    final title = item.isReply
        ? l10n.commentActivityReply(item.authorName)
        : l10n.commentActivityNewComment(item.authorName);
    final isNew = !_seenIds.contains(item.commentId);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        // Один день міг зібрати кілька окремих подій у стрічці (два різні
        // нові коментарі того самого дня) — відкривши тред, юзер бачить їх
        // усі одразу, тож усі й позначаються переглянутими разом, не лише
        // та, на яку тапнули.
        final relatedIds = _items
            .where((i) => i.checkinId == item.checkinId)
            .map((i) => i.commentId)
            .toList();
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SingleEntryScreen(
              checkinId: item.checkinId,
              subjectId: item.subjectId,
              isSubject: item.isSubject,
              isOwnPost: item.isOwnPost,
              relatedCommentIds: relatedIds,
            ),
          ),
        );
        if (mounted) setState(() => _seenIds = {..._seenIds, ...relatedIds});
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            if (isNew) ...[
              const DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.notification,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(width: 8, height: 8),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _relativeDay(item.createdAt, l10n),
              style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Один конкретний день (особистий чи сутності) поза звичним списком —
/// відкривається напряму по checkinId, без гортання ані власної Історії,
/// ані пагінованого списку в друга. Тред коментарів одразу розгорнутий:
/// на цей екран приходять саме заради нього.
class SingleEntryScreen extends StatefulWidget {
  final String checkinId;
  final String? subjectId;
  final bool isSubject;
  final bool isOwnPost;
  // Коментарі зі стрічки "Коментарі", що ведуть на цей самий день —
  // позначаються переглянутими одразу, як тільки юзер справді відкрив тред,
  // не раніше. Порожній список — нормально (екран міг би відкриватись і
  // не зі стрічки активності, якщо колись з'явиться інший вхід).
  final List<String> relatedCommentIds;

  const SingleEntryScreen({
    super.key,
    required this.checkinId,
    required this.subjectId,
    required this.isSubject,
    required this.isOwnPost,
    this.relatedCommentIds = const [],
  });

  @override
  State<SingleEntryScreen> createState() => _SingleEntryScreenState();
}

class _SingleEntryScreenState extends State<SingleEntryScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  bool _error = false;
  CheckinEntry? _entry;
  String? _ownerName;

  String get _table => widget.isSubject ? 'subject_checkins' : 'checkins';

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.relatedCommentIds.isNotEmpty) {
      markCommentsSeen(_supabase, widget.relatedCommentIds);
    }
  }

  Future<void> _load() async {
    try {
      final myId = _supabase.auth.currentUser!.id;
      final columns =
          'id, mood, note, created_at, photo_path, photo_align_y, photo_scale, update_count'
          '${widget.isSubject ? ', author_id' : ', user_id'}';
      final row = await _supabase
          .from(_table)
          .select(columns)
          .eq('id', widget.checkinId)
          .single();

      String? ownerName;
      if (!widget.isOwnPost) {
        if (widget.isSubject) {
          // Не мій щоденник сутності (я лише допущений глядач/коментатор) —
          // підписуємо назвою самої сутності, а не автором конкретного дня,
          // це і є "чий це щоденник" у контексті картки.
          final subjectRow = await _supabase
              .from('subjects')
              .select('name')
              .eq('id', widget.subjectId!)
              .maybeSingle();
          ownerName = subjectRow?['name'] as String?;
        } else {
          final ownerId = row['user_id'] as String?;
          if (ownerId != null && ownerId != myId) {
            final profileRow = await _supabase
                .from('profiles')
                .select('display_name')
                .eq('user_id', ownerId)
                .maybeSingle();
            ownerName = profileRow?['display_name'] as String?;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _entry = CheckinEntry(
          id: row['id'] as String,
          createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
          mood: moodFromDbValue(row['mood'] as String),
          note: row['note'] as String?,
          photoPath: row['photo_path'] as String?,
          photoAlignY: (row['photo_align_y'] as num?)?.toDouble() ?? 0,
          photoScale: (row['photo_scale'] as num?)?.toDouble() ?? 1,
          updateCount: (row['update_count'] as num?)?.toInt() ?? 0,
        );
        _ownerName = ownerName;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(PhosphorIconsLight.arrowLeft, size: 20),
                    tooltip: l10n.back,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _entry == null
                        ? l10n.commentsLabel
                        : _relativeDay(_entry!.createdAt, l10n),
                    style: appScreenTitle(),
                  ),
                ],
              ),
              if (_ownerName != null) ...[
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: Text(
                    _ownerName!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error || _entry == null)
                Expanded(
                  child: Center(
                    child: Text(
                      l10n.couldNotLoadComments,
                      style: const TextStyle(color: AppColors.inkMuted),
                    ),
                  ),
                )
              else
                Expanded(child: _buildEntry(_entry!)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntry(CheckinEntry entry) {
    final l10n = AppLocalizations.of(context);
    final noteText = entry.note?.trim();
    final hasNote = noteText != null && noteText.isNotEmpty;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: entry.mood.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                entry.mood.label(context),
                style: const TextStyle(fontSize: 15),
              ),
            ],
          ),
          if (hasNote) ...[
            const SizedBox(height: 10),
            Text(
              noteText,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.ink,
                height: 1.4,
              ),
            ),
          ],
          if (entry.photoPath != null) ...[
            const SizedBox(height: 12),
            FutureBuilder<Uint8List?>(
              future: downloadCheckinPhoto(entry.photoPath!),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const AspectRatio(
                    aspectRatio: kCompactPhotoAspectRatio,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: kCompactPhotoAspectRatio,
                    child: ScaledPhoto(
                      scale: entry.photoScale,
                      child: Image.memory(
                        snapshot.data!,
                        fit: BoxFit.cover,
                        alignment: Alignment(0, entry.photoAlignY),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 16),
          Text(
            entry.updateCount > 0 ? l10n.updatedCount(entry.updateCount) : '',
            style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 8),
          CommentsSection(
            checkinId: entry.id,
            canComment: true,
            isOwner: widget.isOwnPost,
            isSubject: widget.isSubject,
            initiallyExpanded: true,
          ),
        ],
      ),
    );
  }
}
