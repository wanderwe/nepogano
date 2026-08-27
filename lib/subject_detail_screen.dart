import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'comments_section.dart';
import 'l10n/app_localizations.dart';
import 'main.dart';
import 'photo_storage.dart';
import 'style.dart';

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _relativeDay(DateTime dateTime, AppLocalizations l10n) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dateTime.year, dateTime.month, dateTime.day);
  final diff = today.difference(day).inDays;

  if (diff == 0) return l10n.today;
  if (diff == 1) return l10n.yesterday;
  return '${dateTime.day}.${dateTime.month}';
}

class _SubjectDayEntry {
  final String id;
  final MoodLevel mood;
  final String? note;
  final String? photoPath;
  final double photoAlignY;
  final double photoScale;
  final DateTime date;

  _SubjectDayEntry({
    required this.id,
    required this.mood,
    required this.note,
    required this.photoPath,
    required this.photoAlignY,
    required this.photoScale,
    required this.date,
  });
}

/// Екран щоденника сутності для учасника кола, якому власник відкрив
/// перегляд (subject_folder_shares) — той самий "вгадай, тоді дивись і
/// коментуй" ритуал, що [PersonDetailScreen] для реальних людей, тепер
/// поширений і на сутності (дитина/улюбленець) за продуктовим рішенням,
/// узгодженим з користувачем. Власник і співавтори сюди не потрапляють —
/// вони мають повний прямий доступ через HistoryScreen (календар).
class SubjectDetailScreen extends StatefulWidget {
  final String subjectId;
  final String subjectName;

  const SubjectDetailScreen({
    super.key,
    required this.subjectId,
    required this.subjectName,
  });

  @override
  State<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<SubjectDetailScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  List<_SubjectDayEntry> _entries = [];
  final Map<String, String?> _myGuesses = {};

  // Те саме, що для друзів (PersonDetailScreen) — RLS уже дає повний доступ
  // до всієї історії сутності незалежно від дати, kGuessWindowDays лише
  // стартове вікно. Нема принципової різниці "чи це друг, чи родич, якому
  // відкрили щоденник дитини" — обом однаково можна дивитись глибше.
  int _windowDays = kGuessWindowDays;
  bool _loadingMore = false;
  bool _hasMore = true;

  /// Той самий фікс, що в Історії й на головному екрані — довга нотатка
  /// без обрізання змушувала нескінченно свайпати повз неї.
  final Set<String> _expandedNoteIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _dayKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

