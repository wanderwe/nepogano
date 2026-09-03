import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'comments_section.dart';
import 'date_labels.dart';
import 'day_card_screen.dart';
import 'l10n/app_localizations.dart';
import 'main.dart';
import 'month_report.dart';
import 'photo_storage.dart';
import 'share_utils.dart';
import 'style.dart';
import 'subject_diary_views.dart';

const _constellationIntroSeenKey = 'constellation_intro_seen';

class CheckinEntry {
  final String id;
  final DateTime createdAt;
  final MoodLevel mood;
  final String? note;
  final String? photoPath;
  final double photoAlignX;
  final double photoAlignY;
  final double photoScale;
  final int updateCount;
  // Тільки для щоденників сутностей з кількома співавторами — хто написав
  // саме цей запис. Null для власного checkins і для сутностей з одним
  // автором.
  final String? authorName;

  CheckinEntry({
    required this.id,
    required this.createdAt,
    required this.mood,
    this.note,
    this.photoPath,
    this.photoAlignX = 0,
    this.photoAlignY = 0,
    this.photoScale = 1,
    this.updateCount = 0,
    this.authorName,
  });
}

class HistoryScreen extends StatefulWidget {
  final String? subjectId;
  final String? subjectName;
  // Відкрити екран одразу проскроленим до конкретного дня (тап по крапці
  // тижневої стрічки на головному екрані) — той самий UX, що тап по дню
  // прямо в календарі цього екрана, просто ініційований іззовні.
  final DateTime? initialDate;

  const HistoryScreen({
    super.key,
    this.subjectId,
    this.subjectName,
    this.initialDate,
  });

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

  final _scrollController = ScrollController();
  // Клік по дню в календарі скролить вниз до запису — якщо він далеко,
  // повертатись нагору гортанням незручно, тож показуємо кнопку швидкого
  // повернення, як тільки прокрутка відходить від самого верху.
  bool _showScrollTop = false;
  // Перемикач "Календар / Сузір'я" — заміняє лише саму сітку/канву, шапка з
  // навігацією місяцем і список записів знизу спільні для обох режимів.
  bool _showConstellation = false;
  bool _exporting = false;
  bool _sharingConstellation = false;

