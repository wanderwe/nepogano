import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_screen.dart';
import 'comment_activity.dart';
import 'comment_activity_screen.dart';
import 'comments_section.dart';
import 'daily_reminder.dart';
import 'date_labels.dart';
import 'day_card_screen.dart';
import 'friends_screen.dart';
import 'history_screen.dart';
import 'install_referrer.dart';
import 'l10n/app_localizations.dart';
import 'locale_provider.dart';
import 'onboarding_screen.dart';
import 'photo_reposition_screen.dart';
import 'photo_storage.dart';
import 'profile_screen.dart';
import 'style.dart';
import 'time_capsules_screen.dart';

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
  // Свідомо НІЧОГО важкого/асинхронного тут більше нема — нативний splash
  // має змінитись на щось Flutter-намальоване якнайшвидше. Уся ініціалізація
  // (локаль, нагадування, Supabase) переїхала в _AppBootstrap, що виконується
  // вже ПІСЛЯ runApp(), з видимим індикатором завантаження і кнопкою "ще раз"
  // при невдачі — а не блокує сам запуск, як було раніше (саме це залишало
  // тестувальника на чорному екрані з лого назавжди, якщо мережа на його
  // пристрої "тихо зависала" замість швидкої помилки).
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
      // Material 3 малює стандартний SnackBar кольором inverseSurface — на
      // темній темі це світлий бар, який випадає з решти дизайну. Один
      // спільний стиль тут покриває всі виклики SnackBar по застосунку.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceRaised,
        contentTextStyle: const TextStyle(color: AppColors.ink, fontSize: 14),
        actionTextColor: AppColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      // Без цього дефолтний колір іконки в Material 3 — colorScheme.onSurfaceVariant,
      // похідний від бурштинового colorSchemeSeed (тому іконки виходили теплуватими/
      // бежевими), тоді як текст типу дати навмисно use AppColors.inkMuted (чистий
      // сірий) — розбіжність тону. Один нейтральний сірий для всіх іконок за замовчуванням.
      iconTheme: const IconThemeData(color: AppColors.inkMuted),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: AppColors.inkMuted),
      ),
      // Раніше кожен екран мав власну кнопкову мову: біла ElevatedButton тут,
      // бурштинова FilledButton у попапах, OutlinedButton з іншим радіусом там.
      // Один стиль на кожен рівень ваги (primary/secondary/tertiary) — і його
      // більше не треба повторювати в кожному .styleFrom() окремо.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.accentInk,
          disabledBackgroundColor: AppColors.surface,
          disabledForegroundColor: AppColors.inkMuted,
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.inkMuted,
          side: const BorderSide(color: AppColors.divider),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.inkMuted),
      ),
      // Жодна з ~8 модальних шторок застосунку не мала "ручки" зверху —
      // сучасний сигнал "це можна закрити свайпом", який зараз є стандартом
      // (iOS action sheets, Material 3). Один параметр тут — і вона з'являється
      // всюди, без правок у кожному виклику showModalBottomSheet окремо.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surfaceRaised,
        showDragHandle: true,
        dragHandleColor: AppColors.inkMuted,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      // Без цього довге натискання на IconButton.tooltip показує сирий
      // Material-дефолт (простий білий/чорний прямокутник), який випадає з
      // решти застосунку так само, як SnackBar до свого власного стилю вище.
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(color: AppColors.ink, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );

    return ValueListenableBuilder<Locale>(
      valueListenable: appLocale,
      builder: (context, locale, _) {
        return MaterialApp(
          title: 'Nepogano',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: scaffoldMessengerKey,
          // Inter вшита локально (assets/fonts/), не через
          // GoogleFonts.interTextTheme — той самий фікс, що для Lora в
          // appSerif(): мережеве довантаження при першому запуску викликало
          // видиму зміну розміру тексту по всьому застосунку, не лише на
          // заголовках.
          theme: base.copyWith(
            textTheme: base.textTheme.apply(fontFamily: 'Inter'),
          ),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const _AppBootstrap(),
        );
      },
    );
  }
}

enum _BootstrapStatus { loading, error, ready }

/// Виконує всю асинхронну підготовку (локаль, нагадування, Supabase) вже
/// ПІСЛЯ того, як щось Flutter-намальоване з'явилось на екрані — на відміну
/// від старої версії, де все це чекалось у main() до runApp(), і будь-яке
/// зависання (найчастіше — мережа Supabase.initialize на конкретному
/// пристрої) лишало юзера на чорному нативному splash-екрані назавжди, без
/// жодного індикатора чи можливості повторити спробу.
class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  _BootstrapStatus _status = _BootstrapStatus.loading;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _status = _BootstrapStatus.loading);

    await loadSavedLocale();

    // Нагадування о 20:00 не критичне для того, щоб узагалі побачити
    // застосунок — якщо нативний плагін сповіщень зависне чи впаде на
    // якомусь пристрої, просто йдемо далі без нього.
    try {
      await initDailyReminder().timeout(const Duration(seconds: 5));
    } catch (_) {}

    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
        // На деяких пристроях перший мережевий запит після старту застосунку
        // іноді ловить короткочасну DNS-помилку (SocketException: Failed
        // host lookup), навіть коли мережа в порядку — і Dart-рівень не
        // ретраїть це сам. Обгортаємо HTTP-клієнт автоматичним retry на такі
        // помилки для всіх запитів Supabase.
        httpClient: RetryClient(
          http.Client(),
          retries: 5,
          delay: (retryCount) => Duration(milliseconds: 500 * (retryCount + 1)),
          whenError: (error, stackTrace) => error is SocketException,
        ),
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      if (mounted) setState(() => _status = _BootstrapStatus.error);
      return;
    }

    final appLinks = AppLinks();
    unawaited(appLinks.getInitialLink().then(_handleJoinLink));
    appLinks.uriLinkStream.listen(_handleJoinLink);

    if (mounted) setState(() => _status = _BootstrapStatus.ready);
  }

  @override
  Widget build(BuildContext context) {
    if (_status == _BootstrapStatus.ready) return const AuthGate();

    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: _status == _BootstrapStatus.loading
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.connectionFailedTitle,
                      textAlign: TextAlign.center,
                      style: appScreenTitle(fontSize: 20),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.connectionFailedBody,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.inkMuted),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(onPressed: _init, child: Text(l10n.retry)),
                  ],
                ),
              ),
      ),
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
const _dailyReminderScheduledDateKey = 'daily_reminder_scheduled_date';
const _subjectIntroSeenKey = 'subject_intro_seen';