  /// Розширює вікно кроками по [kGuessWindowDays], поки не з'явиться хоч
  /// один новий запис (або поки старших записів не лишиться взагалі) —
  /// без цього кожен клік розширював вікно рівно на тиждень, і порожній
  /// тиждень виглядав так, ніби "Показати ще" нічого не робить.
  Future<void> _loadMoreEntries() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final previousCount = _entries.length;
    do {
      _windowDays += kGuessWindowDays;
      await _load(isLoadMore: true);
    } while (_hasMore && _entries.length == previousCount);
    if (mounted) setState(() => _loadingMore = false);
  }

  Future<void> _load({bool isLoadMore = false}) async {
    if (!isLoadMore) setState(() => _loading = true);

    final myId = _supabase.auth.currentUser!.id;
    final since = DateTime.now().subtract(Duration(days: _windowDays));
    final sinceUtc = DateTime(
      since.year,
      since.month,
      since.day,
    ).toUtc().toIso8601String();

    // Пряма перевірка "чи є щось старше за вікно" замість порівняння
    // кількості записів між викликами — те раніше рахувалось лише при
    // "Показати ще", тож кнопка завжди висіла після першого відкриття
    // екрана, навіть коли підвантажувати вже нічого.
    final olderRows = await _supabase
        .from('subject_checkins')
        .select('id')
        .eq('subject_id', widget.subjectId)
        .lt('created_at', sinceUtc)
        .limit(1);
    final hasMore = (olderRows as List).isNotEmpty;

    final checkinRows = await _supabase
        .from('subject_checkins')
        .select(
          'id, mood, note, photo_path, photo_align_y, photo_scale, created_at',
        )
        .eq('subject_id', widget.subjectId)
        .gte('created_at', sinceUtc)
        .order('created_at', ascending: false);

    final entries = <_SubjectDayEntry>[];
    final seenDayKeys = <String>{};
    for (final row in checkinRows as List) {
      final createdAt = DateTime.parse(row['created_at'] as String).toLocal();
      final date = DateTime(createdAt.year, createdAt.month, createdAt.day);
      if (!seenDayKeys.add(_dayKey(date))) continue;
      entries.add(
        _SubjectDayEntry(
          id: row['id'] as String,
          mood: moodFromDbValue(row['mood'] as String),
          note: row['note'] as String?,
          photoPath: row['photo_path'] as String?,
          photoAlignY: (row['photo_align_y'] as num?)?.toDouble() ?? 0,
          photoScale: (row['photo_scale'] as num?)?.toDouble() ?? 1,
          date: date,
        ),
      );
    }

    final guesses = <String, String?>{};
    if (entries.isNotEmpty) {
      final sinceDate = DateTime(
        since.year,
        since.month,
        since.day,
      ).toIso8601String().split('T').first;
      final guessRows = await _supabase
          .from('subject_guesses')
          .select('guessed_mood, target_date')
          .eq('guesser_id', myId)
          .eq('subject_id', widget.subjectId)
          .gte('target_date', sinceDate);

      for (final row in guessRows as List) {
        final targetDate = DateTime.parse(row['target_date'] as String);
        guesses[_dayKey(targetDate)] = row['guessed_mood'] as String;
      }
    }

    entries.sort((a, b) => b.date.compareTo(a.date));

    if (!mounted) return;
    setState(() {
      _entries = entries;
      _myGuesses
        ..clear()
        ..addAll(guesses);
      _loading = false;
      _hasMore = hasMore;
    });
  }

  Future<void> _guess(_SubjectDayEntry entry, MoodLevel guessedMood) async {
    final targetDate = entry.date.toIso8601String().split('T').first;
    final key = _dayKey(entry.date);

    try {
      await _supabase.from('subject_guesses').insert({
        'guesser_id': _supabase.auth.currentUser!.id,
        'subject_id': widget.subjectId,
        'target_date': targetDate,
        'guessed_mood': guessedMood.dbValue,
        'correct': guessedMood == entry.mood,
      });
      setState(() => _myGuesses[key] = guessedMood.dbValue);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).couldNotSaveGuess),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
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
                  Expanded(
                    child: Text(
                      widget.subjectName,
                      overflow: TextOverflow.ellipsis,
                      style: appScreenTitle(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_entries.isEmpty)
                // Порожньо в поточному вікні — сам напис і так інформативний
                // (є/нема свіжих новин), центрований, як завжди. Якщо
                // старіші записи все ж є (_hasMore), під написом додається
                // кнопка з окремим формулюванням "Показати старіші" —
                // "Показати ще" тут звучало б дивно, бо показувати після
                // порожнього списку нічого "ще", лише щось старе.
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.notCheckedInToday,
                          style: const TextStyle(color: AppColors.inkMuted),
                        ),
                        if (_hasMore) ...[
                          const SizedBox(height: 12),
                          _loadingMore
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : TextButton(
                                  onPressed: _loadMoreEntries,
                                  // Точково акцентний колір замість
                                  // приглушеного дефолту теми — інакше
                                  // кнопка зливається з написом над нею й не
                                  // виглядає як щось клікабельне.
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.accent,
                                  ),
                                  child: Text(l10n.showOlder),
                                ),
                        ],
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    children: [
                      ..._entries.map(_buildEntryCard),
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
                                    onPressed: _loadMoreEntries,
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

  Widget _buildEntryCard(_SubjectDayEntry entry) {
    final l10n = AppLocalizations.of(context);
    final myGuess = _myGuesses[_dayKey(entry.date)];
    final isToday = _isSameDay(entry.date, DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isToday ? l10n.today : _relativeDay(entry.date, l10n),
            style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 10),
          if (myGuess != null) ...[
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
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 10),
                Text(
                  myGuess == entry.mood.dbValue
                      ? l10n.guessedRight
                      : l10n.guessedWrong,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: myGuess == entry.mood.dbValue
                        ? AppColors.ink
                        : AppColors.notification,
                  ),
                ),
              ],
            ),
            if ((entry.note ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              ExpandableNote(
                text: entry.note!,
                expanded: _expandedNoteIds.contains(entry.id),
                onToggle: () => setState(() {
                  if (!_expandedNoteIds.add(entry.id)) {
                    _expandedNoteIds.remove(entry.id);
                  }
                }),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.ink,
                  height: 1.4,
                ),
              ),
            ],
            if (entry.photoPath != null) ...[
              const SizedBox(height: 10),
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
            CommentsSection(
              key: ValueKey('comments-${entry.id}'),
              checkinId: entry.id,
              canComment: true,
              isOwner: false,
              isSubject: true,
            ),
          ] else ...[
            Text(
              l10n.howAreTheyToday,
              style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
            ),
            const SizedBox(height: 10),
            Row(
              children: MoodLevel.values.map((mood) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GuessMoodButton(
                    mood: mood,
                    onTap: () => _guess(entry, mood),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
