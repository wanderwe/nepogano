import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_screen.dart';
import 'day_card_screen.dart';
import 'friends_screen.dart';
import 'history_screen.dart';
import 'install_referrer.dart';
import 'l10n/app_localizations.dart';
import 'locale_provider.dart';
import 'onboarding_screen.dart';
import 'photo_reposition_screen.dart';
import 'photo_storage.dart';
import 'style.dart';

// TODO: встав сюди свій Project URL і anon key з Supabase (Settings → API)
const supabaseUrl = 'https://wxxvqscmalcuurhvzufl.supabase.co';
const supabaseAnonKey = 'sb_publishable_H5DIUfH_i4_Mm5VKSoAoNA__tT60BUI';

/// Показує SnackBar незалежно від того, який екран зараз активний —
/// потрібно, щоб підтвердити додавання в друзі за диплінком.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Особистий код друга з диплінку, що чекає на автора, поки той не
/// залогіниться (диплінк може прийти ще до входу в застосунок). Приймає два
/// формати: кастомна схема io.supabase.nepogano://join/<code> (працює завжди,
/// але месенджери рідко роблять її клікабельною) і справжній
/// https://nepogano.app/join/<code> (клікабельний скрізь, відкриває
/// застосунок напряму через Android App Links після верифікації домену).
final ValueNotifier<String?> pendingJoinCode = ValueNotifier<String?>(null);