  /// Id записів, чия нотатка розгорнута повністю — за замовчуванням довгі
  /// нотатки обрізані (`ExpandableNote`, `style.dart`), інакше один "пост-простирадло"
  /// змушує нескінченно свайпати, щоб дістатись наступного дня в стрічці.
  final Set<String> _expandedNoteIds = {};

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDate;
    final now = DateTime.now();
    _visibleMonth = initial != null
        ? DateTime(initial.year, initial.month)
        : DateTime(now.year, now.month);
    _scrollController.addListener(_handleScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    final show = _scrollController.offset > 300;
    if (show != _showScrollTop) setState(() => _showScrollTop = show);
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final columns =
          'id, mood, note, created_at, local_date, photo_path, photo_align_x, photo_align_y, photo_scale, update_count'
          '${widget.subjectId != null ? ', author_id' : ''}';
      final rows = await _supabase
          .from(_table)
          .select(columns)
          .eq(_idColumn, _idValue)
          .order('created_at');

      // Атрибуція автора — тільки для щоденників сутностей, і тільки коли
      // автор не я сам (собі підпис не показуємо).
      final myId = _supabase.auth.currentUser?.id;
      Map<String, String?> authorNameById = {};
      if (widget.subjectId != null) {
        final authorIds = (rows as List)
            .map((row) => row['author_id'] as String?)
            .whereType<String>()
            .where((id) => id != myId)
            .toSet()
            .toList();
        if (authorIds.isNotEmpty) {
          final nameRows = await _supabase
              .from('profiles')
              .select('user_id, display_name')
              .inFilter('user_id', authorIds);
          authorNameById = {
            for (final row in nameRows as List)
              row['user_id'] as String: row['display_name'] as String?,
          };
        }
      }

      final entries = (rows as List).map((row) {
        final authorId = row['author_id'] as String?;
        // Той самий принцип, що в _loadWeek() на головному екрані:
        // угруповуємо/показуємо за ЕФЕКТИВНОЮ (local_date) датою, не за
        // сирим created_at — інакше запис, зроблений близько опівночі,
        // міг би лягти в календарі не на той день, на який його бачить
        // тижнева стрічка головного екрана (той самий клас розбіжності,
        // що вже виправлявся для RLS-перевірки вгадування, правило 26
        // в ARCHITECTURE.md).
        final localDateStr = row['local_date'] as String?;
        final effectiveDate = localDateStr != null
            ? DateTime.parse(localDateStr)
            : DateTime.parse(row['created_at'] as String).toLocal();
        return CheckinEntry(
          id: row['id'] as String,
          createdAt: effectiveDate,
          mood: moodFromDbValue(row['mood'] as String),
          note: row['note'] as String?,
          photoPath: row['photo_path'] as String?,
          photoAlignX: (row['photo_align_x'] as num?)?.toDouble() ?? 0,
          photoAlignY: (row['photo_align_y'] as num?)?.toDouble() ?? 0,
          photoScale: (row['photo_scale'] as num?)?.toDouble() ?? 1,
          updateCount: (row['update_count'] as num?)?.toInt() ?? 0,
          authorName: (authorId == null || authorId == myId)
              ? null
              : authorNameById[authorId],
        );
      }).toList();

      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
        if (widget.initialDate != null) {
          // _entryKeys заповнюється лише під час білда списку записів
          // (_buildEntryList) — чекаємо, поки цей кадр реально
          // відрендериться, інакше ключа ще нема і скрол мовчки нічого
          // не робить.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _scrollToDay(widget.initialDate!.day);
          });
          // Коригувальний другий прохід: фото вже не зсувають висоту
          // (AspectRatio-плейсхолдер вище), але коментарі під записом
          // довантажуються асинхронно й так само можуть трохи "дорости"
          // вже після першого скролу — тому позиція, порахована в першу
          // мить після відкриття екрана, ще не так точна, як тап по дню
          // просто в уже відкритій, давно "усталеній" Історії. Другий
          // виклик після паузи ловить ці пізні зміни висоти.
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) _scrollToDay(widget.initialDate!.day);
          });
        }
      }
      if (widget.subjectId != null) {
        markSubjectHistoryViewed(widget.subjectId!);
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

  Future<void> _exportMonth() async {
    final entries = _monthEntriesDesc;
    if (entries.isEmpty || _exporting) return;
    setState(() => _exporting = true);
    try {
      await shareMonthReport(
        context: context,
        monthEntries: entries,
        month: _visibleMonth,
        subjectName: widget.subjectName,
      );
    } catch (e, st) {
      debugPrint('Export month failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).shareFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _shareConstellation() async {
    if (_sharingConstellation || _entriesByDay.isEmpty) return;
    setState(() => _sharingConstellation = true);
    try {
      final l10n = AppLocalizations.of(context);
      final locale = Localizations.localeOf(context);
      final daysInMonth = DateTime(
        _visibleMonth.year,
        _visibleMonth.month + 1,
        0,
      ).day;
      final bytes = await renderConstellationSharePng(
        entriesByDay: _entriesByDay,
        daysInMonth: daysInMonth,
        year: _visibleMonth.year,
        month: _visibleMonth.month,
        monthTitle:
            '${monthName(_visibleMonth.month, locale)} ${_visibleMonth.year}',
        titleLabel: l10n.reportConstellationSection,
      );
      final dir = await getTemporaryDirectory();
      final monthSlug =
          '${_visibleMonth.year}-${_visibleMonth.month.toString().padLeft(2, '0')}';
      final file = File('${dir.path}/nepogano_constellation_$monthSlug.png');
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      // Без місяця в тексті повідомлення: дата вже видна на самому
      // зображенні картки, а в месенджерах підпис з місяцем виявився
      // занадто довгим рядком над прев'ю картинки.
      final shareText = widget.subjectName == null
          ? l10n.myConstellationInNepogano
          : l10n.subjectConstellationInNepogano(widget.subjectName!);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: shareText,
          sharePositionOrigin: shareOriginFrom(context),
        ),
      );
    } catch (e, st) {
      debugPrint('Share constellation failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).shareFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _sharingConstellation = false);
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
      // День місяця (1-31) повторюється в кожному місяці, тож старі ключі
      // могли б колізити з новими — скидаємо лише тут, а не на кожен build.
      _entryKeys.clear();
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
      alignment: 0.02,
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
                    icon: const Icon(PhosphorIconsLight.arrowLeft, size: 20),
                    tooltip: l10n.back,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.subjectName == null
                          ? l10n.history
                          : '${l10n.history} · ${widget.subjectName}',
                      overflow: TextOverflow.ellipsis,
                      style: appScreenTitle(),
                    ),
                  ),
                  if (!_loading && _error == null)
                    IconButton(
                      onPressed: _monthEntriesDesc.isEmpty || _exporting
                          ? null
                          : _exportMonth,
                      icon: _exporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              PhosphorIconsLight.downloadSimple,
                              size: 20,
                            ),
                      tooltip: _monthEntriesDesc.isEmpty
                          ? l10n.exportMonthDisabledHint
                          : l10n.exportMonth,
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
                        TextButton(
                          onPressed: _load,
                          // Той самий фікс, що й для помилки завантаження
                          // запису на Хоумпейджі: акцентний колір замість
                          // приглушеного дефолту, щоб кнопка читалась як дія.
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.accent,
                          ),
                          child: Text(l10n.retry),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: Stack(
                    children: [
                      _buildContent(),
                      Positioned(
                        right: 0,
                        bottom: 12,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 200),
                          offset: _showScrollTop
                              ? Offset.zero
                              : const Offset(0, 2),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: _showScrollTop ? 1 : 0,
                            child: IgnorePointer(
                              ignoring: !_showScrollTop,
                              child: FloatingActionButton.small(
                                heroTag: 'scrollTop',
                                onPressed: _scrollToTop,
                                backgroundColor: AppColors.surfaceRaised,
                                foregroundColor: AppColors.ink,
                                tooltip: l10n.scrollToTop,
                                child: const Icon(PhosphorIconsLight.arrowUp),
                              ),
                            ),
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
      controller: _scrollController,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              onPressed: () => _changeMonth(-1),
              icon: const Icon(PhosphorIconsLight.caretLeft),
            ),
            Text(
              '${monthName(_visibleMonth.month, locale)} ${_visibleMonth.year}',
              style: appScreenTitle(fontSize: 17),
            ),
            IconButton(
              onPressed: _isCurrentMonth ? null : () => _changeMonth(1),
              icon: const Icon(PhosphorIconsLight.caretRight),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildViewToggle(),
        const SizedBox(height: 12),
        if (_showConstellation)
          _buildConstellation(entriesByDay, daysInMonth)
        else ...[
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
              final date = DateTime(
                _visibleMonth.year,
                _visibleMonth.month,
                day,
              );
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
                              : (isFuture
                                    ? Colors.white24
                                    : AppColors.inkMuted),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
        const SizedBox(height: 28),
        _buildRetrospective(),
        _buildEntryList(),
      ],
    );
  }

  Widget _buildViewToggle() {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ViewToggleSegment(
              label: l10n.calendarView,
              selected: !_showConstellation,
              onTap: () => setState(() => _showConstellation = false),
            ),
          ),
          Expanded(
            child: _ViewToggleSegment(
              label: l10n.constellationView,
              selected: _showConstellation,
              onTap: _onConstellationViewTap,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onConstellationViewTap() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_constellationIntroSeenKey) ?? false;
    if (!seen) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AppDialog(
          title: l10n.constellationIntroTitle,
          content: Text(
            l10n.constellationIntroBody,
            style: const TextStyle(color: AppColors.inkMuted, height: 1.4),
          ),
          primaryLabel: l10n.gotIt,
          onPrimary: () => Navigator.of(context).pop(true),
          secondaryLabel: l10n.cancel,
          onSecondary: () => Navigator.of(context).pop(false),
        ),
      );
      // Прапорець ставимо лише при реальному "Зрозуміло" — "Скасувати" не
      // повинно назавжди ховати пояснення, яке юзер фактично не прийняв.
      if (proceed != true) return;
      await prefs.setBool(_constellationIntroSeenKey, true);
    }
    if (mounted) setState(() => _showConstellation = true);
  }

  Widget _buildConstellation(
    Map<int, CheckinEntry> entriesByDay,
    int daysInMonth,
  ) {
    // Порожній місяць уже повідомляє про себе один раз нижче, у
    // _buildEntryList — не дублюємо той текст тут. Але, на відміну від
    // попередньої версії, полотно все одно малюємо: фонові зірки
    // (_drawBackgroundStars) не залежать від записів, тож порожній місяць
    // все одно показує "нічне небо", як порожній календар все одно показує
    // сітку днів — а не голий текст на чорному тлі.
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        children: [
          _buildConstellationCanvas(entriesByDay, daysInMonth),
          if (entriesByDay.isNotEmpty)
            Positioned(
              right: 8,
              top: 8,
              child: _ConstellationShareButton(
                sharing: _sharingConstellation,
                onTap: _shareConstellation,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConstellationCanvas(
    Map<int, CheckinEntry> entriesByDay,
    int daysInMonth,
  ) {
    return LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return GestureDetector(
            // На відміну від тапу по дню в календарі (де перехід очікуваний
            // і миттєвий), тут спершу лише легка інфо-підказка — дата й
            // настрій, без різкого стрибка вниз по екрану серед розглядання
            // картинки. Перехід до самого запису — окрема, свідома дія
            // (кнопка в SnackBar), не побічний ефект простого тапу.
            onTapUp: (details) {
              final day = _MonthConstellationPainter.dayAt(
                details.localPosition,
                size,
                year: _visibleMonth.year,
                month: _visibleMonth.month,
                daysInMonth: daysInMonth,
              );
              final entry = day == null ? null : entriesByDay[day];
              // showSnackBar за замовчуванням СТАВИТЬ У ЧЕРГУ, а не заміняє
              // — без цього тап по іншій зірці чекав би, поки таймер
              // попередньої добіжить до кінця, перш ніж показати нову.
              // Явне очищення тут же дозволяє й тапу по порожньому місцю
              // прибирати тултіп, не лише появі нового.
              ScaffoldMessenger.of(context).clearSnackBars();
              if (day == null || entry == null) return;
              final locale = Localizations.localeOf(context);
              final l10n = AppLocalizations.of(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  // Стандартний action: інколи переносить кнопку на окремий
                  // рядок навіть коли місця вистачає (Material 3) — робимо
                  // Row самі, щоб висота гарантовано лишалась компактною.
                  content: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Настрій уже видно з кольору самої зірки —
                      // повторювати його ще й текстом зайве, лише дата.
                      Text(
                        '$day ${monthNameGenitive(_visibleMonth.month, locale)}',
                      ),
                      TextButton(
                        onPressed: () => _scrollToDay(day),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.accent,
                        ),
                        child: Text(l10n.viewEntry),
                      ),
                    ],
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: CustomPaint(
              painter: _MonthConstellationPainter(
                entriesByDay: entriesByDay,
                daysInMonth: daysInMonth,
                year: _visibleMonth.year,
                month: _visibleMonth.month,
              ),
              child: const SizedBox.expand(),
            ),
          );
        },
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
                    if (entry.authorName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        AppLocalizations.of(
                          context,
                        ).authorLabel(entry.authorName!),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                    if (entry.note != null && entry.note!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      ExpandableNote(
                        text: entry.note!,
                        expanded: _expandedNoteIds.contains(entry.id),
                        onToggle: () => setState(() {
                          if (!_expandedNoteIds.add(entry.id)) {
                            _expandedNoteIds.remove(entry.id);
                          }
                        }),
                      ),
                    ],
                    if (entry.photoPath != null) ...[
                      const SizedBox(height: 8),
                      FutureBuilder<Uint8List?>(
                        future: downloadCheckinPhoto(entry.photoPath!),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            // Не SizedBox.shrink() — той дає нульову висоту,
                            // тож коли фото таки довантажується, картка
                            // "виростає" і зсуває все нижче вже ПІСЛЯ того,
                            // як _scrollToDay порахував позицію для тапу по
                            // крапці тижневої стрічки, і скрол влучає не
                            // туди (гірше — чим далі ціль углиб списку).
                            // AspectRatio одразу резервує фінальну висоту.
                            return const AspectRatio(
                              aspectRatio: kCompactPhotoAspectRatio,
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            );
                          }
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: AspectRatio(
                              aspectRatio: kCompactPhotoAspectRatio,
                              child: ScaledPhoto(
                                scale: entry.photoScale,
                                alignX: entry.photoAlignX,
                                child: Image.memory(
                                  snapshot.data!,
                                  fit: BoxFit.cover,
                                  alignment: Alignment(
                                    entry.photoAlignX,
                                    entry.photoAlignY,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                    CommentsSection(
                      // Без власного ключа Flutter підбирав цей віджет за
                      // позицією в Column, а не за конкретним записом — при
                      // перебудові весь FocusNode/TextEditingController
                      // composer'а міг "переїхати" на інший день, звідси
                      // несподіваний скрол/фокус на чужому записі.
                      key: ValueKey('comments-${entry.id}'),
                      checkinId: entry.id,
                      canComment: true,
                      isOwner: true,
                      showWhenEmpty: false,
                      isSubject: widget.subjectId != null,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DayCardScreen(
                      entry: entry,
                      subjectName: widget.subjectName,
                    ),
                  ),
                ),
                icon: const Icon(PhosphorIconsLight.export, size: 18),
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

class _ViewToggleSegment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ViewToggleSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.surfaceRaised : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? AppColors.ink : AppColors.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Оверлей прямо на самому сузір'ї, не в шапці екрана поруч з "Експортувати
/// місяць" — дія стосується конкретно цього вигляду (і зникає разом з ним
/// при перемиканні на календар), тож логічно лежить на самій картинці, а не
/// на рівні всього екрана Історії.
class _ConstellationShareButton extends StatelessWidget {
  final bool sharing;
  final VoidCallback onTap;

  const _ConstellationShareButton({required this.sharing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // IconButton, не голий Material+InkWell — так само, як інші круглі
    // іконки-кнопки в шапках екранів, безкоштовно дає tooltip по довгому
    // натисканню (вже стилізований через tooltipTheme у main.dart) і
    // стандартний приглушений колір іконки (AppColors.inkMuted через
    // iconButtonTheme), той самий тон, що й в іконки "Експортувати місяць"
    // поруч, а не довільний білий.
    return IconButton(
      onPressed: sharing ? null : onTap,
      tooltip: l10n.share,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.surface.withValues(alpha: 0.7),
        shape: const CircleBorder(),
      ),
      icon: sharing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.inkMuted,
              ),
            )
          : const Icon(PhosphorIconsLight.export, size: 18),
    );
  }
}

/// Емоційний, не аналітичний рендер того самого місяця — кожен чек-ін стає
/// зіркою (колір = настрій), розкидані псевдовипадково по канві й з'єднані
/// лінією в хронологічному порядку. Розкладка детермінована (seed від
/// року+місяця): той самий місяць завжди дає ту саму картинку, а позиція
/// кожного конкретного дня стабільна незалежно від того, скільки інших днів
/// цього місяця мають запис (Random витягується для КОЖНОГО дня місяця по
/// порядку, не лише для днів із записом) — інакше пізніше заповнений заднім
/// числом день зсунув би розкладку решти. Дні без запису пропускаються:
/// лінія з'єднує лише реальні чек-іни напряму, тож густота самого сузір'я й
/// так чесно відображає, скільки днів було зафіксовано, без окремої метрики.
class _MonthConstellationPainter extends CustomPainter {
  final Map<int, CheckinEntry> entriesByDay;
  final int daysInMonth;
  final int year;
  final int month;
  // За замовчуванням true скрізь (екран, PDF) — фон і справжні зірки
  // ділять те саме полотно. Картка шеру — виняток: фоновий зоряний пил
  // малюється окремо на весь кадр 9:16 (`renderConstellationSharePng`),
  // а сюди передається false, щоб не малювати його вдруге поверх уже
  // готового фону в межах самого квадрата справжніх зірок.
  final bool drawBackground;

  _MonthConstellationPainter({
    required this.entriesByDay,
    required this.daysInMonth,
    required this.year,
    required this.month,
    this.drawBackground = true,
  });

  static const _marginFraction = 0.12;
  // Фіксований, не прив'язаний до місяця seed — тьмяні "фонові" зірки самі
  // по собі не дані, лише декорація, що продає ідею нічного неба; мають
  // лишатись стабільними, не стрибати між місяцями, як справжні дані.
  static const _backgroundSeed = 42;
  static const _backgroundStarCount = 40;
  // Комфортна зона тапу навколо зірки — помітно більша за візуальний
  // радіус найменшої зірки (3.0), інакше влучити пальцем по маленькій
  // зірці без нотатки й фото практично неможливо.
  static const _tapRadius = 22.0;

  /// Той самий детермінований розрахунок, що й малювання нижче — окремий
  /// статичний метод, щоб тап-хендлер міг порахувати ті самі координати,
  /// не дублюючи цикл із paint().
  static Map<int, Offset> _positionsFor({
    required int year,
    required int month,
    required int daysInMonth,
    required Size size,
  }) {
    final random = Random(year * 10000 + month * 100);
    final positions = <int, Offset>{};
    for (var day = 1; day <= daysInMonth; day++) {
      final dx =
          _marginFraction + random.nextDouble() * (1 - 2 * _marginFraction);
      final dy =
          _marginFraction + random.nextDouble() * (1 - 2 * _marginFraction);
      positions[day] = Offset(dx * size.width, dy * size.height);
    }
    return positions;
  }

  /// День місяця, у зірку якого влучив тап, чи null, якщо тап був повз усі.
  static int? dayAt(
    Offset tapPosition,
    Size size, {
    required int year,
    required int month,
    required int daysInMonth,
  }) {
    final positions = _positionsFor(
      year: year,
      month: month,
      daysInMonth: daysInMonth,
      size: size,
    );
    // НАЙБЛИЖЧА зірка в межах радіуса тапу, не перша за хронологією — коли
    // кілька зірок скупчені поряд (реальний випадок на щільний місяць),
    // перша-в-порядку завжди "перемагала" незалежно від того, куди саме
    // влучив палець, і решту поряд неможливо було обрати взагалі.
    int? closestDay;
    var closestDistance = double.infinity;
    for (final entry in positions.entries) {
      final distance = (entry.value - tapPosition).distance;
      if (distance <= _tapRadius && distance < closestDistance) {
        closestDistance = distance;
        closestDay = entry.key;
      }
    }
    return closestDay;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (drawBackground) _drawBackgroundStars(canvas, size);

    final positions = _positionsFor(
      year: year,
      month: month,
      daysInMonth: daysInMonth,
      size: size,
    );

    final daysWithEntries = entriesByDay.keys.toList()..sort();

    final linePaint = Paint()
      ..color = AppColors.inkMuted.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    for (var i = 0; i < daysWithEntries.length - 1; i++) {
      canvas.drawLine(
        positions[daysWithEntries[i]]!,
        positions[daysWithEntries[i + 1]]!,
        linePaint,
      );
    }

    for (final day in daysWithEntries) {
      _drawStar(canvas, positions[day]!, entriesByDay[day]!);
    }
  }

  // Чистий випадковий розкид інколи зводить дві крапки впритул одна до
  // одної (статистично очікувано на 40 точках, але оком читається як
  // випадкова розмазана пляма, не задум) — мінімальна дистанція нижче це
  // виключає.
  static const _backgroundMinDistance = 18.0;

  /// Тьмяні статичні крапки, розкидані по всій канві незалежно від реальних
  /// днів — суто атмосфера нічного неба, приглушені настільки, щоб їх не
  /// можна було сплутати зі справжніми зірками-чек-інами. `static` — не
  /// використовує нічого, крім статичних констант класу, тож картка шеру
  /// (`renderConstellationSharePng`) викликає це напряму для повного
  /// кадру 9:16, без створення цілого `_MonthConstellationPainter`.
  static void _drawBackgroundStars(Canvas canvas, Size size) {
    final random = Random(_backgroundSeed);
    final paint = Paint()..color = AppColors.inkMuted.withValues(alpha: 0.4);
    final placed = <Offset>[];
    for (var i = 0; i < _backgroundStarCount; i++) {
      Offset point;
      var attempts = 0;
      do {
        point = Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        );
        attempts++;
      } while (attempts < 20 &&
          placed.any((p) => (p - point).distance < _backgroundMinDistance));
      placed.add(point);
      canvas.drawCircle(point, 1.0, paint);
    }
  }

  /// Шість спроб до цього, усі варіації "коло + якась прикраса поверх"
  /// (зміщена пляма-хайлайт → більярдна куля; суцільний градієнт → все
  /// розмите; центрована крапка → просто менша куля; яскравий хрест-спалах
  /// → ялинкова прикраса; тонший/тьмяніший хрест → те саме, лише слабше;
  /// діагональний "×" замість "+" → та сама проблема під іншим кутом) — не
  /// зайшла жодна. Рішення не в тюнінгу прикраси, а в її відсутності:
  /// просто ореол + чітке коло, без жодного додаткового елемента.
  /// "Зірковість" — з контексту (лінії-сузір'я, тьмяний зоряний фон, назва
  /// екрана), не з форми кожної точки окремо, так само, як на реальних
  /// астрономічних картах (там зірка — просто крапка різної яскравості).
  void _drawStar(Canvas canvas, Offset center, CheckinEntry entry) {
    final radius = _starRadius(entry);
    final color = entry.mood.color;

    // Восьма правка: попередній ореол/спалах розпливались задовго — на
    // реальному пристрої, особливо коли кілька зірок стоять близько,
    // розмиті плями зливались в одну туманну масу замість окремих
    // крапок. Значно звужено радіус розмиття й розмір і ореолу, і
    // дифракційного спалаху — світіння лишається, але щільніше тримається
    // біля самого ядра, не "розтікається" по сусідніх зірках.
    final spikePaint = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.5);
    const diagonal = 0.7853981633974483; // pi/4
    canvas.save();
    canvas.translate(center.dx, center.dy);
    for (final angle in [diagonal, -diagonal]) {
      canvas.save();
      canvas.rotate(angle);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: radius * 3.5,
          height: radius * 0.7,
        ),
        spikePaint,
      );
      canvas.restore();
    }
    canvas.restore();

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.6);
    canvas.drawCircle(center, radius * 1.5, glowPaint);

    canvas.drawCircle(center, radius, Paint()..color = color);
  }

  /// Розмір/яскравість зірки кодує "скільки себе вклав цього дня" — база
  /// (мінімум навіть без нотатки й фото) + приріст від довжини нотатки з
  /// капом (щоб один довгий пост не розвалив композицію) + фіксований
  /// приріст за фото.
  double _starRadius(CheckinEntry entry) {
    const base = 3.0;
    const maxNoteBonus = 4.0;
    final noteLength = entry.note?.length ?? 0;
    final noteBonus = (noteLength / 60).clamp(0, maxNoteBonus).toDouble();
    final photoBonus = entry.photoPath != null ? 3.0 : 0.0;
    return base + noteBonus + photoBonus;
  }

  @override
  bool shouldRepaint(covariant _MonthConstellationPainter oldDelegate) {
    return oldDelegate.year != year ||
        oldDelegate.month != month ||
        oldDelegate.entriesByDay.length != entriesByDay.length;
  }
}

/// Той самий вигляд, що й на екрані Історії, растеризований у PNG — для
/// вбудовування в PDF-звіт місяця (`month_report.dart`), де малює не
/// Flutter `Canvas`, а власний `PdfGraphics` пакета `pdf`, що не вміє
/// прямо виконати цей `CustomPainter`. Мусить викликатись на головному
/// ізоляті (доступ до рушія рендеру), ДО `Isolate.run`, що будує сам PDF.
///
/// `logicalSize` — той самий порядок величини, що й реальна ширина
/// `AspectRatio`-квадрата на екрані Історії (~320-360лп після відступів
/// екрана). Радіус зірки й розмиття в `_MonthConstellationPainter`
/// абсолютні, не пропорційні `Size` полотна — тож якщо тут малювати одразу
/// у велике полотно (як було: 800), зірки виходять НЕПРОПОРЦІЙНО дрібними
/// відносно композиції, і при подальшому масштабуванні в PDF/шері це
/// читається як "розмито", хоч це не блюр, а невідповідний масштаб.
/// Роздільна здатність виводу натомість регулюється окремо через
/// `pixelRatio` (той самий підхід, що й `RepaintBoundary.toImage` у
/// `day_card_screen.dart`) — композиція лишається тією ж, що на екрані,
/// а растеризується вже у вищу піксельну щільність.
///
/// `heading`, якщо задано, домальовується ПРЯМО в те саме зображення над
/// сузір'ям — не окремим `pw.Text` поруч у PDF. `pw.Column`, який раніше
/// об'єднував заголовок і `pw.Image` в один список-елемент MultiPage, НЕ
/// гарантує атомарність (та сама пастка, що вже задокументована для
/// нотаток місяця нижче в `month_report.dart`: Column вимірює кожну
/// дитину на її повну висоту і вирішує, скільки дітей влізло, а не
/// переносить себе цілком) — на практиці заголовок лишався сиротою
/// внизу сторінки, а саме зображення переїжджало на наступну. Один
/// растеризований PNG із заголовком усередині — єдиний спосіб
/// гарантувати, що вони ніколи не розійдуться: `pw.Image` — атомарний
/// лист-віджет, MultiPage переносить його цілком, якщо не влазить.
/// Повертає `(bytes, width, height)` у пікселях — ширина й висота вже НЕ
/// обов'язково збігаються (заголовок додає висоту), викликач має
/// порахувати правильну пропорцію показу з них, а не форсувати квадрат.
// Заголовок сузір'я в PDF малюється Canvas-ом (растр), не справжнім
// pw.Text — тому за замовчуванням брав би VARIABLE "Lora" застосунку, а
// решта тексту в тому самому PDF рендериться пакетом `pdf` через
// СТАТИЧНИЙ Lora-Static-Bold.ttf (`pdf` не вміє variable-шрифти, див.
// коментар у pubspec.yaml) — два різні файли, візуально помітно різний
// шрифт в одному документі. Підвантажуємо той самий статичний файл під
// окремою назвою родини (щоб не підмінити "Lora" всюди по застосунку) і
// рендеримо заголовок ним — той самий шрифт, що й решта PDF-тексту.
// Один раз за життя застосунку: FontLoader.load() — важка операція,
// кешуємо через Future, не bool (паралельні виклики чекають той самий
// Future, не тригерять завантаження вдруге).
Future<void>? _pdfHeadingFontLoad;
const _pdfHeadingFontFamily = 'LoraStaticPdf';

Future<void> _ensurePdfHeadingFontLoaded() {
  return _pdfHeadingFontLoad ??= () async {
    final data = await rootBundle.load('assets/fonts/Lora-Static-Bold.ttf');
    await (FontLoader(_pdfHeadingFontFamily)..addFont(
          Future.value(data),
        ))
        .load();
  }();
}

Future<(Uint8List bytes, int width, int height)> renderConstellationPng({
  required Map<int, CheckinEntry> entriesByDay,
  required int daysInMonth,
  required int year,
  required int month,
  String? heading,
  double logicalSize = 340,
  double pixelRatio = 3.0,
}) async {
  if (heading != null) await _ensurePdfHeadingFontLoaded();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(pixelRatio);

  var headingHeight = 0.0;
  if (heading != null) {
    final painter = TextPainter(
      text: TextSpan(
        text: heading,
        style: const TextStyle(
          fontFamily: _pdfHeadingFontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: logicalSize);
    painter.paint(canvas, Offset.zero);
    headingHeight = painter.height + 12;
  }

  canvas.save();
  canvas.translate(0, headingHeight);
  _MonthConstellationPainter(
    entriesByDay: entriesByDay,
    daysInMonth: daysInMonth,
    year: year,
    month: month,
  ).paint(canvas, Size(logicalSize, logicalSize));
  canvas.restore();

  final picture = recorder.endRecording();
  final width = (logicalSize * pixelRatio).round();
  final height = ((logicalSize + headingHeight) * pixelRatio).round();
  final image = await picture.toImage(width, height);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return (byteData!.buffer.asUint8List(), width, height);
}

/// Брендована картка для шеру "як пост", портретна 9:16 — той самий формат,
/// що й Day Card у `day_card_screen.dart`. "Сузір'я місяця" зверху зліва
/// звичайним рядком, дата одразу під ним, менша й приглушеніша —
/// заголовок+підзаголовок в ОДНОМУ куті, не два окремі написи по різних
/// кутах нагорі (пробували — забагато шуму зверху, погляд тягнуло в різні
/// боки), і не в парі з "nepogano.app" унизу (теж пробували: губилась
/// поруч із брендовим підписом, читалась як дрібний текст, не як назва
/// самого сузір'я). Не окремий великий Lora-заголовок теж (пробували:
/// виглядав важче за решту картки, а місяць/рік дублювався ще й унизу) і
/// не емоційний підсумок настрою кольором (пробували й це: середній
/// рівень шкали настрою, `moodNepogano`, пишеться так само, як назва
/// застосунку — "Непогано"/"Nepogano" — тож окремим великим словом
/// читався як бренд-заголовок, а не як індикатор настрою). "Nepogano" тут
/// не пишемо взагалі — бренд лише внизу як "nepogano.app". Готова одразу
/// до системного шер-листа, без окремого екрана попереднього перегляду,
/// так само як "Експортувати місяць" одразу відкриває шер без проміжного
/// кроку.
Future<Uint8List> renderConstellationSharePng({
  required Map<int, CheckinEntry> entriesByDay,
  required int daysInMonth,
  required int year,
  required int month,
  required String monthTitle,
  required String titleLabel,
  double pixelRatio = 3.0,
}) async {
  const cardWidth = 320.0;
  const cardHeight = cardWidth * 16 / 9;
  const padding = 20.0;
  const mutedWhite = Color(0x99FFFFFF);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(pixelRatio);

  canvas.drawRect(
    const Rect.fromLTWH(0, 0, cardWidth, cardHeight),
    // Той самий колір фону, що й у Day Card — не AppColors.background
    // (0xFF121212), навмисно трохи інший відтінок картки, а не екрана.
    Paint()..color = const Color(0xFF141414),
  );

  // Фоновий зоряний пил — на весь кадр 9:16, не лише в межах квадрата
  // справжніх зірок нижче: та сама ідея, що в Картці дня (фото на весь
  // кадр, текст поверх), тільки для декоративного "нічного неба" замість
  // фото. Справжні зірки (нижче) навмисно НЕ малюють свій власний фон
  // (`drawBackground: false`) — інакше тут була б друга, густіша копія
  // того самого пилу поверх цієї.
  _MonthConstellationPainter._drawBackgroundStars(
    canvas,
    const Size(cardWidth, cardHeight),
  );

  // "Сузір'я місяця" зверху зліва, дата одразу під нею, менша й
  // приглушеніша — заголовок картки з датою-підзаголовком, все в одному
  // куті, верх картки не розтягується на всю ширину.
  final titleLabelPainter = TextPainter(
    text: TextSpan(
      text: titleLabel,
      style: const TextStyle(fontSize: 12, color: Color(0xD9FFFFFF)),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: cardWidth - padding * 2);
  const titleLabelOffset = Offset(padding, padding);
  titleLabelPainter.paint(canvas, titleLabelOffset);

  final header = TextPainter(
    text: TextSpan(
      text: monthTitle,
      style: const TextStyle(fontSize: 11, color: mutedWhite),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: cardWidth - padding * 2);
  final headerOffset = Offset(
    padding,
    titleLabelOffset.dy + titleLabelPainter.height + 2,
  );
  header.paint(canvas, headerOffset);

  final domainLabel = TextPainter(
    text: const TextSpan(
      text: 'nepogano.app',
      style: TextStyle(fontSize: 11, color: mutedWhite),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final footerY = cardHeight - padding - domainLabel.height;
  domainLabel.paint(
    canvas,
    Offset(cardWidth - padding - domainLabel.width, footerY),
  );

  // Розмір полотна сузір'я = той самий логічний масштаб, що й
  // [renderConstellationPng] (~330), не довільний — щоб зірки на картці
  // шеру виглядали так само, як в застосунку й у PDF, а не втретє
  // по-своєму.
  final constellationSize = cardWidth - padding * 2;
  final constellationTop = headerOffset.dy + header.height + 24;
  final availableHeight = footerY - 20 - constellationTop;
  final constellationY = availableHeight > constellationSize
      ? constellationTop + (availableHeight - constellationSize) / 2
      : constellationTop;

  canvas.save();
  canvas.translate(padding, constellationY);
  _MonthConstellationPainter(
    entriesByDay: entriesByDay,
    daysInMonth: daysInMonth,
    year: year,
    month: month,
    drawBackground: false,
  ).paint(canvas, Size(constellationSize, constellationSize));
  canvas.restore();

  final picture = recorder.endRecording();
  final width = (cardWidth * pixelRatio).round();
  final height = (cardHeight * pixelRatio).round();
  final image = await picture.toImage(width, height);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}
