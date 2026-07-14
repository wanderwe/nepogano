import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_screen.dart';
import 'day_card_screen.dart';
import 'history_screen.dart';
import 'style.dart';

// TODO: встав сюди свій Project URL і anon key з Supabase (Settings → API)
const supabaseUrl = 'https://wxxvqscmalcuurhvzufl.supabase.co';
const supabaseAnonKey = 'sb_publishable_H5DIUfH_i4_Mm5VKSoAoNA__tT60BUI';

/// Показує лоадер замість логін-екрана, поки триває обмін Google-коду на сесію
/// (браузер повертається в застосунок раніше, ніж Supabase встигає завершити обмін).
final ValueNotifier<bool> googleSignInPending = ValueNotifier<bool>(false);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(const NepoganoApp());
}

class NepoganoApp extends StatelessWidget {
  const NepoganoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xFFE0A458),
      scaffoldBackgroundColor: AppColors.background,
    );

    return MaterialApp(
      title: 'Nepogano',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(textTheme: GoogleFonts.interTextTheme(base.textTheme)),
      home: const AuthGate(),
    );
  }
}

/// Слухає стан авторизації і показує або екран входу, або чек-ін
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<AuthState> _authStateStream;

  @override
  void initState() {
    super.initState();
    _authStateStream = Supabase.instance.client.auth.onAuthStateChange;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _authStateStream,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          return const CheckInScreen();
        }
        return ValueListenableBuilder<bool>(
          valueListenable: googleSignInPending,
          builder: (context, pending, _) {
            if (pending) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return const AuthScreen();
          },
        );
      },
    );
  }
}

enum MoodLevel { niyak, nepogano, zbs }

extension MoodLevelData on MoodLevel {
  String get label {
    switch (this) {
      case MoodLevel.niyak:
        return 'Ніяк';
      case MoodLevel.nepogano:
        return 'Непогано';
      case MoodLevel.zbs:
        return 'Збс';
    }
  }

  // Значення, яке зберігається в базі даних (має збігатись з CHECK constraint у SQL)
  String get dbValue {
    switch (this) {
      case MoodLevel.niyak:
        return 'niyak';
      case MoodLevel.nepogano:
        return 'nepogano';
      case MoodLevel.zbs:
        return 'zbs';
    }
  }

  Color get color {
    switch (this) {
      case MoodLevel.niyak:
        return const Color(0xFFB0B0B0);
      case MoodLevel.nepogano:
        return const Color(0xFFE0A458);
      case MoodLevel.zbs:
        return const Color(0xFF4FC3B0);
    }
  }
}

MoodLevel moodFromDbValue(String value) {
  return MoodLevel.values.firstWhere((m) => m.dbValue == value);
}

class _MoodTile extends StatefulWidget {
  final MoodLevel mood;
  final bool isSelected;
  final VoidCallback onTap;

  const _MoodTile({
    required this.mood,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_MoodTile> createState() => _MoodTileState();
}

class _MoodTileState extends State<_MoodTile> {
  bool _pressed = false;

  void _setPressed(bool value) => setState(() => _pressed = value);

  @override
  Widget build(BuildContext context) {
    final mood = widget.mood;
    final isSelected = widget.isSelected;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: isSelected ? mood.color.withValues(alpha: 0.16) : AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: isSelected ? Border.all(color: mood.color, width: 2) : null,
          ),
          child: Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: mood.color, shape: BoxShape.circle),
              ),
              const SizedBox(height: 10),
              Text(
                mood.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? AppColors.ink : AppColors.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CheckInScreen extends StatefulWidget {
  const CheckInScreen({super.key});

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  MoodLevel? _selected;
  final TextEditingController _noteController = TextEditingController();
  bool _saving = false;
  Object? _todayEntryId;
  DateTime? _todayEntrySavedAt;
  List<CheckinEntry> _weekEntries = [];

  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadTodayEntry();
    _loadWeek();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  (String, String) _todayRangeUtc() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final startOfNextDay = DateTime(now.year, now.month, now.day + 1);
    return (
      startOfDay.toUtc().toIso8601String(),
      startOfNextDay.toUtc().toIso8601String(),
    );
  }

  Future<void> _loadTodayEntry() async {
    final (startOfDay, startOfNextDay) = _todayRangeUtc();

    final rows = await _supabase
        .from('checkins')
        .select('id, mood, note, created_at')
        .gte('created_at', startOfDay)
        .lt('created_at', startOfNextDay)
        .order('created_at', ascending: false)
        .limit(1);

    if (!mounted || (rows as List).isEmpty) return;

    final row = rows.first;
    setState(() {
      _todayEntryId = row['id'];
      _selected = moodFromDbValue(row['mood'] as String);
      _noteController.text = (row['note'] as String?) ?? '';
      _todayEntrySavedAt = DateTime.parse(row['created_at'] as String).toLocal();
    });
  }

  Future<void> _loadWeek() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - 6).toUtc().toIso8601String();

    final rows = await _supabase
        .from('checkins')
        .select('mood, note, created_at')
        .gte('created_at', start)
        .order('created_at');

    if (!mounted) return;