void _handleJoinLink(Uri? uri) {
  if (uri == null) return;

  String? code;
  if (uri.host == 'join' && uri.pathSegments.isNotEmpty) {
    code = uri.pathSegments.first;
  } else if (uri.host == 'nepogano.app' &&
      uri.pathSegments.length >= 2 &&
      uri.pathSegments.first == 'join') {
    code = uri.pathSegments[1];
  }

  if (code != null) pendingJoinCode.value = code;
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
          theme: base.copyWith(
            textTheme: GoogleFonts.interTextTheme(base.textTheme),
          ),
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
const _installReferrerCheckedKey = 'install_referrer_checked';

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
    _checkInstallReferrer();
  }

  /// Перевіряє (лише раз за весь час життя застосунку на пристрої) Play
  /// Install Referrer — якщо застосунок щойно встановили за посиланням
  /// nepogano.app/join/<code>, коли його ще не було, код прийде саме звідси
  /// (deferred deep link). Чергу в pendingJoinCode підхоплює вже наявний
  /// _tryPendingJoin, коли юзер залогіниться.
  Future<void> _checkInstallReferrer() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_installReferrerCheckedKey) == true) return;
    await prefs.setBool(_installReferrerCheckedKey, true);

    final code = await fetchInstallReferrerJoinCode();
    if (code != null && code.isNotEmpty) {
      pendingJoinCode.value = code;
    }
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

    // Підтягуємо ім'я того, хто поділився кодом, щоб діалог підтвердження
    // називав конкретну людину, а не "хтось" — якщо не вдалось, fallback
    // на загальний варіант тексту нижче.
    String? requesterName;
    try {
      final result = await Supabase.instance.client.rpc(
        'resolve_friend_code',
        params: {'code': code},
      );
      requesterName = result as String?;
    } catch (e) {
      // ignore — покажемо загальний заголовок
    }
    if (!mounted) return;

    // Питаємо підтвердження, а не тихо додаємо в друзі одразу — це має
    // відчуватись як прийняття запиту в друзі, а не виконання коду.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text(
          requesterName != null
              ? l10n.friendRequestTitleNamed(requesterName)
              : l10n.friendRequestTitle,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.no),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.accept),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await Supabase.instance.client.rpc(
        'add_friend_by_code',
        params: {'code': code},
      );
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(l10n.friendAdded)),
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
            color: isSelected
                ? mood.color.withValues(alpha: 0.16)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: isSelected ? Border.all(color: mood.color, width: 2) : null,
          ),
          child: Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: mood.color,
                  shape: BoxShape.circle,
                ),
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

  // Фото: або вже збережений шлях (з попереднього завантаження цього дня),
  // або щойно обраний локальний файл, що чекає на завантаження при _save().
  String? _existingPhotoPath;
  File? _pickedPhotoFile;
  bool _removePhoto = false;
  double _photoAlignY = 0;

  // Якщо запис за сьогодні вже є — за замовчуванням показуємо його як
  // готовий підсумок, а не одразу активну форму. Форма з'являється тільки
  // для нового запису або коли юзер явно тисне "Редагувати".
  bool _editing = false;
  bool get _showForm => _todayEntryId == null || _editing;

  // Поки не підтверджено, чи є вже запис за сьогодні, НЕ показуємо форму —
  // інакше короткочасний мережевий збій на холодному старті (той самий
  // клас проблем, що й з фото/Google-логіном) мовчки показує "порожній"
  // екран, ніби запису немає, і є ризик створити дублікат замість оновлення.
  bool _loadingToday = true;
  bool _todayLoadFailed = false;

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
    final has = await hasUnseenFriendActivity(_supabase);
    if (mounted) setState(() => _hasCircleActivity = has);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Widget _buildTodayLoadError(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.couldNotLoadTodayEntry,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.inkMuted),
        ),
        const SizedBox(height: 12),
        TextButton(onPressed: _loadTodayEntry, child: Text(l10n.retry)),
      ],
    );
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
    setState(() {
      _loadingToday = true;
      _todayLoadFailed = false;
    });
    final (startOfDay, startOfNextDay) = _todayRangeUtc();

    try {
      final rows = await _supabase
          .from('checkins')
          .select('id, mood, note, created_at, photo_path, photo_align_y')
          .eq('user_id', _supabase.auth.currentUser!.id)
          .gte('created_at', startOfDay)
          .lt('created_at', startOfNextDay)
          .order('created_at', ascending: false)
          .limit(1);

      if (!mounted) return;

      if ((rows as List).isEmpty) {
        setState(() => _loadingToday = false);
        return;
      }

      final row = rows.first;
      setState(() {
        _todayEntryId = row['id'];
        _selected = moodFromDbValue(row['mood'] as String);
        _noteController.text = (row['note'] as String?) ?? '';
        _todayEntrySavedAt = DateTime.parse(
          row['created_at'] as String,
        ).toLocal();
        _existingPhotoPath = row['photo_path'] as String?;
        _photoAlignY = (row['photo_align_y'] as num?)?.toDouble() ?? 0;
        _pickedPhotoFile = null;
        _removePhoto = false;
        _editing = false;
        _loadingToday = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingToday = false;
          _todayLoadFailed = true;
        });
      }
    }
  }

  void _startEditing() => setState(() => _editing = true);

  void _cancelEditing() {
    setState(() {
      _pickedPhotoFile = null;
      _removePhoto = false;
    });
    _loadTodayEntry();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (picked == null || !mounted) return;

    final file = File(picked.path);
    final alignY = await Navigator.of(context).push<double>(
      MaterialPageRoute(
        builder: (_) => PhotoRepositionScreen(image: FileImage(file)),
      ),
    );
    if (!mounted) return;
    setState(() {
      _pickedPhotoFile = file;
      _photoAlignY = alignY ?? 0;
      _removePhoto = false;
    });
  }

  Future<void> _repositionPhoto(ImageProvider image) async {
    final alignY = await Navigator.of(context).push<double>(
      MaterialPageRoute(
        builder: (_) =>
            PhotoRepositionScreen(image: image, initialAlignY: _photoAlignY),
      ),
    );
    if (alignY != null && mounted) setState(() => _photoAlignY = alignY);
  }

  Future<void> _choosePhotoSource() async {
    final l10n = AppLocalizations.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surfaceRaised,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MenuRow(
                icon: Icons.photo_camera_outlined,
                label: l10n.takePhoto,
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              _MenuRow(
                icon: Icons.photo_library_outlined,
                label: l10n.chooseFromGallery,
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source != null) await _pickPhoto(source);
  }

  void _clearPhoto() {
    setState(() {
      _pickedPhotoFile = null;
      _removePhoto = _existingPhotoPath != null;
      _photoAlignY = 0;
    });
  }

  Widget _buildPhotoPicker(AppLocalizations l10n) {
    if (_pickedPhotoFile != null) {
      final image = FileImage(_pickedPhotoFile!);
      return _PhotoPreview(
        image: Image(
          image: image,
          fit: BoxFit.cover,
          alignment: Alignment(0, _photoAlignY),
        ),
        onRemove: _clearPhoto,
        onReposition: () => _repositionPhoto(image),
        removeTooltip: l10n.removePhotoTooltip,
        repositionTooltip: l10n.repositionPhotoTooltip,
      );
    }

    if (_existingPhotoPath != null && !_removePhoto) {
      return FutureBuilder<Uint8List?>(
        future: downloadCheckinPhoto(_existingPhotoPath!),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Container(
              height: 96,
              width: 96,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final image = MemoryImage(snapshot.data!);
          return _PhotoPreview(
            image: Image(
              image: image,
              fit: BoxFit.cover,
              alignment: Alignment(0, _photoAlignY),
            ),
            onRemove: _clearPhoto,
            onReposition: () => _repositionPhoto(image),
            removeTooltip: l10n.removePhotoTooltip,
            repositionTooltip: l10n.repositionPhotoTooltip,
          );
        },
      );
    }

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _choosePhotoSource,
        icon: const Icon(Icons.photo_camera_outlined, size: 18),
        label: Text(l10n.addPhoto),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.inkMuted,
          side: const BorderSide(color: AppColors.divider),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  DayCardScreen _buildDayCardScreen() {
    return DayCardScreen(
      entry: CheckinEntry(
        createdAt: _todayEntrySavedAt ?? DateTime.now(),
        mood: _selected!,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        photoPath: _existingPhotoPath,
        photoAlignY: _photoAlignY,
      ),
    );
  }

  List<Widget> _buildFormContent(AppLocalizations l10n) {
    return [
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
                  const SizedBox(height: 12),
                  _buildPhotoPicker(l10n),
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
                      child: TextButton(
                        onPressed: _saving ? null : _cancelEditing,
                        child: Text(l10n.cancel),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _buildDayCardScreen(),
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
    ];
  }

  List<Widget> _buildSummaryContent(AppLocalizations l10n) {
    return [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(
                style: appSerif(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
                children: [
                  TextSpan(text: '${l10n.todayWasPrefix} '),
                  TextSpan(
                    text: _selected!.label(context).toLowerCase(),
                    style: TextStyle(color: _selected!.color),
                  ),
                ],
              ),
            ),
            if (_noteController.text.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _noteController.text.trim(),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.inkMuted,
                  height: 1.4,
                ),
              ),
            ],
            if (_existingPhotoPath != null) ...[
              const SizedBox(height: 14),
              FutureBuilder<Uint8List?>(
                future: downloadCheckinPhoto(_existingPhotoPath!),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox(
                      height: 140,
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
                    borderRadius: BorderRadius.circular(14),
                    child: Image.memory(
                      snapshot.data!,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      alignment: Alignment(0, _photoAlignY),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _startEditing,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(l10n.edit),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            foregroundColor: AppColors.ink,
            side: const BorderSide(color: AppColors.divider),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: TextButton.icon(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => _buildDayCardScreen())),
          icon: const Icon(Icons.ios_share, size: 18),
          label: Text(l10n.dayCard),
        ),
      ),
    ];
  }

  bool get _isCurrentWeek => _visibleWeekStart == _mondayOf(DateTime.now());
  bool get _isPreviousWeek =>
      _visibleWeekStart ==
      _mondayOf(DateTime.now()).subtract(const Duration(days: 7));

  void _changeWeek(int deltaWeeks) {
    final currentMonday = _mondayOf(DateTime.now());
    final next = _visibleWeekStart.add(Duration(days: 7 * deltaWeeks));
    // Лише поточний і минулий тиждень — не глибше і не в майбутнє.
    if (next.isAfter(currentMonday) ||
        next.isBefore(currentMonday.subtract(const Duration(days: 7)))) {
      return;
    }
    setState(() => _visibleWeekStart = next);
    _loadWeek();
  }

  Future<void> _loadWeek() async {
    final start = _visibleWeekStart.toUtc().toIso8601String();
    final end = _visibleWeekStart
        .add(const Duration(days: 7))
        .toUtc()
        .toIso8601String();

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
      String? photoPath = _existingPhotoPath;
      if (_pickedPhotoFile != null) {
        photoPath = await uploadCheckinPhoto(_pickedPhotoFile!);
        if (_existingPhotoPath != null) {
          unawaited(deleteCheckinPhoto(_existingPhotoPath!));
        }
      } else if (_removePhoto) {
        if (_existingPhotoPath != null) {
          unawaited(deleteCheckinPhoto(_existingPhotoPath!));
        }
        photoPath = null;
      }

      final payload = {
        'mood': _selected!.dbValue,
        'note': _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        'photo_path': photoPath,
        'photo_align_y': photoPath == null ? 0 : _photoAlignY,
      };

      if (_todayEntryId != null) {
        final updated = await _supabase
            .from('checkins')
            .update(payload)
            .eq('id', _todayEntryId as Object)
            .select('id');
        if ((updated as List).isEmpty) {
          throw Exception(
            'Update affected 0 rows — check RLS UPDATE policy on checkins.',
          );
        }
      } else {
        final inserted = await _supabase
            .from('checkins')
            .insert(payload)
            .select('id, created_at')
            .single();
        _todayEntryId = inserted['id'];
        _todayEntrySavedAt = DateTime.parse(
          inserted['created_at'] as String,
        ).toLocal();
      }
      _existingPhotoPath = photoPath;
      _pickedPhotoFile = null;
      _removePhoto = false;
      _editing = false;
      unawaited(_loadWeek());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              ).savedSnackbar(_selected!.label(context)),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).saveFailedSnackbar),
          ),
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
            appLocale.value.languageCode == 'uk'
                ? const Locale('en')
                : const Locale('uk'),
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
            child: Text(
              l10n.delete,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    final finalConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text(l10n.deleteAccountFinalConfirmTitle),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.no),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l10n.yesDelete,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (finalConfirmed != true) return;

    try {
      await _supabase.rpc('delete_own_account');
      await _supabase.auth.signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).deleteAccountFailedSnackbar,
            ),
          ),
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
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.inkMuted,
                    ),
                  ),
                  Row(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const FriendsScreen(),
                                ),
                              );
                              _checkCircleActivity();
                            },
                            icon: const Icon(Icons.people_outline, size: 20),
                            tooltip: l10n.friends,
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
                          MaterialPageRoute(
                            builder: (_) => const HistoryScreen(),
                          ),
                        ),
                        icon: const Icon(
                          Icons.calendar_month_outlined,
                          size: 20,
                        ),
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
                  child: _loadingToday
                      ? const CircularProgressIndicator()
                      : _todayLoadFailed
                      ? _buildTodayLoadError(l10n)
                      : SingleChildScrollView(
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
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.inkMuted,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 32),
                              if (_showForm)
                                ..._buildFormContent(l10n)
                              else
                                ..._buildSummaryContent(l10n),
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

  String _weekLabel(AppLocalizations l10n) =>
      _isCurrentWeek ? l10n.thisWeek : l10n.previousWeek;

  Widget _buildWeekStrip() {
    final l10n = AppLocalizations.of(context);
    final today = DateTime.now();
    final days = List.generate(
      7,
      (i) => _visibleWeekStart.add(Duration(days: i)),
    );

    final byDay = <DateTime, MoodLevel>{};
    for (final entry in _weekEntries) {
      final d = DateTime(
        entry.createdAt.year,
        entry.createdAt.month,
        entry.createdAt.day,
      );
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
              final isToday =
                  d.year == today.year &&
                  d.month == today.month &&
                  d.day == today.day;

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
                        : (isToday
                              ? Border.all(color: AppColors.ink, width: 1.5)
                              : null),
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
              label:
                  '${l10n.language}: ${appLocale.value.languageCode == 'uk' ? 'UK' : 'EN'}',
              onTap: onLanguage,
            ),
            _MenuRow(icon: Icons.logout, label: l10n.signOut, onTap: onSignOut),
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

class _PhotoPreview extends StatelessWidget {
  final Widget image;
  final VoidCallback onRemove;
  final VoidCallback onReposition;
  final String removeTooltip;
  final String repositionTooltip;

  const _PhotoPreview({
    required this.image,
    required this.onRemove,
    required this.onReposition,
    required this.removeTooltip,
    required this.repositionTooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 140,
            width: double.infinity,
            child: GestureDetector(onTap: onReposition, child: image),
          ),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: onReposition,
              icon: const Icon(Icons.open_with, size: 16, color: Colors.white),
              tooltip: repositionTooltip,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 16, color: Colors.white),
              tooltip: removeTooltip,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
      ],
    );
  }
}
