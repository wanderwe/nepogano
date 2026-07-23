import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'date_labels.dart';
import 'day_card_screen.dart';
import 'l10n/app_localizations.dart';
import 'main.dart';
import 'photo_storage.dart';
import 'style.dart';

class CheckinEntry {
  final DateTime createdAt;
  final MoodLevel mood;
  final String? note;
  final String? photoPath;
  final double photoAlignY;

  CheckinEntry({
    required this.createdAt,
    required this.mood,
    this.note,
    this.photoPath,
    this.photoAlignY = 0,
  });
}

class HistoryScreen extends StatefulWidget {
  final String? subjectId;
  final String? subjectName;

  const HistoryScreen({super.key, this.subjectId, this.subjectName});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _supabase = Supabase.instance.client;

  String get _table =>
      widget.subjectId == null ? 'checkins' : 'subject_checkins';
  String get _idColumn => widget.subjectId == null ? 'user_id' : 'subject_id';
  String get _idValue => widget.subjectId ?? _supabase.auth.currentUser!.id;

  bool _loading = true;
  String? _error;
  List<CheckinEntry> _entries = [];
  late DateTime _visibleMonth;

  /// Ключі записів у списку внизу (по дню місяця), щоб можна було
  /// проскролити до потрібного запису кліком по дню в календарі.
  final Map<int, GlobalKey> _entryKeys = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await _supabase
          .from(_table)
          .select('mood, note, created_at, photo_path, photo_align_y')
          .eq(_idColumn, _idValue)
          .order('created_at');

      final entries = (rows as List).map((row) {
        return CheckinEntry(
          createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
          mood: moodFromDbValue(row['mood'] as String),
          note: row['note'] as String?,
          photoPath: row['photo_path'] as String?,
          photoAlignY: (row['photo_align_y'] as num?)?.toDouble() ?? 0,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context).couldNotLoadHistory;
          _loading = false;
        });
      }
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _visibleMonth.year == now.year && _visibleMonth.month == now.month;
  }

  void _scrollToDay(int day) {
    final ctx = _entryKeys[day]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.1,
    );
  }

  /// Останній запис на кожен день місяця (якщо їх декілька — переможе новіший)
  Map<int, CheckinEntry> get _entriesByDay {
    final map = <int, CheckinEntry>{};
    for (final entry in _entries) {
      if (entry.createdAt.year == _visibleMonth.year &&
          entry.createdAt.month == _visibleMonth.month) {
        map[entry.createdAt.day] = entry;
      }
    }
    return map;
  }

  List<CheckinEntry> get _monthEntriesDesc {
    final list = _entries
        .where(
          (e) =>
              e.createdAt.year == _visibleMonth.year &&
              e.createdAt.month == _visibleMonth.month,
        )
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Скільки днів місяця припало на кожну оцінку (по одному дню — один запис).
  Map<MoodLevel, int> get _monthMoodCounts {
    final counts = <MoodLevel, int>{};
    for (final entry in _entriesByDay.values) {
      counts[entry.mood] = (counts[entry.mood] ?? 0) + 1;
    }
    return counts;
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
                    icon: const Icon(Icons.arrow_back, size: 20),
                    tooltip: l10n.back,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.subjectName == null
                        ? l10n.history
                        : '${l10n.history} — ${widget.subjectName}',
                    style: appSerif(fontSize: 22),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          style: const TextStyle(color: AppColors.inkMuted),
                        ),
                        const SizedBox(height: 12),
                        TextButton(onPressed: _load, child: Text(l10n.retry)),
                      ],
                    ),
                  ),
                )
              else
                Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final locale = Localizations.localeOf(context);
    final entriesByDay = _entriesByDay;
    final daysInMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    ).day;
    final leadingBlanks =
        DateTime(_visibleMonth.year, _visibleMonth.month, 1).weekday - 1;
    final today = DateTime.now();

    return ListView(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              onPressed: () => _changeMonth(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              '${monthName(_visibleMonth.month, locale)} ${_visibleMonth.year}',
              style: appSerif(fontSize: 17),
            ),
            IconButton(
              onPressed: _isCurrentMonth ? null : () => _changeMonth(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(7, (i) => i + 1)
              .map(
                (weekday) => Expanded(
                  child: Center(
                    child: Text(
                      weekdayLabel(weekday, locale),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
          itemCount: leadingBlanks + daysInMonth,
          itemBuilder: (context, index) {
            if (index < leadingBlanks) return const SizedBox.shrink();

            final day = index - leadingBlanks + 1;
            final date = DateTime(_visibleMonth.year, _visibleMonth.month, day);
            final entry = entriesByDay[day];
            final isFuture = date.isAfter(
              DateTime(today.year, today.month, today.day),
            );
            final isToday =
                date.year == today.year &&
                date.month == today.month &&
                date.day == today.day;

            return AspectRatio(
              aspectRatio: 1,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: entry != null ? () => _scrollToDay(day) : null,
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    decoration: BoxDecoration(
                      color: entry != null
                          ? entry.mood.color.withValues(alpha: 0.85)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(9),
                      border: isToday
                          ? Border.all(color: AppColors.ink, width: 1.5)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$day',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: entry != null
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: entry != null
                            ? Colors.white
                            : (isFuture ? Colors.white24 : AppColors.inkMuted),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 28),
        _buildRetrospective(),
        _buildEntryList(),
      ],
    );
  }

  Widget _buildRetrospective() {
    final counts = _monthMoodCounts;
    final moodsWithData = MoodLevel.values
        .where((m) => (counts[m] ?? 0) > 0)
        .toList();
    if (moodsWithData.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.thisMonth,
            style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 12),
          Row(
            children: moodsWithData.map((mood) {
              return Expanded(
                flex: counts[mood]!,
                child: Container(
                  height: 8,
                  margin: EdgeInsets.only(
                    right: mood == moodsWithData.last ? 0 : 3,
                  ),
                  decoration: BoxDecoration(
                    color: mood.color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: moodsWithData.map((mood) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: mood.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${mood.label(context)} · ${counts[mood]}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryList() {
    final entries = _monthEntriesDesc;

    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          AppLocalizations.of(context).noEntriesThisMonth,
          style: const TextStyle(color: AppColors.inkMuted),
        ),
      );
    }

    _entryKeys.clear();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries.map((entry) {
        final d = entry.createdAt;
        final dateLabel = '${d.day}.${d.month}.${d.year}';
        final key = _entryKeys.putIfAbsent(d.day, () => GlobalKey());

        return Container(
          key: key,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 5),
                decoration: BoxDecoration(
                  color: entry.mood.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          entry.mood.label(context),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          dateLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                    if (entry.note != null && entry.note!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        entry.note!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                    if (entry.photoPath != null) ...[
                      const SizedBox(height: 8),
                      FutureBuilder<Uint8List?>(
                        future: downloadCheckinPhoto(entry.photoPath!),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const SizedBox.shrink();
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(
                              snapshot.data!,
                              height: 90,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              alignment: Alignment(0, entry.photoAlignY),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DayCardScreen(entry: entry),
                  ),
                ),
                icon: const Icon(Icons.ios_share, size: 18),
                tooltip: AppLocalizations.of(context).dayCard,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
