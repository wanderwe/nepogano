import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_screen.dart';
import 'circles_screen.dart';
import 'day_card_screen.dart';
import 'history_screen.dart';
import 'l10n/app_localizations.dart';
import 'locale_provider.dart';
import 'onboarding_screen.dart';
import 'style.dart';

// TODO: встав сюди свій Project URL і anon key з Supabase (Settings → API)
const supabaseUrl = 'https://wxxvqscmalcuurhvzufl.supabase.co';
const supabaseAnonKey = 'sb_publishable_H5DIUfH_i4_Mm5VKSoAoNA__tT60BUI';

/// Показує SnackBar незалежно від того, який екран зараз активний —
/// потрібно, щоб підтвердити автоприєднання до кола за диплінком.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Код запрошення в коло з диплінку (io.supabase.nepogano://join/<code>),
/// що чекає на автора, поки той не залогіниться (диплінк може прийти ще до
/// входу в застосунок).
final ValueNotifier<String?> pendingJoinCode = ValueNotifier<String?>(null);

void _handleJoinLink(Uri? uri) {
  if (uri == null || uri.host != 'join' || uri.pathSegments.isEmpty) return;
  pendingJoinCode.value = uri.pathSegments.first;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  await loadSavedLocale();

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
    // На деяких пристроях перший мережевий запит після старту застосунку іноді
    // ловить короткочасну DNS-помилку (SocketException: Failed host lookup),
    // навіть коли мережа в порядку — і Dart-рівень не ретраїть це сам. Обгортаємо
    // HTTP-клієнт автоматичним retry на такі помилки для всіх запитів Supabase.
    httpClient: RetryClient(
      http.Client(),
      retries: 5,
      delay: (retryCount) => Duration(milliseconds: 500 * (retryCount + 1)),
      whenError: (error, stackTrace) => error is SocketException,
    ),
  );

  final appLinks = AppLinks();
  unawaited(appLinks.getInitialLink().then(_handleJoinLink));
  appLinks.uriLinkStream.listen(_handleJoinLink);

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
      // Прибираємо анімований Android-ripple (той круглий "спалах" на дотик,
      // що читається як застарілий Material-стиль), але лишаємо тиху статичну
      // підсвітку замість нього — щоб прості InkWell не ставали "мертвими" на дотик.
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.white.withValues(alpha: 0.06),
    );

    return ValueListenableBuilder<Locale>(
      valueListenable: appLocale,
      builder: (context, locale, _) {
        return MaterialApp(
          title: 'Nepogano',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: scaffoldMessengerKey,
          theme: base.copyWith(textTheme: GoogleFonts.interTextTheme(base.textTheme)),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AuthGate(),
        );
      },
    );
  }
}

/// Слухає стан авторизації і показує або екран входу, або чек-ін
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

const _onboardingSeenKey = 'onboarding_seen';

class _AuthGateState extends State<AuthGate> {
  late final Stream<AuthState> _authStateStream;
  StreamSubscription<AuthState>? _authSub;
  bool _onboardingChecked = false;
  bool _onboardingSeen = false;

  @override
  void initState() {
    super.initState();
    _authStateStream = Supabase.instance.client.auth.onAuthStateChange;
    _authSub = _authStateStream.listen((_) => _tryPendingJoin());
    pendingJoinCode.addListener(_tryPendingJoin);
    // AppLocalizations.of(context) не можна викликати всередині initState —
    // відкладаємо першу перевірку на момент після першого кадру.
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryPendingJoin());
    _loadOnboardingSeen();
  }

  Future<void> _loadOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _onboardingSeen = prefs.getBool(_onboardingSeenKey) ?? false;
      _onboardingChecked = true;
    });
  }

  Future<void> _markOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingSeenKey, true);
    if (mounted) setState(() => _onboardingSeen = true);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    pendingJoinCode.removeListener(_tryPendingJoin);
    super.dispose();
  }

  Future<void> _tryPendingJoin() async {
    final code = pendingJoinCode.value;
    final session = Supabase.instance.client.auth.currentSession;
    if (code == null || session == null || !mounted) return;

    pendingJoinCode.value = null;
    final l10n = AppLocalizations.of(context);
    try {
      await Supabase.instance.client.rpc('join_circle_by_code', params: {'code': code});
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(l10n.joinedCircleSuccess)),
      );
    } catch (e) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(l10n.invalidInviteCode)),
      );
    }
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
        if (!_onboardingChecked) {
          return const Scaffold(backgroundColor: AppColors.background);
        }
        if (!_onboardingSeen) {
          return OnboardingScreen(onDone: _markOnboardingSeen);
        }
        return const AuthScreen();
      },
    );
  }
}

enum MoodLevel { niyak, nepogano, zbs }