class _AuthGateState extends State<AuthGate> {
  late final Stream<AuthState> _authStateStream;
  StreamSubscription<AuthState>? _authSub;
  bool _onboardingChecked = false;
  bool _onboardingSeen = false;

  @override
  void initState() {
    super.initState();
    _authStateStream = Supabase.instance.client.auth.onAuthStateChange;
    _authSub = _authStateStream.listen((_) {
      _tryPendingJoin();
      _setupDailyReminder();
    });
    pendingJoinCode.addListener(_tryPendingJoin);
    // AppLocalizations.of(context) не можна викликати всередині initState —
    // відкладаємо першу перевірку на момент після першого кадру.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryPendingJoin();
      _setupDailyReminder();
    });
    _loadOnboardingSeen();
    _checkInstallReferrer();
  }

  /// Питає дозвіл і планує щоденне нагадування о 20:00 — і тільки коли вже є
  /// активна сесія (питати дозвіл на сповіщення ще до логіну зарано, юзер
  /// ще навіть не бачив застосунок).
  ///
  /// Раніше це робилось лише РАЗ за все життя застосунку на пристрої — але
  /// flutter_local_notifications не реєструє власний receiver для
  /// перепланування після перезавантаження телефону (Android стирає
  /// заплановані через AlarmManager нагадування при кожному ребуті), а
  /// "вже заплановано" ставилось назавжди. Тобто після першого ж ребуту
  /// нагадування зникало з системи без жодного шансу відновитись. Тепер
  /// перепланування самовідновлюване — раз на календарний день (не при
  /// кожному відкритті застосунку чи oновленні токена, це було б
  /// надлишково): якщо телефон перезавантажили, наступне ж відкриття
  /// застосунку того самого дня знову освіжить alarm. Дозвіл повторно НЕ
  /// перепитується — Android/iOS не показують діалог вдруге, якщо він уже
  /// один раз вирішений.
  Future<void> _setupDailyReminder() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null || !mounted) return;

    final today = DateTime.now().toIso8601String().split('T').first;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_dailyReminderScheduledDateKey) == today) return;

    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final scheduled = await scheduleDailyReminder(
      title: l10n.dailyReminderTitle,
      body: l10n.dailyReminderBody,
    );
    if (scheduled) {
      await prefs.setString(_dailyReminderScheduledDateKey, today);
    }
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
      builder: (context) => AppDialog(
        title: requesterName != null
            ? l10n.friendRequestTitleNamed(requesterName)
            : l10n.friendRequestTitle,
        primaryLabel: l10n.accept,
        onPrimary: () => Navigator.of(context).pop(true),
        secondaryLabel: l10n.no,
        onSecondary: () => Navigator.of(context).pop(false),
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

/// Кнопка вибору настрою для гри-вгадування (`PersonDetailScreen`,
/// `SubjectDetailScreen`) — навмисно заповнена кольором, з крапкою й
/// анімацією натискання, а не голий `OutlinedButton` з тонкою рамкою: той
/// самий візуальний "почерк", що й `_MoodTile` вище, який юзер уже знає як
/// "тапни тут, щоб обрати настрій". Розбіжність у стилі раніше означала,
/// що кнопки вгадування виглядали як пасивні лейбли, не як інтерактивний
/// вибір — імовірна причина, чому частина юзерів постить власні чек-іни,
/// але жодного разу не пробувала вгадати друга.
class GuessMoodButton extends StatefulWidget {
  final MoodLevel mood;
  final VoidCallback onTap;

  const GuessMoodButton({super.key, required this.mood, required this.onTap});

  @override
  State<GuessMoodButton> createState() => _GuessMoodButtonState();
}

class _GuessMoodButtonState extends State<GuessMoodButton> {
  bool _pressed = false;

  void _setPressed(bool value) => setState(() => _pressed = value);

  @override
  Widget build(BuildContext context) {
    final mood = widget.mood;
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: mood.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
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
                mood.label(context),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubjectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final IconData? leadingIcon;

  const _SubjectChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.leadingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: AppChip(
        label: label,
        selected: selected,
        onTap: onTap,
        onLongPress: onLongPress,
        leadingIcon: leadingIcon,
      ),
    );
  }
}

/// Сутність (дитина/улюбленець/інше), яку веде власник акаунту тим самим
/// ритуалом чек-іну, що й для себе — повністю приватний щоденник, без
/// видимості друзям чи колам.
class Subject {
  final String id;
  final String kind;
  final String name;
  // Власник керує співавторами/колами-перегляду/перейменуванням/видаленням;
  // співавтор може лише читати й писати чек-іни.
  final bool isOwner;
  // Тільки для співавторів — ім'я власника, щоб показати "хто веде щоденник"
  // при довгому тапі замість порожньої, незрозумілої відсутності меню.
  final String? ownerName;

  Subject({
    required this.id,
    required this.kind,
    required this.name,
    required this.isOwner,
    this.ownerName,
  });
}

