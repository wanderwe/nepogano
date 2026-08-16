import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'daily_reminder.dart';
import 'date_labels.dart';
import 'l10n/app_localizations.dart';
import 'style.dart';

const _bodyMaxLength = 5000;

enum _LetterState { locked, unlockedUnread, opened }

class _FriendOption {
  final String id;
  final String name;

  _FriendOption({required this.id, required this.name});
}

/// Ті самі accepted-friendships, що й на екрані Друзів, тільки без усього
/// іншого (настрій, вгадування тощо) — тут потрібні лише id+ім'я для
/// вибору отримувача листа.
Future<List<_FriendOption>> _loadFriendOptions(SupabaseClient supabase) async {
  final myId = supabase.auth.currentUser!.id;
  final rows = await supabase
      .from('friendships')
      .select('requester_id, addressee_id')
      .or('requester_id.eq.$myId,addressee_id.eq.$myId')
      .eq('status', 'accepted');
  final friendIds = (rows as List)
      .map((r) => r['requester_id'] == myId ? r['addressee_id'] : r['requester_id'])
      .whereType<String>()
      .toSet()
      .toList();
  if (friendIds.isEmpty) return [];

  final profileRows = await supabase
      .from('profiles')
      .select('user_id, display_name')
      .inFilter('user_id', friendIds);
  return (profileRows as List)
      .map(
        (r) => _FriendOption(
          id: r['user_id'] as String,
          name: (r['display_name'] as String?) ?? '',
        ),
      )
      .toList();
}

class _Letter {
  final String id;
  final String authorId;
  final String? recipientId;
  final DateTime unlockAt;
  final DateTime? openedAt;
  // Присутнє, лише коли RLS дозволив прочитати future_letter_bodies —
  // тобто фактично коли лист уже розкрито. До того часу null навіть якщо
  // рядок технічно існує на сервері.
  final String? body;
  // Ім'я другої сторони (не мене) — null для листів собі. Проставляється
  // окремим batch-запитом до profiles після основного завантаження, бо
  // future_letters має дві FK на auth.users (author_id, recipient_id), і
  // PostgREST не embed'ить profiles автоматично через таку неоднозначність.
  final String? otherPartyName;

  _Letter({
    required this.id,
    required this.authorId,
    this.recipientId,
    required this.unlockAt,
    this.openedAt,
    this.body,
    this.otherPartyName,
  });

  _LetterState get state {
    if (DateTime.now().isBefore(unlockAt)) return _LetterState.locked;
    if (openedAt == null) return _LetterState.unlockedUnread;
    return _LetterState.opened;
  }
}

String _formatDate(DateTime date, BuildContext context) {
  final locale = Localizations.localeOf(context);
  return '${date.day} ${monthNameGenitive(date.month, locale)} ${date.year}';
}

String _letterLabel(_Letter letter, String myId, AppLocalizations l10n) {
  if (letter.recipientId == null) return l10n.timeCapsuleToSelfLabel;
  final name = letter.otherPartyName ?? '';
  return letter.authorId == myId
      ? l10n.timeCapsuleToFriendLabel(name)
      : l10n.timeCapsuleFromFriendLabel(name);
}

DateTime _addMonths(DateTime from, int months) {
  final totalMonths = from.month - 1 + months;
  final year = from.year + totalMonths ~/ 12;
  final month = totalMonths % 12 + 1;
  return DateTime(year, month, from.day, from.hour, from.minute, from.second);
}

class TimeCapsulesScreen extends StatefulWidget {
  const TimeCapsulesScreen({super.key});

  @override
  State<TimeCapsulesScreen> createState() => _TimeCapsulesScreenState();
}

class _TimeCapsulesScreenState extends State<TimeCapsulesScreen> {
  final _supabase = Supabase.instance.client;
  List<_Letter> _letters = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final myId = _supabase.auth.currentUser!.id;
      final rows = await _supabase
          .from('future_letters')
          .select(
            'id, author_id, recipient_id, unlock_at, opened_at, future_letter_bodies(body)',
          )
          .order('created_at', ascending: false);