extension MoodLevelData on MoodLevel {
  String label(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    switch (this) {
      case MoodLevel.niyak:
        return l10n.moodNiyak;
      case MoodLevel.nepogano:
        return l10n.moodNepogano;
      case MoodLevel.zbs:
        return l10n.moodZbs;
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
                mood.label(context),
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
  bool _hasCircleActivity = false;
  late DateTime _visibleWeekStart;

  final _supabase = Supabase.instance.client;

  static DateTime _mondayOf(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  @override
  void initState() {
    super.initState();
    _visibleWeekStart = _mondayOf(DateTime.now());
    _loadTodayEntry();
    _loadWeek();
    _checkCircleActivity();
  }

  Future<void> _checkCircleActivity() async {
    final has = await hasUnseenCircleActivity(_supabase);
    if (mounted) setState(() => _hasCircleActivity = has);
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
        .eq('user_id', _supabase.auth.currentUser!.id)
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

  bool get _isCurrentWeek => _visibleWeekStart == _mondayOf(DateTime.now());
  bool get _isPreviousWeek =>
      _visibleWeekStart == _mondayOf(DateTime.now()).subtract(const Duration(days: 7));

  void _changeWeek(int deltaWeeks) {
    final currentMonday = _mondayOf(DateTime.now());
    final next = _visibleWeekStart.add(Duration(days: 7 * deltaWeeks));
    // Лише поточний і минулий тиждень — не глибше і не в майбутнє.
    if (next.isAfter(currentMonday) || next.isBefore(currentMonday.subtract(const Duration(days: 7)))) {
      return;
    }
    setState(() => _visibleWeekStart = next);
    _loadWeek();
  }

  Future<void> _loadWeek() async {
    final start = _visibleWeekStart.toUtc().toIso8601String();
    final end = _visibleWeekStart.add(const Duration(days: 7)).toUtc().toIso8601String();

    final rows = await _supabase
        .from('checkins')
        .select('mood, note, created_at')
        .eq('user_id', _supabase.auth.currentUser!.id)
        .gte('created_at', start)
        .lt('created_at', end)
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
            content: Text(AppLocalizations.of(context).savedSnackbar(_selected!.label(context))),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).saveFailedSnackbar)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    await _supabase.auth.signOut();
  }

  void _openMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _MoreMenuSheet(
        onLanguage: () {
          Navigator.of(sheetContext).pop();
          setAppLocale(
            appLocale.value.languageCode == 'uk' ? const Locale('en') : const Locale('uk'),
          );
        },
        onSignOut: () {
          Navigator.of(sheetContext).pop();
          _signOut();
        },
        onDeleteAccount: () {
          Navigator.of(sheetContext).pop();
          _confirmDeleteAccount();
        },
      ),
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text(l10n.deleteAccountConfirmTitle),
        content: Text(l10n.deleteAccountConfirmBody),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete, style: const TextStyle(color: Colors.redAccent)),
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
          SnackBar(content: Text(AppLocalizations.of(context).deleteAccountFailedSnackbar)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const CirclesScreen()),
                              );
                              _checkCircleActivity();
                            },
                            icon: const Icon(Icons.people_outline, size: 20),
                            tooltip: l10n.circle,
                          ),
                          if (_hasCircleActivity)
                            const Positioned(
                              top: 8,
                              right: 8,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: AppColors.notification,
                                  shape: BoxShape.circle,
                                ),
                                child: SizedBox(width: 8, height: 8),
                              ),
                            ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const HistoryScreen()),
                        ),
                        icon: const Icon(Icons.calendar_month_outlined, size: 20),
                        tooltip: l10n.history,
                      ),
                      IconButton(
                        onPressed: _openMoreMenu,
                        icon: const Icon(Icons.more_vert, size: 20),
                        tooltip: l10n.moreTooltip,
                      ),
                    ],
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.howAreThingsToday,
                          style: appSerif(fontSize: 28),
                        ),
                        if (_todayEntrySavedAt != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            l10n.alreadySavedToday(
                              '${_todayEntrySavedAt!.hour.toString().padLeft(2, '0')}:'
                              '${_todayEntrySavedAt!.minute.toString().padLeft(2, '0')}',
                            ),
                            style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
                          ),
                        ],
                        const SizedBox(height: 32),
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
                                        hintText: l10n.notePlaceholder,
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
                                                _todayEntryId != null ? l10n.update : l10n.save,
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
                                          label: Text(l10n.dayCard),
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

  String _weekLabel(AppLocalizations l10n) => _isCurrentWeek ? l10n.thisWeek : l10n.previousWeek;

  Widget _buildWeekStrip() {
    final l10n = AppLocalizations.of(context);
    final today = DateTime.now();
    final days = List.generate(7, (i) => _visibleWeekStart.add(Duration(days: i)));

    final byDay = <DateTime, MoodLevel>{};
    for (final entry in _weekEntries) {
      final d = DateTime(entry.createdAt.year, entry.createdAt.month, entry.createdAt.day);
      byDay[d] = entry.mood;
    }

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -200) {
          _changeWeek(1);
        } else if (velocity > 200) {
          _changeWeek(-1);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _isPreviousWeek ? null : () => _changeWeek(-1),
                icon: const Icon(Icons.chevron_left, size: 18),
                visualDensity: VisualDensity.compact,
                color: AppColors.inkMuted,
              ),
              Text(
                _weekLabel(l10n),
                style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
              ),
              IconButton(
                onPressed: _isCurrentWeek ? null : () => _changeWeek(1),
                icon: const Icon(Icons.chevron_right, size: 18),
                visualDensity: VisualDensity.compact,
                color: AppColors.inkMuted,
              ),
            ],
          ),
          const SizedBox(height: 6),
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
      ),
    );
  }
}

class _MoreMenuSheet extends StatelessWidget {
  final VoidCallback onLanguage;
  final VoidCallback onSignOut;
  final VoidCallback onDeleteAccount;

  const _MoreMenuSheet({
    required this.onLanguage,
    required this.onSignOut,
    required this.onDeleteAccount,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MenuRow(
              icon: Icons.language,
              label: '${l10n.language}: ${appLocale.value.languageCode == 'uk' ? 'UK' : 'EN'}',
              onTap: onLanguage,
            ),
            _MenuRow(
              icon: Icons.logout,
              label: l10n.signOut,
              onTap: onSignOut,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(color: AppColors.divider, height: 1),
            ),
            _MenuRow(
              icon: Icons.delete_outline,
              label: l10n.deleteAccount,
              color: Colors.redAccent,
              onTap: onDeleteAccount,
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? AppColors.ink;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: textColor),
            const SizedBox(width: 16),
            Text(label, style: TextStyle(fontSize: 16, color: textColor)),
          ],
        ),
      ),
    );
  }
}