class CheckInScreen extends StatefulWidget {
  const CheckInScreen({super.key});

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen>
    with WidgetsBindingObserver {
  MoodLevel? _selected;
  final TextEditingController _noteController = TextEditingController();
  bool _saving = false;
  Object? _todayEntryId;
  DateTime? _todayEntrySavedAt;
  List<CheckinEntry> _weekEntries = [];
  bool _hasCircleActivity = false;
  // Наскрізний сигнал — новий коментар на будь-якому МОЄМУ дні АБО
  // відповідь на МІЙ коментар під чужим, тому й не прив'язаний до
  // конкретного щоденника і не перераховується при перемиканні. Раніше
  // тут ще був окремий _hasUnseenComments (крапка на іконці "Історія" +
  // крапки на конкретних днях у календарі) — прибрано, бо стрічка
  // "Коментарі" вже показує ці самі події, дублювати сигнал нема сенсу.
  bool _hasCommentActivity = false;
  PendingNudges? _pendingNudges;
  // На відміну від _pendingNudges це не "востаннє бачене", а справжній
  // стан (unlock_at минув, opened_at ще null) — тому немає окремого
  // "позначити побаченим назавжди": закриття банера ховає його лише на
  // цю сесію, він з'явиться знову при наступному відкритті, поки юзер
  // реально не відкриє лист.
  int _pendingUnlockedLetters = 0;
  bool _lettersBannerDismissed = false;
  late DateTime _visibleWeekStart;

  // Фото: або вже збережений шлях (з попереднього завантаження цього дня),
  // або щойно обраний локальний файл, що чекає на завантаження при _save().
  String? _existingPhotoPath;
  File? _pickedPhotoFile;
  bool _removePhoto = false;
  double _photoAlignY = 0;
  double _photoScale = 1;

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

  // Скільки разів сьогоднішній запис уже редагували (перший save не
  // рахується — тільки повторні "Оновити"). Сам інкремент — тригер у БД,
  // тут просто відображаємо те, що прийшло, і бампаємо локально одразу
  // після успішного _save(), щоб не чекати повторного запиту.
  int _updateCount = 0;

  // Хто написав сьогоднішній запис сутності — актуально лише коли в
  // щоденника кілька співавторів; для власного checkins завжди null (і так
  // очевидно, що це я).
  String? _authorName;

  // Сутності (дитина/улюбленець/інше) — той самий екран/ритуал, просто
  // перемкнутий на іншого адресата. null = веду власний чек-ін.
  List<Subject> _subjects = [];
  String? _activeSubjectId;

  String get _table =>
      _activeSubjectId == null ? 'checkins' : 'subject_checkins';
  String get _idColumn => _activeSubjectId == null ? 'user_id' : 'subject_id';
  String get _idValue => _activeSubjectId ?? _supabase.auth.currentUser!.id;

  final _supabase = Supabase.instance.client;

  static DateTime _mondayOf(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _visibleWeekStart = _mondayOf(DateTime.now());
    _loadTodayEntry();
    _loadWeek();
    _checkAllActivityOnLoad();
    _loadSubjects();
    _loadPendingNudges();
    _loadPendingUnlockedLetters();
  }

  Future<void> _loadPendingNudges() async {
    final nudges = await loadPendingNudges(_supabase);
    if (mounted) setState(() => _pendingNudges = nudges);
  }

  Future<void> _dismissNudgeBanner() async {
    setState(() => _pendingNudges = null);
    await markNudgesSeen();
  }

  /// Тап на сам банер (не на ✕) — показує, хто саме поштовхнув, а не лише
  /// "X і ще N друзів". Раніше ці N імен просто не зберігались після
  /// підрахунку count.
  ///
  /// Тап на конкретне ім'я веде на профіль цього друга й НЕ позначає банер
  /// переглянутим — інакше після переходу до першого з кількох людей решта
  /// імен ставали недоступні (банер уже зник би). Переглянутим банер
  /// вважається лише тоді, коли шторку закрили самі (свайп/тап повз),
  /// не обираючи нікого конкретного.
  Future<void> _showNudgeList() async {
    final l10n = AppLocalizations.of(context);
    final nudges = _pendingNudges;
    if (nudges == null) return;
    final tappedUserId = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.nudgeListTitle, style: appScreenTitle(fontSize: 18)),
              const SizedBox(height: 12),
              for (final person in nudges.from)
                InkWell(
                  onTap: () => Navigator.of(context).pop(person.userId),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 4,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          PhosphorIconsLight.handWaving,
                          size: 18,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          person.name.isEmpty
                              ? l10n.unnamedFriend
                              : person.name,
                          style: const TextStyle(fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (!mounted) return;
    if (tappedUserId != null) {
      final person = nudges.from.firstWhere((p) => p.userId == tappedUserId);
      // displayEmail лишається порожнім (немає звідки взяти email для
      // цього флоу) — тому displayName підставляємо явно, з фолбеком, а не
      // покладаємось на внутрішній fallback PersonDetailScreen на
      // displayEmail (він теж був би порожнім, тайтл вийшов би пустий).
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PersonDetailScreen(
            userId: person.userId,
            displayEmail: '',
            displayName: person.name.isEmpty ? l10n.unnamedFriend : person.name,
          ),
        ),
      );
    } else {
      setState(() => _pendingNudges = null);
      await markNudgesSeen();
    }
  }