    setState(() {
      _weekEntries = (rows as List).map((row) {
        return CheckinEntry(
          createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
          mood: moodFromDbValue(row['mood'] as String),
          note: row['note'] as String?,
        );
      }).toList();
    });
  }

  Future<void> _save() async {
    if (_selected == null) return;

    setState(() => _saving = true);

    try {
      final payload = {
        'mood': _selected!.dbValue,
        'note': _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      };

      if (_todayEntryId != null) {
        final updated = await _supabase
            .from('checkins')
            .update(payload)
            .eq('id', _todayEntryId as Object)
            .select('id');
        if ((updated as List).isEmpty) {
          throw Exception('Update affected 0 rows — check RLS UPDATE policy on checkins.');
        }
      } else {
        final inserted = await _supabase.from('checkins').insert(payload).select('id, created_at').single();
        _todayEntryId = inserted['id'];
        _todayEntrySavedAt = DateTime.parse(inserted['created_at'] as String).toLocal();
      }
      unawaited(_loadWeek());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Збережено: ${_selected!.label}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не вдалось зберегти. Спробуй ще раз.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    await _supabase.auth.signOut();
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: const Text('Видалити акаунт?'),
        content: const Text(
          'Це видалить твій акаунт і всі записи назавжди. Скасувати неможливо.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Скасувати'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Видалити', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _supabase.rpc('delete_own_account');
      await _supabase.auth.signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не вдалось видалити акаунт. Спробуй ще раз.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final dateLabel = '${today.day}.${today.month}.${today.year}';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    dateLabel,
                    style: const TextStyle(fontSize: 14, color: AppColors.inkMuted),
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const HistoryScreen()),
                        ),
                        icon: const Icon(Icons.calendar_month_outlined, size: 20),
                        tooltip: 'Історія',
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 20),
                        tooltip: 'Ще',
                        color: AppColors.surfaceRaised,
                        onSelected: (value) {
                          if (value == 'signOut') _signOut();
                          if (value == 'delete') _confirmDeleteAccount();
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'signOut',
                            child: Text('Вийти'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text(
                              'Видалити акаунт',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              Text(
                'Як пройшов день?',
                style: appSerif(fontSize: 28),
              ),
              if (_todayEntrySavedAt != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Вже зберіг сьогодні о '
                  '${_todayEntrySavedAt!.hour.toString().padLeft(2, '0')}:'
                  '${_todayEntrySavedAt!.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
                ),
              ],
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: MoodLevel.values.map((mood) {
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: _MoodTile(
                                  mood: mood,
                                  isSelected: _selected == mood,
                                  onTap: () => setState(() => _selected = mood),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: _selected != null
                              ? Column(
                                  key: const ValueKey('note-field'),
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TextField(
                                      controller: _noteController,
                                      maxLines: 3,
                                      decoration: InputDecoration(
                                        hintText: 'Пару слів про день (необов\'язково)',
                                        filled: true,
                                        fillColor: AppColors.surface,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(16),
                                          borderSide: BorderSide.none,
                                        ),
                                        contentPadding: const EdgeInsets.all(16),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: _saving ? null : _save,
                                        style: ElevatedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 16),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          backgroundColor: AppColors.ink,
                                          foregroundColor: AppColors.background,
                                        ),
                                        child: _saving
                                            ? const SizedBox(
                                                height: 18,
                                                width: 18,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: AppColors.background,
                                                ),
                                              )
                                            : Text(
                                                _todayEntryId != null ? 'Оновити' : 'Зберегти',
                                                style: const TextStyle(fontSize: 16),
                                              ),
                                      ),
                                    ),
                                    if (_todayEntryId != null) ...[
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: TextButton.icon(
                                          onPressed: () => Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => DayCardScreen(
                                                entry: CheckinEntry(
                                                  createdAt: _todayEntrySavedAt ?? DateTime.now(),
                                                  mood: _selected!,
                                                  note: _noteController.text.trim().isEmpty
                                                      ? null
                                                      : _noteController.text.trim(),
                                                ),
                                              ),
                                            ),
                                          ),
                                          icon: const Icon(Icons.ios_share, size: 18),
                                          label: const Text('Картка дня'),
                                        ),
                                      ),
                                    ],
                                  ],
                                )
                              : const SizedBox.shrink(key: ValueKey('empty')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _buildWeekStrip(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeekStrip() {
    final today = DateTime.now();
    final days = List.generate(7, (i) => DateTime(today.year, today.month, today.day - 6 + i));

    final byDay = <DateTime, MoodLevel>{};
    for (final entry in _weekEntries) {
      final d = DateTime(entry.createdAt.year, entry.createdAt.month, entry.createdAt.day);
      byDay[d] = entry.mood;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'Останній тиждень',
          style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: days.map((d) {
            final mood = byDay[d];
            final isToday = d.year == today.year && d.month == today.month && d.day == today.day;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mood?.color ?? Colors.transparent,
                  border: mood == null
                      ? Border.all(color: AppColors.surfaceRaised, width: 1.5)
                      : (isToday ? Border.all(color: AppColors.ink, width: 1.5) : null),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}