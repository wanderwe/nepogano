import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'day_card_screen.dart';
import 'main.dart';
import 'style.dart';

const _monthNames = [
  'Січень', 'Лютий', 'Березень', 'Квітень', 'Травень', 'Червень',
  'Липень', 'Серпень', 'Вересень', 'Жовтень', 'Листопад', 'Грудень',
];

const _weekdayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Нд'];

class CheckinEntry {
  final DateTime createdAt;
  final MoodLevel mood;
  final String? note;

  CheckinEntry({required this.createdAt, required this.mood, this.note});
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<CheckinEntry> _entries = [];
  late DateTime _visibleMonth;

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
          .from('checkins')
          .select('mood, note, created_at')
          .order('created_at');

      final entries = (rows as List).map((row) {
        return CheckinEntry(
          createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
          mood: moodFromDbValue(row['mood'] as String),
          note: row['note'] as String?,
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
          _error = 'Не вдалось завантажити історію.';
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
    final list = _entries.where((e) =>
        e.createdAt.year == _visibleMonth.year &&
        e.createdAt.month == _visibleMonth.month).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Widget build(BuildContext context) {
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
                    tooltip: 'Назад',
                  ),
                  const SizedBox(width: 4),
                  Text('Історія', style: appSerif(fontSize: 22)),
                ],
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, style: const TextStyle(color: AppColors.inkMuted)),
                        const SizedBox(height: 12),
                        TextButton(onPressed: _load, child: const Text('Спробувати ще раз')),
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
    final entriesByDay = _entriesByDay;
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final leadingBlanks = DateTime(_visibleMonth.year, _visibleMonth.month, 1).weekday - 1;
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
              '${_monthNames[_visibleMonth.month - 1]} ${_visibleMonth.year}',
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
          children: _weekdayLabels
              .map((label) => Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                      ),
                    ),
                  ))
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
            final isFuture = date.isAfter(DateTime(today.year, today.month, today.day));
            final isToday = date.year == today.year &&
                date.month == today.month &&
                date.day == today.day;

            return AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: entry != null
                      ? entry.mood.color.withValues(alpha: 0.85)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(9),
                  border: isToday ? Border.all(color: AppColors.ink, width: 1.5) : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: entry != null ? FontWeight.w600 : FontWeight.w400,
                    color: entry != null
                        ? Colors.white
                        : (isFuture ? Colors.white24 : AppColors.inkMuted),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 28),
        _buildEntryList(),
      ],
    );
  }

  Widget _buildEntryList() {
    final entries = _monthEntriesDesc;

    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'У цьому місяці ще немає записів.',
          style: TextStyle(color: AppColors.inkMuted),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries.map((entry) {
        final d = entry.createdAt;
        final dateLabel = '${d.day}.${d.month}.${d.year}';

        return Container(
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
                decoration: BoxDecoration(color: entry.mood.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          entry.mood.label,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          dateLabel,
                          style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                        ),
                      ],
                    ),
                    if (entry.note != null && entry.note!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        entry.note!,
                        style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => DayCardScreen(entry: entry)),
                ),
                icon: const Icon(Icons.ios_share, size: 18),
                tooltip: 'Картка дня',
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