  // Три різні приводи для індикатора на "Капсули часу": лист розкрився і
  // чекає на прочитання (unlock_at минув, МІЙ *_opened_at ще null), АБО
  // друг щойно надіслав новий запечатаний лист, який я ще не бачив у
  // списку (recipient_seen_at null) — це може статись задовго до unlock_at.
  // Гілка "автор не прочитав" звужена лише до листів СОБІ (recipient_id
  // null) — інакше автор, що просто не перечитує вже НАДІСЛАНИЙ другові
  // лист (той однаково більше не зміниться і не потребує його уваги),
  // назавжди тримав би бейдж увімкненим на власних старих листах. Кожна
  // гілка додатково звіряє відповідний *_deleted_at is null — лист,
  // видалений зі свого боку, не повинен більше рахуватись у бейджі навіть
  // якщо *_opened_at чомусь так і лишився null (як у листів, створених ще
  // до розділення на author_opened_at/recipient_opened_at).
  Future<void> _loadPendingUnlockedLetters() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;
    final rows = await _supabase
        .from('future_letters')
        .select('id')
        .or(
          'and(unlock_at.lte.$now,author_id.eq.$myId,recipient_id.is.null,author_opened_at.is.null,author_deleted_at.is.null),'
          'and(unlock_at.lte.$now,recipient_id.eq.$myId,recipient_opened_at.is.null,recipient_deleted_at.is.null),'
          'and(recipient_id.eq.$myId,recipient_seen_at.is.null,recipient_deleted_at.is.null)',
        );
    if (mounted)
      setState(() => _pendingUnlockedLetters = (rows as List).length);
  }

  Future<void> _loadSubjects() async {
    final myId = _supabase.auth.currentUser!.id;

    final ownRows = await _supabase
        .from('subjects')
        .select('id, kind, name')
        .eq('owner_id', myId)
        .order('created_at');

    // Сутності, де я не власник, а лише доданий співавтор — той самий
    // перемикач нагорі, та сама можливість писати чек-іни. Тягнемо ще й
    // owner_id — довгий тап у співавтора показує інфо-шторку "хто веде",
    // а не порожню відсутність меню.
    final coauthorRows = await _supabase
        .from('subject_coauthors')
        .select('subjects(id, kind, name, owner_id)')
        .eq('coauthor_user_id', myId);

    final coauthorSubjects = (coauthorRows as List)
        .map((r) => r['subjects'] as Map<String, dynamic>?)
        .whereType<Map<String, dynamic>>()
        .toList();

    final ownerIds = coauthorSubjects
        .map((s) => s['owner_id'] as String)
        .toSet()
        .toList();
    var ownerNameById = <String, String?>{};
    if (ownerIds.isNotEmpty) {
      final ownerRows = await _supabase
          .from('profiles')
          .select('user_id, display_name')
          .inFilter('user_id', ownerIds);
      ownerNameById = {
        for (final row in ownerRows as List)
          row['user_id'] as String: row['display_name'] as String?,
      };
    }

    if (!mounted) return;
    setState(() {
      final own = (ownRows as List).map(
        (r) => Subject(
          id: r['id'],
          kind: r['kind'],
          name: r['name'],
          isOwner: true,
        ),
      );
      final coauthored = coauthorSubjects.map(
        (s) => Subject(
          id: s['id'],
          kind: s['kind'],
          name: s['name'],
          isOwner: false,
          ownerName: ownerNameById[s['owner_id']],
        ),
      );
      _subjects = [...own, ...coauthored];
    });
  }

  Future<void> _checkCircleActivity() async {
    final has = await hasUnseenFriendActivity(_supabase);
    if (mounted) setState(() => _hasCircleActivity = has);
  }

  Future<void> _checkCommentActivity() async {
    final has = await hasUnseenCommentActivity(_supabase);
    if (mounted) setState(() => _hasCommentActivity = has);
  }

  /// Лише для першого завантаження екрана — два незалежні бейджі-крапки
  /// інакше з'являлись по черзі, коли готовий кожен окремий запит (і той,
  /// що тягне коментарі, довше за інші), і це виглядало як "довантаження"
  /// замість одного стабільного стану. Тут обидва чекаються разом і
  /// показуються одним setState. Рефреш після повернення з конкретного
  /// екрана (наприклад Друзів) лишається окремим викликом — там ефект
  /// довантаження не заважає, бо це вже не перший кадр застосунку.
  Future<void> _checkAllActivityOnLoad() async {
    final results = await Future.wait([
      hasUnseenFriendActivity(_supabase),
      hasUnseenCommentActivity(_supabase),
    ]);
    if (!mounted) return;
    setState(() {
      _hasCircleActivity = results[0];
      _hasCommentActivity = results[1];
    });
  }

  /// Перемикає, за кого зараз ведеться чек-ін (null = я сам) — той самий
  /// екран, скидається тільки локальний стан форми, тоді підвантажується
  /// сьогоднішній запис і тиждень для нового адресата.
  void _switchSubject(String? id) {
    setState(() {
      _activeSubjectId = id;
      _selected = null;
      _noteController.text = '';
      _todayEntryId = null;
      _todayEntrySavedAt = null;
      _existingPhotoPath = null;
      _pickedPhotoFile = null;
      _removePhoto = false;
      _photoAlignY = 0;
      _photoScale = 1;
      _updateCount = 0;
      _authorName = null;
      _editing = false;
    });
    _loadTodayEntry();
    _loadWeek();
  }

  /// Перше натискання "+" за весь час на цьому пристрої — одноразово
  /// пояснює всю механіку (особистий щоденник видно всім друзям, цей
  /// приватний, коло=перегляд, співавтор=редагування) перед самим
  /// створенням. Раз, повністю, і не повторюється — на відміну від
  /// постійного підпису в діалозі створення (забирали, бо заважав швидко
  /// прийняти рішення щоразу) чи підзаголовків у меню шеру (не рятує,
  /// якщо саме меню ніхто не знаходить). Прапорець на пристрій, той самий
  /// підхід, що й [_onboardingSeenKey].
  Future<void> _onCreateSubjectTap() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_subjectIntroSeenKey) ?? false;
    if (!seen) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AppDialog(
          title: l10n.subjectIntroTitle,
          content: Text(
            l10n.subjectIntroBody,
            style: const TextStyle(color: AppColors.inkMuted, height: 1.4),
          ),
          primaryLabel: l10n.gotIt,
          onPrimary: () => Navigator.of(context).pop(true),
          secondaryLabel: l10n.cancel,
          onSecondary: () => Navigator.of(context).pop(false),
        ),
      );
      // Прапорець ставимо лише при реальному "Зрозуміло" — "Скасувати" не
      // повинно назавжди ховати пояснення, яке юзер фактично не прийняв
      // (міг просто передумати в цю мить, не встигнувши прочитати).
      if (proceed != true) return;
      await prefs.setBool(_subjectIntroSeenKey, true);
    }
    if (mounted) await _createSubject();
  }

  Future<void> _createSubject() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    // Поза StatefulBuilder.builder — інакше кожен setState перестворював би
    // цю змінну заново й скидав вибір назад на 'child'.
    var kind = 'child';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AppDialog(
            title: l10n.newSubject,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: appFieldDecoration(l10n.subjectNameHint),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppChip(
                      label: l10n.subjectKindChild,
                      selected: kind == 'child',
                      onTap: () => setState(() => kind = 'child'),
                    ),
                    AppChip(
                      label: l10n.subjectKindPet,
                      selected: kind == 'pet',
                      onTap: () => setState(() => kind = 'pet'),
                    ),
                    AppChip(
                      label: l10n.subjectKindPartner,
                      selected: kind == 'partner',
                      onTap: () => setState(() => kind = 'partner'),
                    ),
                    AppChip(
                      label: l10n.subjectKindOther,
                      selected: kind == 'other',
                      onTap: () => setState(() => kind = 'other'),
                    ),
                  ],
                ),
              ],
            ),
            primaryLabel: l10n.create,
            onPrimary: controller.text.trim().isEmpty
                ? null
                : () => Navigator.of(
                    context,
                  ).pop({'name': controller.text.trim(), 'kind': kind}),
            secondaryLabel: l10n.cancel,
            onSecondary: () => Navigator.of(context).pop(),
          );
        },
      ),
    );

    if (result == null) return;

    try {
      final inserted = await _supabase
          .from('subjects')
          .insert({
            'owner_id': _supabase.auth.currentUser!.id,
            'name': result['name'],
            'kind': result['kind'],
          })
          .select('id')
          .single();
      await _loadSubjects();
      _switchSubject(inserted['id'] as String);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).couldNotCreateSubject),
          ),
        );
      }
    }
  }

  Future<void> _removeSubject(Subject subject) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: l10n.removeSubjectConfirmTitle(subject.name),
        content: Text(
          l10n.removeSubjectConfirmBody,
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
      await _supabase.from('subjects').delete().eq('id', subject.id);
      if (_activeSubjectId == subject.id) _switchSubject(null);
      await _loadSubjects();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).couldNotRemoveSubject),
          ),
        );
      }
    }
  }

  Future<void> _openSubjectMenu(Subject subject) async {
    final l10n = AppLocalizations.of(context);

    // Співавтор не керує щоденником (перейменування/шер/видалення) — замість
    // порожньої відсутності меню (як було раніше) показуємо, хто ним керує,
    // що сам співавтор може робити, і даємо реальний вихід — інакше щоденник,
    // доданий власником, назавжди лишався б у перемикача без жодного способу
    // його прибрати.
    if (!subject.isOwner) {
      final ownerName = subject.ownerName ?? l10n.someone;
      final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(subject.name, style: appScreenTitle(fontSize: 18)),
                const SizedBox(height: 8),
                Text(
                  l10n.coauthorInfoBody(ownerName),
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.inkMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                _MenuRow(
                  icon: PhosphorIconsLight.signOut,
                  label: l10n.leaveCoauthoredDiary,
                  color: Colors.redAccent,
                  onTap: () => Navigator.of(context).pop('leave'),
                ),
              ],
            ),
          ),
        ),
      );
      if (choice == 'leave') await _leaveCoauthoredDiary(subject);
      return;
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MenuRow(
                icon: PhosphorIconsLight.pencilSimple,
                label: l10n.renameDiary,
                onTap: () => Navigator.of(context).pop('rename'),
              ),
              _MenuRow(
                icon: PhosphorIconsLight.circlesThreePlus,
                label: l10n.shareWithCircle,
                onTap: () => Navigator.of(context).pop('share'),
              ),
              _MenuRow(
                icon: PhosphorIconsLight.userPlus,
                label: l10n.addCoauthor,
                onTap: () => Navigator.of(context).pop('coauthor'),
              ),
              _MenuRow(
                icon: PhosphorIconsLight.trash,
                label: l10n.deleteDiary,
                color: Colors.redAccent,
                onTap: () => Navigator.of(context).pop('delete'),
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == 'rename') {
      await _renameSubject(subject);
    } else if (choice == 'share') {
      await _shareSubjectWithFolders(subject);
    } else if (choice == 'coauthor') {
      await _manageCoauthors(subject);
    } else if (choice == 'delete') {
      await _removeSubject(subject);
    }
  }

  Future<void> _leaveCoauthoredDiary(Subject subject) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: l10n.leaveCoauthoredDiaryConfirmTitle(subject.name),
        content: Text(
          l10n.leaveCoauthoredDiaryConfirmBody(
            subject.ownerName ?? l10n.someone,
          ),
          style: const TextStyle(color: AppColors.inkMuted),
        ),
        primaryLabel: l10n.cancel,
        onPrimary: () => Navigator.of(context).pop(false),
        secondaryLabel: l10n.leaveCoauthoredDiary,
        secondaryColor: Colors.redAccent,
        onSecondary: () => Navigator.of(context).pop(true),
      ),
    );
    if (confirmed != true) return;

    try {
      await _supabase
          .from('subject_coauthors')
          .delete()
          .eq('subject_id', subject.id)
          .eq('coauthor_user_id', _supabase.auth.currentUser!.id);
      if (_activeSubjectId == subject.id) _switchSubject(null);
      await _loadSubjects();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).couldNotLeaveCoauthoredDiary,
            ),
          ),
        );
      }
    }
  }

  Future<void> _renameSubject(Subject subject) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: subject.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AppDialog(
          title: l10n.renameDiary,
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: appFieldDecoration(l10n.subjectNameHint),
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

    if (name == null || name.isEmpty || name == subject.name) return;

    try {
      await _supabase
          .from('subjects')
          .update({'name': name})
          .eq('id', subject.id);
      await _loadSubjects();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).couldNotRenameSubject),
          ),
        );
      }
    }
  }

  Future<void> _shareSubjectWithFolders(Subject subject) async {
    final l10n = AppLocalizations.of(context);
    final myId = _supabase.auth.currentUser!.id;

    final folderRows = await _supabase
        .from('friend_folders')
        .select('id, name')
        .eq('owner_id', myId)
        .order('created_at');
    final folders = (folderRows as List)
        .map((r) => (id: r['id'] as String, name: r['name'] as String))
        .toList();

    if (!mounted) return;

    if (folders.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.noFoldersYetForSharing)));
      return;
    }

    final shareRows = await _supabase
        .from('subject_folder_shares')
        .select('folder_id')
        .eq('subject_id', subject.id);
    final selected = (shareRows as List)
        .map((r) => r['folder_id'] as String)
        .toSet();

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.shareSubjectTitle(subject.name),
                  style: appScreenTitle(fontSize: 18),
                ),
                const SizedBox(height: 12),
                ...folders.map((folder) {
                  final checked = selected.contains(folder.id);
                  return CheckboxListTile(
                    value: checked,
                    onChanged: (value) async {
                      if (value == true) {
                        selected.add(folder.id);
                        await _supabase.from('subject_folder_shares').insert({
                          'subject_id': subject.id,
                          'folder_id': folder.id,
                        });
                      } else {
                        selected.remove(folder.id);
                        await _supabase
                            .from('subject_folder_shares')
                            .delete()
                            .eq('subject_id', subject.id)
                            .eq('folder_id', folder.id);
                      }
                      setSheetState(() {});
                    },
                    title: Text(folder.name),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _manageCoauthors(Subject subject) async {
    final l10n = AppLocalizations.of(context);
    final myId = _supabase.auth.currentUser!.id;

    final friendshipRows = await _supabase
        .from('friendships')
        .select('requester_id, requester_email, addressee_id, addressee_email')
        .or('requester_id.eq.$myId,addressee_id.eq.$myId')
        .eq('status', 'accepted');

    final friendIds = <String>[];
    final friendEmailById = <String, String>{};
    for (final row in friendshipRows as List) {
      final isRequester = row['requester_id'] == myId;
      final friendId = isRequester
          ? row['addressee_id'] as String?
          : row['requester_id'] as String;
      final friendEmail = isRequester
          ? row['addressee_email'] as String
          : row['requester_email'] as String;
      if (friendId != null) {
        friendIds.add(friendId);
        friendEmailById[friendId] = friendEmail;
      }
    }

    if (!mounted) return;

    if (friendIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.noFriendsToAddAsCoauthor)));
      return;
    }

    final nameRows = await _supabase
        .from('profiles')
        .select('user_id, display_name')
        .inFilter('user_id', friendIds);
    final nameById = <String, String?>{
      for (final row in nameRows as List)
        row['user_id'] as String: row['display_name'] as String?,
    };

    final friends =
        friendIds
            .map(
              (id) => (
                id: id,
                name: nameById[id] ?? friendEmailById[id]!.split('@').first,
              ),
            )
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );

    final coauthorRows = await _supabase
        .from('subject_coauthors')
        .select('coauthor_user_id')
        .eq('subject_id', subject.id);
    final selected = (coauthorRows as List)
        .map((r) => r['coauthor_user_id'] as String)
        .toSet();

    if (!mounted) return;

    final searchController = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final query = searchController.text.trim().toLowerCase();
          final visible = query.isEmpty
              ? friends
              : friends
                    .where((f) => f.name.toLowerCase().contains(query))
                    .toList();

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.coauthorsTitle(subject.name),
                      style: appScreenTitle(fontSize: 18),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: searchController,
                      decoration: appFieldDecoration(l10n.searchFriendHint),
                      onChanged: (_) => setSheetState(() {}),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: visible.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                l10n.noFriendsFoundForSearch,
                                style: const TextStyle(
                                  color: AppColors.inkMuted,
                                ),
                              ),
                            )
                          : ListView(
                              shrinkWrap: true,
                              children: visible.map((friend) {
                                final checked = selected.contains(friend.id);
                                return CheckboxListTile(
                                  value: checked,
                                  onChanged: (value) async {
                                    if (value == true) {
                                      selected.add(friend.id);
                                      await _supabase
                                          .from('subject_coauthors')
                                          .insert({
                                            'subject_id': subject.id,
                                            'coauthor_user_id': friend.id,
                                          });
                                    } else {
                                      selected.remove(friend.id);
                                      await _supabase
                                          .from('subject_coauthors')
                                          .delete()
                                          .eq('subject_id', subject.id)
                                          .eq('coauthor_user_id', friend.id);
                                    }
                                    setSheetState(() {});
                                  },
                                  title: Text(friend.name),
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                );
                              }).toList(),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _noteController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Юзер міг отримати новий коментар, вгадування друга чи капсулу часу,
    // поки застосунок був у фоні — усі три індикатори інакше оновлюються
    // лише при холодному старті чи поверненні саме з відповідного екрана,
    // не живо.
    if (state == AppLifecycleState.resumed) {
      _checkAllActivityOnLoad();
      _loadPendingUnlockedLetters();
    }
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
      final columns =
          'id, mood, note, created_at, photo_path, photo_align_y, photo_scale, update_count'
          '${_activeSubjectId != null ? ', author_id' : ''}';
      final rows = await _supabase
          .from(_table)
          .select(columns)
          .eq(_idColumn, _idValue)
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

      String? authorName;
      final authorId = row['author_id'] as String?;
      if (authorId != null) {
        authorName = authorId == _supabase.auth.currentUser!.id
            ? null // сам собі підпис не показуємо
            : await _resolveDisplayName(authorId);
      }
      if (!mounted) return;

      setState(() {
        _todayEntryId = row['id'];
        _selected = moodFromDbValue(row['mood'] as String);
        _noteController.text = (row['note'] as String?) ?? '';
        _todayEntrySavedAt = DateTime.parse(
          row['created_at'] as String,
        ).toLocal();
        _existingPhotoPath = row['photo_path'] as String?;
        _photoAlignY = (row['photo_align_y'] as num?)?.toDouble() ?? 0;
        _photoScale = (row['photo_scale'] as num?)?.toDouble() ?? 1;
        _updateCount = (row['update_count'] as num?)?.toInt() ?? 0;
        _authorName = authorName;
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

  Future<String?> _resolveDisplayName(String userId) async {
    final row = await _supabase
        .from('profiles')
        .select('display_name')
        .eq('user_id', userId)
        .maybeSingle();
    return row?['display_name'] as String?;
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
    final result = await Navigator.of(context).push<(double, double)>(
      MaterialPageRoute(
        builder: (_) => PhotoRepositionScreen(image: FileImage(file)),
      ),
    );
    if (!mounted) return;
    setState(() {
      _pickedPhotoFile = file;
      _photoAlignY = result?.$1 ?? 0;
      _photoScale = result?.$2 ?? 1;
      _removePhoto = false;
    });
  }

  Future<void> _repositionPhoto(ImageProvider image) async {
    final result = await Navigator.of(context).push<(double, double)>(
      MaterialPageRoute(
        builder: (_) => PhotoRepositionScreen(
          image: image,
          initialAlignY: _photoAlignY,
          initialScale: _photoScale,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _photoAlignY = result.$1;
        _photoScale = result.$2;
      });
    }
  }

  Future<void> _choosePhotoSource() async {
    final l10n = AppLocalizations.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MenuRow(
                icon: PhosphorIconsLight.camera,
                label: l10n.takePhoto,
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              _MenuRow(
                icon: PhosphorIconsLight.images,
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
      _photoScale = 1;
    });
  }

  Widget _buildPhotoPicker(AppLocalizations l10n) {
    if (_pickedPhotoFile != null) {
      final image = FileImage(_pickedPhotoFile!);
      return _PhotoPreview(
        image: ScaledPhoto(
          scale: _photoScale,
          child: Image(
            image: image,
            fit: BoxFit.cover,
            alignment: Alignment(0, _photoAlignY),
          ),
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
            image: ScaledPhoto(
              scale: _photoScale,
              child: Image(
                image: image,
                fit: BoxFit.cover,
                alignment: Alignment(0, _photoAlignY),
              ),
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
        icon: const Icon(PhosphorIconsLight.camera, size: 18),
        label: Text(l10n.addPhoto),
      ),
    );
  }

  DayCardScreen _buildDayCardScreen() {
    // firstWhere без orElse впав би, якби активну сутність видалив
    // співавтор на своєму пристрої до того, як цей пристрій встиг
    // синхронізувати _subjects.
    final subjectName = _activeSubjectId == null
        ? null
        : _subjects
              .cast<Subject?>()
              .firstWhere((s) => s?.id == _activeSubjectId, orElse: () => null)
              ?.name;
    return DayCardScreen(
      subjectName: subjectName,
      entry: CheckinEntry(
        // Картка дня — статичне зображення для шеру, коментарі туди не
        // рендеряться, тож id не потрібен.
        id: (_todayEntryId as String?) ?? '',
        createdAt: _todayEntrySavedAt ?? DateTime.now(),
        mood: _selected!,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        photoPath: _existingPhotoPath,
        photoAlignY: _photoAlignY,
        photoScale: _photoScale,
        updateCount: _updateCount,
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
                    // "Готово" на клавіатурі одразу зберігає — без цього
                    // єдиний спосіб зберегти з відкритою клавіатурою це
                    // скролити й шукати кнопку "Зберегти" нижче фото,
                    // яку клавіатура ще й затуляє знизу.
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _saving ? null : _save(),
                    // Той самий розмір і міжрядковий інтервал, що й у збереженому
                    // вигляді нижче (_buildSummaryContent) — щоб перехід
                    // "пишу" → "збережено" не виглядав як зовсім інший текст.
                    style: const TextStyle(fontSize: 14, height: 1.4),
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
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.accentInk,
                              ),
                            )
                          : Text(
                              _todayEntryId != null ? l10n.update : l10n.save,
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
                // Це власний текст юзера, не метадані (як-от "Оновлено N
                // разів" нижче) — має виділятись, а не зливатись з
                // приглушеними підписами навколо.
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.ink,
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
                    borderRadius: BorderRadius.circular(14),
                    child: AspectRatio(
                      aspectRatio: kCompactPhotoAspectRatio,
                      child: ScaledPhoto(
                        scale: _photoScale,
                        child: Image.memory(
                          snapshot.data!,
                          fit: BoxFit.cover,
                          alignment: Alignment(0, _photoAlignY),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
            if (_todayEntryId != null)
              CommentsSection(
                // Без ключа перемикання між щоденниками (_todayEntryId
                // міняється, той самий слот у дереві) могло лишити стару
                // чернетку/ціль відповіді від попереднього щоденника.
                key: ValueKey('comments-$_todayEntryId'),
                checkinId: _todayEntryId as String,
                canComment: true,
                isOwner: true,
                showWhenEmpty: false,
                isSubject: _activeSubjectId != null,
              ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _startEditing,
          icon: const Icon(PhosphorIconsLight.pencilSimple, size: 18),
          label: Text(l10n.edit),
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: TextButton.icon(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => _buildDayCardScreen())),
          icon: const Icon(PhosphorIconsLight.export, size: 18),
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

    try {
      final rows = await _supabase
          .from(_table)
          .select('mood, note, created_at')
          .eq(_idColumn, _idValue)
          .gte('created_at', start)
          .lt('created_at', end)
          .order('created_at');

      if (!mounted) return;

      setState(() {
        _weekEntries = (rows as List).map((row) {
          return CheckinEntry(
            // Лише для крапок тижневої стрічки — id тут ніде не читається
            // (CommentsSection на цей список не підключений).
            id: '',
            createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
            mood: moodFromDbValue(row['mood'] as String),
            note: row['note'] as String?,
          );
        }).toList();
      });
    } catch (_) {
      // Тиждень — лише декоративна стрічка на головному екрані, не
      // критичний для чек-іну сам по собі; при збої просто лишаємо
      // попередній стан замість непійманого винятку під час перемикання
      // щоденників.
    }
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
        'photo_scale': photoPath == null ? 1 : _photoScale,
        // 'user_id' у checkins має дефолт auth.uid(), тому передавати не
        // треба — а от subject_id у subject_checkins нема звідки взяти
        // самостійно, вказуємо явно тільки коли ведемо чек-ін сутності.
        // author_id теж лише для сутностей — атрибуція "хто написав", коли
        // щоденник ведуть кілька співавторів разом; для власного checkins
        // це й так завжди "я", підписувати нема сенсу.
        if (_activeSubjectId != null) 'subject_id': _activeSubjectId,
        if (_activeSubjectId != null)
          'author_id': _supabase.auth.currentUser!.id,
      };

      if (_todayEntryId != null) {
        final updated = await _supabase
            .from(_table)
            .update(payload)
            .eq('id', _todayEntryId as Object)
            .select('id');
        if ((updated as List).isEmpty) {
          throw Exception(
            'Update affected 0 rows — check RLS UPDATE policy on $_table.',
          );
        }
        // Сам інкремент рахує тригер у БД (checkin-update-count-migration.sql);
        // тут просто відображаємо очікуваний результат одразу, без повторного запиту.
        _updateCount++;
      } else {
        final inserted = await _supabase
            .from(_table)
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
      builder: (sheetContext) => _MoreMenuSheet(
        hasNewLetters: _pendingUnlockedLetters > 0,
        onProfile: () {
          Navigator.of(sheetContext).pop();
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
        },
        onTimeCapsules: () async {
          Navigator.of(sheetContext).pop();
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const TimeCapsulesScreen()));
          if (mounted) _loadPendingUnlockedLetters();
        },
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
      builder: (context) => AppDialog(
        title: l10n.deleteAccountConfirmTitle,
        content: Text(
          l10n.deleteAccountConfirmBody,
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
    if (!mounted) return;

    final finalConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: l10n.deleteAccountFinalConfirmTitle,
        primaryLabel: l10n.no,
        onPrimary: () => Navigator.of(context).pop(false),
        secondaryLabel: l10n.yesDelete,
        secondaryColor: Colors.redAccent,
        onSecondary: () => Navigator.of(context).pop(true),
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
    final locale = Localizations.localeOf(context);
    final today = DateTime.now();
    final dateLabel = '${today.day} ${monthNameGenitive(today.month, locale)}';

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
                      IconButton(
                        onPressed: () async {
                          final activeName = _activeSubjectId == null
                              ? null
                              : _subjects
                                    .cast<Subject?>()
                                    .firstWhere(
                                      (s) => s?.id == _activeSubjectId,
                                      orElse: () => null,
                                    )
                                    ?.name;
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => HistoryScreen(
                                subjectId: _activeSubjectId,
                                subjectName: activeName,
                              ),
                            ),
                          );
                          // На відміну від Друзів/Коментарів/Капсул, цей
                          // пуш ніколи не оновлював активність коментарів
                          // після повернення — якщо додав коментар до
                          // сьогоднішнього запису прямо в Історії, банер
                          // на головному екрані про це не дізнавався.
                          if (mounted) _checkCommentActivity();
                        },
                        icon: const Icon(
                          PhosphorIconsLight.calendarBlank,
                          size: 20,
                        ),
                        tooltip: l10n.history,
                      ),
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
                            icon: const Icon(
                              PhosphorIconsLight.users,
                              size: 20,
                            ),
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
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const CommentActivityScreen(),
                                ),
                              );
                              _checkCommentActivity();
                            },
                            icon: const Icon(
                              PhosphorIconsLight.chatCircleDots,
                              size: 20,
                            ),
                            tooltip: l10n.commentsLabel,
                          ),
                          if (_hasCommentActivity)
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
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            onPressed: _openMoreMenu,
                            icon: const Icon(
                              PhosphorIconsLight.dotsThreeVertical,
                              size: 20,
                            ),
                            tooltip: l10n.moreTooltip,
                          ),
                          // Дублює банер вище (там же "Капсули часу") —
                          // навіть якщо банер закрили на сесію, ця крапка
                          // лишається, поки лист реально не відкриють, і
                          // вказує прямо на пункт меню, де його шукати.
                          if (_pendingUnlockedLetters > 0)
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
                    ],
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _pendingNudges == null
                    ? const SizedBox.shrink()
                    : Column(
                        children: [
                          const SizedBox(height: 12),
                          GestureDetector(
                            // Тап на банер (окрім ✕ нижче) — показує, хто саме
                            // поштовхнув, а не просто закриває банер. ✕ має
                            // власний GestureDetector усередині — вкладений
                            // тап "перемагає" цей зовнішній, тож натискання
                            // саме на хрестик все ще просто закриває, не
                            // відкриваючи список.
                            onTap: _showNudgeList,
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                // Текст банера тепер завжди один короткий
                                // рядок (без name/count-інтерполяції), тож
                                // переносу більше нема — center замість
                                // start.
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Icon(
                                    PhosphorIconsLight.handWaving,
                                    size: 16,
                                    color: AppColors.accent,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      l10n.nudgeBanner,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.accent,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _dismissNudgeBanner,
                                    behavior: HitTestBehavior.opaque,
                                    child: const Padding(
                                      padding: EdgeInsets.all(6),
                                      child: Icon(
                                        PhosphorIconsLight.x,
                                        size: 16,
                                        color: AppColors.accent,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: (_pendingUnlockedLetters > 0 && !_lettersBannerDismissed)
                    ? Column(
                        children: [
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  PhosphorIconsLight.envelopeSimpleOpen,
                                  size: 16,
                                  color: AppColors.accent,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () async {
                                      setState(
                                        () => _lettersBannerDismissed = true,
                                      );
                                      await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const TimeCapsulesScreen(),
                                        ),
                                      );
                                      if (mounted) {
                                        _loadPendingUnlockedLetters();
                                      }
                                    },
                                    child: Text(
                                      l10n.timeCapsulesBannerReady,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.accent,
                                      ),
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => setState(
                                    () => _lettersBannerDismissed = true,
                                  ),
                                  child: const Icon(
                                    PhosphorIconsLight.x,
                                    size: 14,
                                    color: AppColors.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _SubjectChip(
                            label: l10n.me,
                            selected: _activeSubjectId == null,
                            onTap: () => _switchSubject(null),
                          ),
                          ..._subjects.map(
                            (s) => _SubjectChip(
                              label: s.name,
                              selected: _activeSubjectId == s.id,
                              onTap: () => _switchSubject(s.id),
                              onLongPress: () => _openSubjectMenu(s),
                              // Видно ще до тапу, що це не власний
                              // щоденник, а спільний з кимось.
                              leadingIcon: s.isOwner
                                  ? null
                                  : PhosphorIconsLight.usersThree,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _onCreateSubjectTap,
                    icon: const Icon(PhosphorIconsLight.plusCircle, size: 22),
                    tooltip: l10n.newSubject,
                    color: AppColors.inkMuted,
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
                                textAlign: TextAlign.center,
                                style: appSerif(fontSize: 28),
                              ),
                              if (_todayEntrySavedAt != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  [
                                    l10n.alreadySavedToday(
                                      '${_todayEntrySavedAt!.hour.toString().padLeft(2, '0')}:'
                                      '${_todayEntrySavedAt!.minute.toString().padLeft(2, '0')}',
                                    ),
                                    if (_updateCount > 0)
                                      l10n.updatedCount(_updateCount),
                                    // Тільки коли щоденник сутності веде хтось
                                    // ще, крім мене — власний checkins ніколи
                                    // не підписуємо.
                                    if (_authorName != null)
                                      l10n.authorLabel(_authorName!),
                                  ].join(' · '),
                                  textAlign: TextAlign.center,
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
              // Ховаємо смужку тижня, коли відкрита клавіатура — вона
              // сидить поза скролом фіксованою висотою, тож при
              // стисканні Scaffold клавіатурою (resizeToAvoidBottomInset)
              // забирала місце саме тоді, коли форма чек-іну (поле
              // нотатки, кнопка збереження) найбільше його потребує.
              // Навігація тижнями під час набору тексту й не потрібна.
              // AnimatedSize замість миттєвого if/insert — інакше поява
              // смужки одразу після закриття клавіатури виглядає як різкий
              // стрибок контенту, а не плавне звільнення місця.
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: MediaQuery.of(context).viewInsets.bottom == 0
                    ? Column(
                        children: [
                          _buildWeekStrip(),
                          const SizedBox(height: 16),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
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
                icon: const Icon(PhosphorIconsLight.caretLeft, size: 18),
                visualDensity: VisualDensity.compact,
                color: AppColors.inkMuted,
              ),
              Text(
                _weekLabel(l10n),
                style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
              ),
              IconButton(
                onPressed: _isCurrentWeek ? null : () => _changeWeek(1),
                icon: const Icon(PhosphorIconsLight.caretRight, size: 18),
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
  final VoidCallback onProfile;
  final VoidCallback onTimeCapsules;
  final bool hasNewLetters;
  final VoidCallback onLanguage;
  final VoidCallback onSignOut;
  final VoidCallback onDeleteAccount;

  const _MoreMenuSheet({
    required this.onProfile,
    required this.onTimeCapsules,
    required this.hasNewLetters,
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
              icon: PhosphorIconsLight.userCircle,
              label: l10n.profile,
              onTap: onProfile,
            ),
            _MenuRow(
              icon: PhosphorIconsLight.envelopeSimple,
              label: l10n.timeCapsulesMenuLabel,
              onTap: onTimeCapsules,
              showDot: hasNewLetters,
            ),
            _MenuRow(
              icon: PhosphorIconsLight.globe,
              label:
                  '${l10n.language}: ${appLocale.value.languageCode == 'uk' ? 'UK' : 'EN'}',
              onTap: onLanguage,
            ),
            _MenuRow(
              icon: PhosphorIconsLight.signOut,
              label: l10n.signOut,
              onTap: onSignOut,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(color: AppColors.divider, height: 1),
            ),
            _MenuRow(
              icon: PhosphorIconsLight.trash,
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
  final bool showDot;

  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.showDot = false,
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
            if (showDot) ...[
              const SizedBox(width: 8),
              const DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.notification,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(width: 8, height: 8),
              ),
            ],
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
          child: AspectRatio(
            aspectRatio: kCompactPhotoAspectRatio,
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
              icon: const Icon(
                PhosphorIconsLight.arrowsOutCardinal,
                size: 16,
                color: Colors.white,
              ),
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
              icon: const Icon(
                PhosphorIconsLight.x,
                size: 16,
                color: Colors.white,
              ),
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