      final otherPartyIds = <String>{};
      for (final row in rows as List) {
        final authorId = row['author_id'] as String;
        final recipientId = row['recipient_id'] as String?;
        final otherId = authorId == myId ? recipientId : authorId;
        if (otherId != null) otherPartyIds.add(otherId);
      }
      final nameById = <String, String>{};
      if (otherPartyIds.isNotEmpty) {
        final profileRows = await _supabase
            .from('profiles')
            .select('user_id, display_name')
            .inFilter('user_id', otherPartyIds.toList());
        for (final row in profileRows as List) {
          nameById[row['user_id'] as String] =
              (row['display_name'] as String?) ?? '';
        }
      }

      final letters = rows.map((row) {
        // letter_id — PK у future_letter_bodies, тобто зв'язок "один до
        // одного" з погляду future_letters, тож PostgREST embed'ить це як
        // об'єкт (Map), а не масив (List), як для звичайних to-many
        // зв'язків. Раніше тут стояв `as List?`, і поки лист був закритий
        // (RLS повертав null), каст мовчки проходив — а щойно RLS почав
        // реально повертати рядок, `null as List?` замінився на Map, каст
        // впав з рантайм-помилкою, яку ковтав catch навколо всього _load(),
        // і список тихо ставав порожнім.
        final bodyRow = row['future_letter_bodies'] as Map<String, dynamic>?;
        final openedAtRaw = row['opened_at'] as String?;
        final authorId = row['author_id'] as String;
        final recipientId = row['recipient_id'] as String?;
        final otherId = authorId == myId ? recipientId : authorId;
        return _Letter(
          id: row['id'] as String,
          authorId: authorId,
          recipientId: recipientId,
          unlockAt: DateTime.parse(row['unlock_at'] as String).toLocal(),
          openedAt: openedAtRaw != null
              ? DateTime.parse(openedAtRaw).toLocal()
              : null,
          body: bodyRow?['body'] as String?,
          otherPartyName: otherId != null ? nameById[otherId] : null,
        );
      }).toList();
      if (mounted) setState(() => _letters = letters);
    } catch (_) {
      // Список просто лишається таким, яким був — немає окремого
      // "щось пішло не так" стану для цього екрана, спробує ще раз при
      // наступному відкритті.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCompose() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ComposeLetterSheet(),
    );
    if (saved == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).timeCapsulesSealedConfirmation),
          ),
        );
      }
      _load();
    }
  }

  Future<void> _openLetter(_Letter letter) async {
    final l10n = AppLocalizations.of(context);
    if (letter.state == _LetterState.locked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.timeCapsulesStillLocked(_formatDate(letter.unlockAt, context)),
          ),
        ),
      );
      return;
    }

    if (letter.state == _LetterState.unlockedUnread) {
      await _supabase
          .from('future_letters')
          .update({'opened_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', letter.id);
    }

    if (!mounted) return;
    final title = _letterLabel(letter, _supabase.auth.currentUser!.id, l10n);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _LetterDetailScreen(title: title, body: letter.body ?? ''),
      ),
    );
    _load();
  }

  Future<void> _confirmDelete(_Letter letter) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: l10n.timeCapsulesDeleteConfirmTitle,
        content: Text(
          l10n.timeCapsulesDeleteConfirmBody,
          style: const TextStyle(color: AppColors.inkMuted),
        ),
        primaryLabel: l10n.no,
        onPrimary: () => Navigator.of(context).pop(false),
        secondaryLabel: l10n.yesDelete,
        secondaryColor: Colors.redAccent,
        onSecondary: () => Navigator.of(context).pop(true),
      ),
    );
    if (confirmed != true) return;
    await _supabase.from('future_letters').delete().eq('id', letter.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.timeCapsulesMenuLabel, style: appScreenTitle())),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _letters.isEmpty
          ? _EmptyState(onWrite: _openCompose)
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: _letters.length,
              itemBuilder: (context, index) {
                final letter = _letters[index];
                return _LetterRow(
                  letter: letter,
                  onTap: () => _openLetter(letter),
                  onLongPress: letter.state == _LetterState.locked
                      ? () => _confirmDelete(letter)
                      : null,
                );
              },
            ),
      floatingActionButton: _letters.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _openCompose,
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.accentInk,
              icon: const Icon(PhosphorIconsLight.envelopeSimple),
              label: Text(l10n.timeCapsulesWriteNew),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onWrite;

  const _EmptyState({required this.onWrite});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.timeCapsulesEmptyTitle,
              textAlign: TextAlign.center,
              style: appSerif(fontSize: 22),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.timeCapsulesEmptySubtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.inkMuted, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.accentInk,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                ),
                onPressed: onWrite,
                child: Text(l10n.timeCapsulesWriteFirst),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LetterRow extends StatelessWidget {
  final _Letter letter;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _LetterRow({required this.letter, required this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final IconData icon;
    final String status;
    switch (letter.state) {
      case _LetterState.locked:
        icon = PhosphorIconsLight.lockKey;
        status = l10n.timeCapsulesLockedUntil(_formatDate(letter.unlockAt, context));
        break;
      case _LetterState.unlockedUnread:
        icon = PhosphorIconsLight.envelopeSimpleOpen;
        status = l10n.timeCapsulesLockedUntil(_formatDate(letter.unlockAt, context));
        break;
      case _LetterState.opened:
        icon = PhosphorIconsLight.bookOpen;
        status = l10n.timeCapsulesOpenedOn(
          _formatDate(letter.openedAt ?? letter.unlockAt, context),
        );
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.inkMuted, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _letterLabel(
                        letter,
                        Supabase.instance.client.auth.currentUser!.id,
                        l10n,
                      ),
                      style: const TextStyle(color: AppColors.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(status, style: const TextStyle(color: AppColors.inkMuted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecipientPickResult {
  final String? id; // null = собі

  _RecipientPickResult(this.id);
}

/// Пошук + прокручуваний список замість ряду чіпів — той не масштабується,
/// якщо друзів десятки чи сотні. "Я" завжди першим рядком і не фільтрується
/// пошуком, той самий принцип, що чіп "Я" в перемикачі сутностей.
class _RecipientPickerSheet extends StatefulWidget {
  final List<_FriendOption> friends;
  final String? selectedId;

  const _RecipientPickerSheet({required this.friends, required this.selectedId});

  @override
  State<_RecipientPickerSheet> createState() => _RecipientPickerSheetState();
}

class _RecipientPickerSheetState extends State<_RecipientPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.friends
        : widget.friends
              .where((f) => f.name.toLowerCase().contains(query))
              .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: appFieldDecoration(l10n.search),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    if (query.isEmpty)
                      _RecipientRow(
                        label: l10n.me,
                        selected: widget.selectedId == null,
                        onTap: () =>
                            Navigator.of(context).pop(_RecipientPickResult(null)),
                      ),
                    ...filtered.map(
                      (friend) => _RecipientRow(
                        label: friend.name,
                        selected: widget.selectedId == friend.id,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(_RecipientPickResult(friend.id)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RecipientRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RecipientRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      title: Text(label, style: const TextStyle(color: AppColors.ink)),
      trailing: selected
          ? const Icon(PhosphorIconsLight.check, color: AppColors.accent, size: 18)
          : null,
    );
  }
}

class _ComposeLetterSheet extends StatefulWidget {
  const _ComposeLetterSheet();

  @override
  State<_ComposeLetterSheet> createState() => _ComposeLetterSheetState();
}

class _ComposeLetterSheetState extends State<_ComposeLetterSheet> {
  final _controller = TextEditingController();
  int _delayMonths = 1;
  bool _saving = false;
  List<_FriendOption> _friends = [];
  // null = собі (за замовчуванням).
  String? _recipientId;

  @override
  void initState() {
    super.initState();
    _loadFriendOptions(Supabase.instance.client).then((friends) {
      if (mounted) setState(() => _friends = friends);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _saving = true);
    try {
      final unlockAt = _addMonths(DateTime.now(), _delayMonths);
      final supabase = Supabase.instance.client;
      final myId = supabase.auth.currentUser!.id;
      final inserted = await supabase
          .from('future_letters')
          .insert({
            'author_id': myId,
            'recipient_id': _recipientId,
            'unlock_at': unlockAt.toUtc().toIso8601String(),
          })
          .select('id')
          .single();
      final letterId = inserted['id'] as String;
      await supabase.from('future_letter_bodies').insert({
        'letter_id': letterId,
        'body': text,
      });

      // Локальна нотифікація планується на ЦЬОМУ пристрої, тобто пристрої
      // автора. Для листа другові це не розбудить телефон отримувача —
      // локальні нотифікації не можуть розбудити ЧУЖИЙ пристрій, для цього
      // потрібен справжній server-side push (окремий проєкт, свідомо не
      // робимо зараз). Автор все одно отримає нагадування собі (і сам
      // теж відновлює доступ до листа з дати розкриття), а отримувач
      // побачить лист лише коли сам відкриє застосунок після цієї дати.
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        await scheduleLetterUnlockNotification(
          letterId: letterId,
          unlockAt: unlockAt,
          title: l10n.timeCapsulesMenuLabel,
          body: l10n.timeCapsulesBannerReady,
        );
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).somethingWentWrong)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              maxLines: 8,
              minLines: 5,
              maxLength: _bodyMaxLength,
              decoration: appFieldDecoration(l10n.timeCapsulesComposeHint),
            ),
            // Тільки якщо є хоч один друг — інакше вибір завжди однаковий
            // (лише "Я") і не додає нічого, крім зайвого рядка. Окремий
            // піквер із пошуком замість ряду чіпів — той не масштабується,
            // якщо в юзера десятки чи сотні друзів (стіна плиток замість
            // списку).
            if (_friends.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(l10n.timeCapsulesRecipientLabel, style: const TextStyle(color: AppColors.inkMuted, fontSize: 12)),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () async {
                  final picked = await showModalBottomSheet<_RecipientPickResult>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => _RecipientPickerSheet(
                      friends: _friends,
                      selectedId: _recipientId,
                    ),
                  );
                  if (picked != null) setState(() => _recipientId = picked.id);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _recipientId == null
                              ? l10n.me
                              : _friends
                                    .firstWhere((f) => f.id == _recipientId)
                                    .name,
                          style: const TextStyle(color: AppColors.ink),
                        ),
                      ),
                      const Icon(
                        PhosphorIconsLight.caretDown,
                        size: 16,
                        color: AppColors.inkMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                AppChip(
                  label: l10n.timeCapsulesDelayMonth,
                  selected: _delayMonths == 1,
                  onTap: () => setState(() => _delayMonths = 1),
                ),
                AppChip(
                  label: l10n.timeCapsulesDelayHalfYear,
                  selected: _delayMonths == 6,
                  onTap: () => setState(() => _delayMonths = 6),
                ),
                AppChip(
                  label: l10n.timeCapsulesDelayYear,
                  selected: _delayMonths == 12,
                  onTap: () => setState(() => _delayMonths = 12),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.accentInk,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentInk),
                      )
                    : Text(l10n.timeCapsulesSeal),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LetterDetailScreen extends StatelessWidget {
  final String title;
  final String body;

  const _LetterDetailScreen({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, style: appScreenTitle())),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Text(
          body,
          style: const TextStyle(color: AppColors.ink, fontSize: 16, height: 1.5),
        ),
      ),
    );
  }
}
