import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'date_labels.dart';
import 'l10n/app_localizations.dart';
import 'style.dart';

const _bodyMaxLength = 5000;

/// Список раніше вантажив УСІ листи одним запитом без жодного ліміту,
/// незалежно від того, чи їх 4, чи 400. 10, не 20 (як стрічка "Коментарі"),
/// бо картки листів тут значно більші — 20 за раз давало занадто довгий
/// перший скрол.
const _lettersPageSize = 10;

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
      .map(
        (r) =>
            r['requester_id'] == myId ? r['addressee_id'] : r['requester_id'],
      )
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
  final DateTime createdAt;
  final DateTime unlockAt;
  // Окремо для автора й отримувача — інакше автор, зазирнувши у власний
  // надісланий лист, помилково позначав би його "прочитаним" і для
  // отримувача теж (спільне поле не могло різнити, хто саме відкрив).
  final DateTime? authorOpenedAt;
  final DateTime? recipientOpenedAt;
  final DateTime? recipientSeenAt;
  // true, якщо recipient_id став null через видалення акаунта отримувача
  // (тригер on auth.users), а не тому, що лист від початку писався собі —
  // без цього прапорця UI не міг би розрізнити ці два випадки, і лист
  // другові, чий акаунт видалили, помилково показувався б як "лист собі".
  final bool recipientAccountDeleted;
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
    required this.createdAt,
    required this.unlockAt,
    this.authorOpenedAt,
    this.recipientOpenedAt,
    this.recipientSeenAt,
    this.recipientAccountDeleted = false,
    this.body,
    this.otherPartyName,
  });

  DateTime? _myOpenedAt(String myId) =>
      myId == authorId ? authorOpenedAt : recipientOpenedAt;

  _LetterState stateFor(String myId) {
    if (DateTime.now().isBefore(unlockAt)) return _LetterState.locked;
    if (_myOpenedAt(myId) == null) return _LetterState.unlockedUnread;
    return _LetterState.opened;
  }
}

String _formatDate(DateTime date, BuildContext context) {
  final locale = Localizations.localeOf(context);
  return '${date.day} ${monthNameGenitive(date.month, locale)} ${date.year}';
}

String _letterLabel(_Letter letter, String myId, AppLocalizations l10n) {
  if (letter.recipientAccountDeleted) {
    return l10n.timeCapsuleRecipientDeletedLabel;
  }
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
  bool _loadingMore = false;
  bool _hasMore = false;
  // Знімок "щойно отримано, ще не бачив" на момент відкриття списку — щоб
  // рядок ще підсвічувався крапкою під час цього перегляду, навіть якщо
  // recipient_seen_at уже проставився фоновим запитом нижче.
  Set<String> _newlyReceivedIds = {};
  // Позначення recipient_seen_at — await у _load() сам собою НІЧОГО не
  // блокує в навігації: юзер може вийти (кнопка "назад", свайп) раніше,
  // ніж запит устигне завершитись, і батьківський екран одразу перечитає
  // бейдж зі старими даними. PopScope нижче гарантує, що вихід реально
  // стається лише ПІСЛЯ завершення цього запиту.
  Future<void> _markSeenFuture = Future.value();

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Одна сторінка листів, найновіші спершу. [before] — курсор
  /// (`created_at` останнього вже завантаженого листа), null для першої
  /// сторінки. `hasMore` — та сама евристика, що й `comment_activity.dart`:
  /// якщо сторінка прийшла повною ([_lettersPageSize] рядків), вважаємо,
  /// що далі, ймовірно, є ще, без окремого зонд-запиту.
  Future<(List<_Letter>, bool)> _fetchLettersPage({DateTime? before}) async {
    final myId = _supabase.auth.currentUser!.id;
    // "Видалено для мене" фільтрується тут, не в RLS SELECT-політиці —
    // якщо RLS сама звіряє author_deleted_at/recipient_deleted_at, Postgres
    // починає відхиляти сам UPDATE, що ставить цю позначку (WITH CHECK
    // нового рядка перестає проходити ту саму SELECT-політику).
    var query = _supabase
        .from('future_letters')
        .select(
          'id, author_id, recipient_id, recipient_account_deleted, created_at, unlock_at, author_opened_at, recipient_opened_at, recipient_seen_at, future_letter_bodies(body)',
        )
        .or(
          'and(author_id.eq.$myId,author_deleted_at.is.null),'
          'and(recipient_id.eq.$myId,recipient_deleted_at.is.null)',
        );
    if (before != null) {
      query = query.lt('created_at', before.toUtc().toIso8601String());
    }
    final rows = await query
        .order('created_at', ascending: false)
        .limit(_lettersPageSize);

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
      final authorOpenedAtRaw = row['author_opened_at'] as String?;
      final recipientOpenedAtRaw = row['recipient_opened_at'] as String?;
      final recipientSeenAtRaw = row['recipient_seen_at'] as String?;
      final authorId = row['author_id'] as String;
      final recipientId = row['recipient_id'] as String?;
      final otherId = authorId == myId ? recipientId : authorId;
      return _Letter(
        id: row['id'] as String,
        authorId: authorId,
        recipientId: recipientId,
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
        unlockAt: DateTime.parse(row['unlock_at'] as String).toLocal(),
        authorOpenedAt: authorOpenedAtRaw != null
            ? DateTime.parse(authorOpenedAtRaw).toLocal()
            : null,
        recipientOpenedAt: recipientOpenedAtRaw != null
            ? DateTime.parse(recipientOpenedAtRaw).toLocal()
            : null,
        recipientSeenAt: recipientSeenAtRaw != null
            ? DateTime.parse(recipientSeenAtRaw).toLocal()
            : null,
        recipientAccountDeleted:
            row['recipient_account_deleted'] as bool? ?? false,
        body: bodyRow?['body'] as String?,
        otherPartyName: otherId != null ? nameById[otherId] : null,
      );
    }).toList();

    return (letters, letters.length >= _lettersPageSize);
  }

  /// Той самий "ознайомлення" ефект, що раніше йшов прямо в [_load] —
  /// сам факт побачити запечатаний лист друга у щойно завантаженій
  /// сторінці вже знімає індикатор, навіть якщо unlock_at ще далеко в
  /// майбутньому.
  Future<void> _markSeen(List<_Letter> letters) async {
    final myId = _supabase.auth.currentUser!.id;
    final unseenIds = letters
        .where((l) => l.recipientId == myId && l.recipientSeenAt == null)
        .map((l) => l.id)
        .toList();
    if (mounted) {
      setState(() => _newlyReceivedIds = {..._newlyReceivedIds, ...unseenIds});
    }
    if (unseenIds.isEmpty) return;
    // Зберігаємо посилання на Future — PopScope в build() чекає саме на
    // нього перед фактичним виходом з екрана (див. коментар біля поля
    // _markSeenFuture).
    _markSeenFuture = _supabase
        .from('future_letters')
        .update({'recipient_seen_at': DateTime.now().toUtc().toIso8601String()})
        .inFilter('id', unseenIds);
    await _markSeenFuture;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final (letters, hasMore) = await _fetchLettersPage();
      if (mounted) {
        setState(() {
          _letters = letters;
          _hasMore = hasMore;
        });
      }
      await _markSeen(letters);
    } catch (_) {
      // Список просто лишається таким, яким був — немає окремого
      // "щось пішло не так" стану для цього екрана, спробує ще раз при
      // наступному відкритті.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_letters.isEmpty || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final (letters, hasMore) = await _fetchLettersPage(
        before: _letters.last.createdAt,
      );
      if (mounted) {
        setState(() {
          _letters = [..._letters, ...letters];
          _hasMore = hasMore;
        });
      }
      await _markSeen(letters);
    } catch (_) {
      // Та сама тиха відмова, що й _load — спробує ще раз, якщо юзер
      // натисне "Показати ще" повторно.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Викликається лише з FAB "Написати новий лист" (видимий тільки коли
  /// список НЕ порожній). Якщо юзер ще ЖОДНОГО листа сам не писав (лише
  /// отримував — інакше список був би порожній, і він побачив би це саме
  /// пояснення через _EmptyState), показуємо те саме пояснення механіки
  /// перед першим написанням. Перевірка на живих даних (чи є серед
  /// _letters лист, де я автор), не окремий прапорець — переживає
  /// перевстановлення застосунку і не може розсинхронитись із реальністю.
  /// _EmptyState.onWrite викликає _openComposeSheet() НАПРЯМУ, минаючи цю
  /// перевірку — інакше юзер бачив би те саме пояснення двічі поспіль.
  Future<void> _openCompose() async {
    final myId = _supabase.auth.currentUser?.id;
    final everWrote = _letters.any((l) => l.authorId == myId);
    if (!everWrote) {
      final l10n = AppLocalizations.of(context);
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AppDialog(
          title: l10n.timeCapsulesEmptyTitle,
          content: Text(
            l10n.timeCapsulesEmptySubtitle,
            style: const TextStyle(color: AppColors.inkMuted, height: 1.4),
          ),
          primaryLabel: l10n.gotIt,
          onPrimary: () => Navigator.of(context).pop(true),
          secondaryLabel: l10n.cancel,
          onSecondary: () => Navigator.of(context).pop(false),
        ),
      );
      if (proceed != true) return;
    }
    if (mounted) await _openComposeSheet();
  }

  Future<void> _openComposeSheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      // Свайп/тап повз вимкнено — лист може бути до 5000 символів, і
      // випадкове закриття без підтвердження стирало б усе написане.
      // Закрити можна лише явною кнопкою "X" усередині шторки, яка сама
      // питає підтвердження, якщо текст не порожній.
      isDismissible: false,
      enableDrag: false,
      builder: (_) => const _ComposeLetterSheet(),
    );
    if (saved == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).timeCapsulesSealedConfirmation,
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      _load();
    }
  }

  Future<void> _openLetter(_Letter letter) async {
    final l10n = AppLocalizations.of(context);
    final myId = _supabase.auth.currentUser!.id;
    final state = letter.stateFor(myId);
    if (state == _LetterState.locked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.timeCapsulesStillLocked(_formatDate(letter.unlockAt, context)),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    if (state == _LetterState.unlockedUnread) {
      final column = myId == letter.authorId
          ? 'author_opened_at'
          : 'recipient_opened_at';
      await _supabase
          .from('future_letters')
          .update({column: DateTime.now().toUtc().toIso8601String()})
          .eq('id', letter.id);
    }

    if (!mounted) return;
    final title = _letterLabel(letter, myId, l10n);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _LetterDetailScreen(title: title, body: letter.body ?? ''),
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

    try {
      final myId = _supabase.auth.currentUser!.id;
      final isAuthor = letter.authorId == myId;
      final isSelfLetter = letter.recipientId == null;
      if (isSelfLetter || (isAuthor && letter.recipientOpenedAt == null)) {
        // Втрачати нічого — інша сторона або не існує, або ще навіть не
        // бачила текст, тому стираємо рядок повністю. RETURNING тут
        // безпечний для перевірки — DELETE-політика звіряється зі старим
        // рядком, який ще існував і був видимий нам.
        final affected = await _supabase
            .from('future_letters')
            .delete()
            .eq('id', letter.id)
            .select('id');
        if (affected.isEmpty) throw Exception('RLS blocked the delete');
      } else {
        // М'яке видалення — ховаємо лише зі свого боку, інша сторона (яка
        // вже читала або є автором) зберігає свою копію. Без .select() тут
        // навмисно: після встановлення recipient_deleted_at/author_deleted_at
        // рядок одразу перестає проходити SELECT-політику для НАС САМИХ,
        // тож RETURNING легітимно повернув би порожньо навіть при успіху —
        // покладаємось на те, що WITH CHECK кидає реальний виняток при
        // фактичній відмові.
        final column = isAuthor ? 'author_deleted_at' : 'recipient_deleted_at';
        await _supabase
            .from('future_letters')
            .update({column: DateTime.now().toUtc().toIso8601String()})
            .eq('id', letter.id);
      }
      _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).somethingWentWrong),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _markSeenFuture;
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.timeCapsulesMenuLabel, style: appScreenTitle()),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _letters.isEmpty
            ? _EmptyState(onWrite: _openComposeSheet)
            : _buildLetterList(l10n),
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
      ),
    );
  }

  Widget _buildLetterList(AppLocalizations l10n) {
    final myId = _supabase.auth.currentUser!.id;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        for (final letter in _letters)
          _LetterRow(
            letter: letter,
            myId: myId,
            onTap: () => _openLetter(letter),
            // Автор може передумати будь-коли; отримувач — лише
            // прочитавши, щоб не стерти чужу працю навіть не глянувши.
            onDelete:
                letter.authorId == myId ||
                    letter.stateFor(myId) == _LetterState.opened
                ? () => _confirmDelete(letter)
                : null,
            // "Новий" для щойно розкритого — той самий виняток, що й
            // бейдж на меню: не для автора, що просто не перечитує вже
            // надісланий другові лист (не потребує його уваги).
            showNewDot:
                _newlyReceivedIds.contains(letter.id) ||
                (letter.stateFor(myId) == _LetterState.unlockedUnread &&
                    (letter.recipientId == null || letter.authorId != myId)),
          ),
        if (_hasMore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: _loadingMore
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed: _loadMore,
                      child: Text(l10n.showMore),
                    ),
            ),
          ),
      ],
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
              style: const TextStyle(
                color: AppColors.inkMuted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.accentInk,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
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
  final String myId;
  final VoidCallback onTap;
  // Тільки для ще незапечатаних листів — видима кнопка замість прихованого
  // long-press, який ніхто сам не здогадався б спробувати.
  final VoidCallback? onDelete;
  // Або щойно отриманий лист від друга (ще не бачений у списку раніше),
  // або щойно розкрився і чекає на прочитання — той самий привід, що й для
  // бейджа на меню/банері, лише вказаний на конкретному рядку.
  final bool showNewDot;

  const _LetterRow({
    required this.letter,
    required this.myId,
    required this.onTap,
    this.onDelete,
    this.showNewDot = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = letter.stateFor(myId);
    final IconData icon;
    final String status;
    switch (state) {
      case _LetterState.locked:
        icon = PhosphorIconsLight.lockKey;
        status = l10n.timeCapsulesLockedUntil(
          _formatDate(letter.unlockAt, context),
        );
        break;
      case _LetterState.unlockedUnread:
        icon = PhosphorIconsLight.envelopeSimpleOpen;
        status = l10n.timeCapsulesLockedUntil(
          _formatDate(letter.unlockAt, context),
        );
        break;
      case _LetterState.opened:
        icon = PhosphorIconsLight.bookOpen;
        status = l10n.timeCapsulesOpenedOn(
          _formatDate(letter._myOpenedAt(myId) ?? letter.unlockAt, context),
        );
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              if (showNewDot) ...[
                const DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.notification,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(width: 8, height: 8),
                ),
                const SizedBox(width: 10),
              ],
              Icon(icon, color: AppColors.inkMuted, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _letterLabel(letter, myId, l10n),
                      style: const TextStyle(color: AppColors.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status,
                      style: const TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(
                    PhosphorIconsLight.trash,
                    size: 18,
                    color: AppColors.inkMuted,
                  ),
                  tooltip: l10n.delete,
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

  const _RecipientPickerSheet({
    required this.friends,
    required this.selectedId,
  });

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
                        label: l10n.timeCapsulesRecipientSelf,
                        selected: widget.selectedId == null,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(_RecipientPickResult(null)),
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
          ? const Icon(
              PhosphorIconsLight.check,
              color: AppColors.accent,
              size: 18,
            )
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

      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).somethingWentWrong),
          ),
        );
      }
    }
  }

  /// true — можна закривати (текст порожній або юзер підтвердив втрату).
  Future<bool> _confirmDiscard() async {
    if (_controller.text.trim().isEmpty) return true;
    final l10n = AppLocalizations.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: l10n.discardLetterConfirmTitle,
        content: Text(
          l10n.discardLetterConfirmBody,
          style: const TextStyle(color: AppColors.inkMuted),
        ),
        primaryLabel: l10n.keepWriting,
        onPrimary: () => Navigator.of(context).pop(false),
        secondaryLabel: l10n.discardLetter,
        secondaryColor: Colors.redAccent,
        onSecondary: () => Navigator.of(context).pop(true),
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final canDiscard = await _confirmDiscard();
        if (canDiscard && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          // Клавіатура (viewInsets) ДО padding.bottom — цей другий доданок
          // бракувало: без нього кнопка ховалась під системною навігацією
          // Android (жестовою панеллю чи 3-кнопковою), бо на iOS safe-area
          // знизу вже враховувалась інакше й проблема там не виникала.
          20 +
              MediaQuery.of(context).viewInsets.bottom +
              MediaQuery.of(context).padding.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () async {
                    if (await _confirmDiscard() && context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      PhosphorIconsLight.x,
                      size: 20,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
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
              // списку). AnimatedSize — той самий фікс, що для банерів і
              // тижневої стрічки: _friends вантажиться асинхронно в
              // initState, тож без цього дропдаун миттєво "вистрибував"
              // знизу, щойно список друзів довантажувався.
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _friends.isEmpty
                    ? const SizedBox.shrink()
                    : Column(
                        children: [
                          // Без окремого підпису "Кому" — значення дропдауна
                          // (напр. "собі") разом із шевроном і так
                          // зрозуміле без пояснення.
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () async {
                              final picked =
                                  await showModalBottomSheet<
                                    _RecipientPickResult
                                  >(
                                    context: context,
                                    isScrollControlled: true,
                                    builder: (_) => _RecipientPickerSheet(
                                      friends: _friends,
                                      selectedId: _recipientId,
                                    ),
                                  );
                              if (picked != null) {
                                setState(() => _recipientId = picked.id);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _recipientId == null
                                          ? l10n.timeCapsulesRecipientSelf
                                          : _friends
                                                .firstWhere(
                                                  (f) => f.id == _recipientId,
                                                )
                                                .name,
                                      style: const TextStyle(
                                        color: AppColors.ink,
                                      ),
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
                      ),
              ),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accentInk,
                          ),
                        )
                      : Text(l10n.timeCapsulesSeal),
                ),
              ),
            ],
          ),
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
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 16,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
