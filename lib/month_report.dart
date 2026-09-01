import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Border;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'date_labels.dart';
import 'history_screen.dart';
import 'l10n/app_localizations.dart';
import 'main.dart';
import 'share_utils.dart';
import 'style.dart';

PdfColor _toPdfColor(Color color) => PdfColor.fromInt(color.toARGB32());

Future<String?> _myDisplayNameForFilename() async {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;
  final row = await supabase
      .from('profiles')
      .select('display_name')
      .eq('user_id', userId)
      .maybeSingle();
  final displayName = row?['display_name'] as String?;
  if (displayName != null && displayName.trim().isNotEmpty) return displayName;
  return supabase.auth.currentUser?.email?.split('@').first;
}

/// Нікнейм не має обмежень ні на довжину, ні на символи (емодзі, слеші,
/// що завгодно) — тут перетворюємо будь-який на безпечний і компактний
/// шматок імені файлу: лишаємо тільки літери (включно з кирилицею)/цифри,
/// пробіли й дефіси стають одним "_", решта прибирається, обрізаємо до
/// 24 символів. Якщо після цього нічого не лишилось (наприклад, нік був
/// суцільними емодзі) — файл лишається без імені, як і раніше, а не з
/// порожнім "_" на кінці.
String? _slugifyForFilename(String? name) {
  if (name == null) return null;
  final ascii = name
      .trim()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[^\p{L}\p{N}_-]', unicode: true), '');
  final trimmed = ascii.length > 24 ? ascii.substring(0, 24) : ascii;
  return trimmed.isEmpty ? null : trimmed;
}

// Темна тема звіту — той самий AppColors, що й сам застосунок, а не
// "офісний" білий папір. PDF як архів все одно рідко друкують, а
// візуально відірваний від бренду звіт читався як щось стороннє.
final _pdfBackground = _toPdfColor(AppColors.background);
final _pdfSurface = _toPdfColor(AppColors.surface);
final _pdfInk = _toPdfColor(AppColors.ink);
final _pdfInkMuted = _toPdfColor(AppColors.inkMuted);
final _pdfAccent = _toPdfColor(AppColors.accent);

/// Усе, що потрібно фоновому ізоляту, щоб побудувати звіт — лише прості дані
/// (без `BuildContext`/`AppLocalizations`, їх не можна передати між
/// ізолятами). Локалізовані рядки резолвляться в l10n на головному ізоляті
/// ДО виклику [Isolate.run], а не всередині — саме тому тут готові рядки,
/// а не сам об'єкт `l10n`.
class _ReportData {
  final List<CheckinEntry> monthEntries;
  final List<CheckinEntry> sortedAsc;
  final DateTime month;
  final String? subjectName;
  final Locale locale;
  final Map<MoodLevel, String> moodLabels;
  final Uint8List interFontBytes;
  final Uint8List loraFontBytes;
  final Uint8List? constellationPng;
  final String daysFilledText;
  final String moodDistributionLabel;
  final String notesSectionLabel;
  final String constellationSectionLabel;
  final String footerBrand;

  _ReportData({
    required this.monthEntries,
    required this.sortedAsc,
    required this.month,
    required this.subjectName,
    required this.locale,
    required this.moodLabels,
    required this.interFontBytes,
    required this.loraFontBytes,
    required this.constellationPng,
    required this.daysFilledText,
    required this.moodDistributionLabel,
    required this.notesSectionLabel,
    required this.constellationSectionLabel,
    required this.footerBrand,
  });
}

/// Будує PDF-звіт місяця (календар + розподіл настроїв + інсайти + нотатки)
/// і відкриває системний шер-лист. Викликається з History-екрана.
Future<void> shareMonthReport({
  required BuildContext context,
  required List<CheckinEntry> monthEntries,
  required DateTime month,
  String? subjectName,
}) async {
  final l10n = AppLocalizations.of(context);
  final locale = Localizations.localeOf(context);
  final moodLabels = {for (final m in MoodLevel.values) m: m.label(context)};

  final entriesByDay = <int, CheckinEntry>{};
  for (final entry in monthEntries) {
    entriesByDay[entry.createdAt.day] = entry;
  }
  final sortedAsc = [...monthEntries]
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  final today = DateTime.now();
  final isCurrentMonth = month.year == today.year && month.month == today.month;
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  final consideredDays = isCurrentMonth ? today.day : daysInMonth;
  final filled = entriesByDay.length;
  final missed = (consideredDays - filled).clamp(0, consideredDays);

  // Статичні (не variable) збірки — пакет `pdf` не вміє парсити variable
  // TTF-файли, якими користується решта застосунку (див. коментар у pubspec.yaml).
  final interData = await rootBundle.load(
    'assets/fonts/Inter-Static-Regular.ttf',
  );
  final loraData = await rootBundle.load('assets/fonts/Lora-Static-Bold.ttf');

  // Растеризація потребує рушія рендеру Flutter, тож тільки тут, на
  // головному ізоляті, ДО Isolate.run нижче — сам PNG (Uint8List) після
  // цього вже звичайні байти, які спокійно перетинають межу ізолятів.
  final constellationPng = entriesByDay.isEmpty
      ? null
      : await renderConstellationPng(
          entriesByDay: entriesByDay,
          daysInMonth: daysInMonth,
          year: month.year,
          month: month.month,
        );

  final data = _ReportData(
    monthEntries: monthEntries,
    sortedAsc: sortedAsc,
    month: month,
    subjectName: subjectName,
    locale: locale,
    moodLabels: moodLabels,
    interFontBytes: interData.buffer.asUint8List(),
    loraFontBytes: loraData.buffer.asUint8List(),
    constellationPng: constellationPng,
    daysFilledText: l10n.reportDaysFilled(filled, consideredDays, missed),
    moodDistributionLabel: l10n.reportMoodDistribution,
    notesSectionLabel: l10n.reportNotesSection,
    constellationSectionLabel: l10n.reportConstellationSection,
    footerBrand: l10n.reportFooterBrand,
  );

  // Побудова дерева pw-віджетів і `doc.save()` (кодування зображень у PDF)
  // — важка синхронна CPU-робота без жодної точки await усередині. На
  // головному ізоляті вона блокує UI-потік цілком, тож навіть спінер
  // завантаження застигає замість крутитись — саме це юзер побачив і
  // сприйняв як "зависання". `Isolate.run` виносить цю роботу на фоновий
  // потік, головний ізолят лишається вільним малювати кадри.
  final bytes = await Isolate.run(() => _buildReportBytes(data));

  // Хто саме — інакше файл завжди "nepogano_2026-08.pdf" незалежно від
  // юзера, і якщо друг, який теж користується застосунком, скине свій
  // такого ж місяця, файли візуально не розрізнити в списку завантажень.
  // Для власного щоденника беремо display_name (той самий фолбек на
  // e-mail, що й запрошення друга у `friends_screen.dart`, бо
  // display_name теоретично може бути NULL у зовсім старих акаунтів);
  // для щоденника сутності — subjectName вже переданий викликом.
  final nameForFile = subjectName ?? await _myDisplayNameForFilename();
  final nameSlug = _slugifyForFilename(nameForFile);

  final dir = await getTemporaryDirectory();
  final monthSlug = '${month.year}-${month.month.toString().padLeft(2, '0')}';
  final fileName = nameSlug == null
      ? 'nepogano_$monthSlug.pdf'
      : 'nepogano_${monthSlug}_$nameSlug.pdf';
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);

  if (!context.mounted) return;
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path)],
      sharePositionOrigin: shareOriginFrom(context),
    ),
  );
}

Future<Uint8List> _buildReportBytes(_ReportData data) async {
  final baseFont = pw.Font.ttf(data.interFontBytes.buffer.asByteData());
  final headingFont = pw.Font.ttf(data.loraFontBytes.buffer.asByteData());

  final entriesByDay = <int, CheckinEntry>{};
  for (final entry in data.monthEntries) {
    entriesByDay[entry.createdAt.day] = entry;
  }

  // Рахуємо тут, а не через `LayoutBuilder` у самих записах нотаток —
  // `LayoutBuilder` не спанsuch, розбиває пагінацію (див. коментар біля
  // `_buildNoteEntry`). Ширина відома наперед: A4 мінус ті самі поля, що
  // нижче в `pageTheme.margin`.
  const pageMargin = 32.0;
  final contentWidth = PdfPageFormat.a4.width - pageMargin * 2;

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        margin: const pw.EdgeInsets.symmetric(
          horizontal: pageMargin,
          vertical: 36,
        ),
        theme: pw.ThemeData.withFont(base: baseFont, bold: headingFont)
            .copyWith(
              defaultTextStyle: pw.TextStyle(font: baseFont, color: _pdfInk),
            ),
        buildBackground: (ctx) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(color: _pdfBackground),
        ),
      ),
      header: (ctx) => ctx.pageNumber == 1
          ? pw.SizedBox()
          : pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(bottom: 12),
              child: pw.Text(
                '${monthName(data.month.month, data.locale)} ${data.month.year}',
                style: pw.TextStyle(fontSize: 9, color: _pdfInkMuted),
              ),
            ),
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerLeft,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text(
          data.footerBrand,
          style: pw.TextStyle(fontSize: 8, color: _pdfInkMuted),
        ),
      ),
      build: (ctx) => [
        _buildHeader(data, headingFont),
        pw.SizedBox(height: 24),
        _buildCalendar(data.monthEntries, data.month, data.locale, baseFont),
        pw.SizedBox(height: 24),
        _buildMoodDistribution(data, entriesByDay),
        pw.SizedBox(height: 20),
        pw.Text(
          data.daysFilledText,
          style: pw.TextStyle(fontSize: 11, color: _pdfInk),
        ),
        pw.SizedBox(height: 24),
        if (data.sortedAsc.isNotEmpty)
          ..._buildNotesSection(data, headingFont, contentWidth),
        // Бонусом в кінці, не на видному місці зверху — декоративний вигляд
        // місяця, не функціональна частина звіту (та сама причина, з якої
        // в самому застосунку це окремий тогл, а не заміна календаря).
        if (data.constellationPng != null) ...[
          pw.SizedBox(height: 28),
          pw.Text(
            data.constellationSectionLabel,
            style: pw.TextStyle(
              font: headingFont,
              fontSize: 15,
              color: _pdfInk,
            ),
          ),
          pw.SizedBox(height: 10),
          // Ширина = та сама вузька колонка нотаток вище (contentWidth -
          // rightGap із _buildNotesSection), а не довільна частка сторінки
          // — щоб не виглядало ширшим/окремим блоком від тексту над ним.
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.SizedBox(
              width: contentWidth * 0.5,
              height: contentWidth * 0.5,
              child: pw.Image(pw.MemoryImage(data.constellationPng!)),
            ),
          ),
        ],
      ],
    ),
  );

  return doc.save();
}

pw.Widget _buildHeader(_ReportData data, pw.Font headingFont) {
  final title = data.subjectName == null
      ? '${monthName(data.month.month, data.locale)} ${data.month.year}'
      : '${monthName(data.month.month, data.locale)} ${data.month.year} · ${data.subjectName}';
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Nepogano',
        style: pw.TextStyle(font: headingFont, fontSize: 14, color: _pdfAccent),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        title,
        style: pw.TextStyle(font: headingFont, fontSize: 24, color: _pdfInk),
      ),
    ],
  );
}

pw.Widget _buildCalendar(
  List<CheckinEntry> monthEntries,
  DateTime month,
  Locale locale,
  pw.Font baseFont,
) {
  final entriesByDay = <int, CheckinEntry>{};
  for (final entry in monthEntries) {
    entriesByDay[entry.createdAt.day] = entry;
  }
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  final leadingBlanks = DateTime(month.year, month.month, 1).weekday - 1;
  final totalCells = leadingBlanks + daysInMonth;
  final rows = (totalCells / 7).ceil();

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        children: List.generate(7, (i) => i + 1)
            .map(
              (weekday) => pw.Expanded(
                child: pw.Center(
                  child: pw.Text(
                    weekdayLabel(weekday, locale),
                    style: pw.TextStyle(fontSize: 9, color: _pdfInkMuted),
                  ),
                ),
              ),
            )
            .toList(),
      ),
      pw.SizedBox(height: 6),
      for (var r = 0; r < rows; r++)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 5),
          child: pw.Row(
            children: List.generate(7, (c) {
              final index = r * 7 + c;
              final day = index - leadingBlanks + 1;
              if (index < leadingBlanks || day > daysInMonth) {
                return pw.Expanded(child: pw.SizedBox(height: 26));
              }
              final entry = entriesByDay[day];
              return pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 2),
                  child: pw.Container(
                    height: 26,
                    alignment: pw.Alignment.center,
                    decoration: pw.BoxDecoration(
                      color: entry != null
                          ? _toPdfColor(entry.mood.color)
                          : _pdfSurface,
                      borderRadius: pw.BorderRadius.circular(5),
                    ),
                    child: pw.Text(
                      '$day',
                      style: pw.TextStyle(
                        fontSize: 9,
                        color: entry != null ? PdfColors.white : _pdfInkMuted,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
    ],
  );
}

pw.Widget _buildMoodDistribution(
  _ReportData data,
  Map<int, CheckinEntry> entriesByDay,
) {
  final counts = <MoodLevel, int>{};
  for (final entry in entriesByDay.values) {
    counts[entry.mood] = (counts[entry.mood] ?? 0) + 1;
  }
  final moodsWithData = MoodLevel.values
      .where((m) => (counts[m] ?? 0) > 0)
      .toList();
  if (moodsWithData.isEmpty) return pw.SizedBox();

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        data.moodDistributionLabel,
        style: pw.TextStyle(fontSize: 11, color: _pdfInkMuted),
      ),
      pw.SizedBox(height: 10),
      pw.Row(
        children: moodsWithData.map((mood) {
          return pw.Expanded(
            flex: counts[mood]!,
            child: pw.Container(
              height: 8,
              margin: pw.EdgeInsets.only(
                right: mood == moodsWithData.last ? 0 : 3,
              ),
              decoration: pw.BoxDecoration(
                color: _toPdfColor(mood.color),
                borderRadius: pw.BorderRadius.circular(4),
              ),
            ),
          );
        }).toList(),
      ),
      pw.SizedBox(height: 10),
      pw.Wrap(
        spacing: 16,
        runSpacing: 4,
        children: moodsWithData.map((mood) {
          return pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Container(
                width: 7,
                height: 7,
                decoration: pw.BoxDecoration(
                  color: _toPdfColor(mood.color),
                  shape: pw.BoxShape.circle,
                ),
              ),
              pw.SizedBox(width: 5),
              pw.Text(
                '${data.moodLabels[mood]} · ${counts[mood]}',
                style: pw.TextStyle(fontSize: 10, color: _pdfInkMuted),
              ),
            ],
          );
        }).toList(),
      ),
    ],
  );
}

// Патерн по дню тижня ("настрій частіше просідає у суботу") свідомо НЕ
// рахується тут: у межах одного місяця кожен день тижня трапляється лише
// ~4 рази — цього недостатньо для чесного висновку про закономірність,
// навіть якщо формально пройде поріг "нижче за середнє". Показувати це
// як впевнене твердження вводило б в оману сильніше, ніж просто не
// показувати нічого. Для такого інсайту треба вікно в кілька місяців,
// не один. Сам рядок ("Заповнено N з M днів") резолвиться через l10n на
// головному ізоляті заздалегідь (`data.daysFilledText`) — тут лишається
// тільки цифри/логіка, без `AppLocalizations`.

// Повна ширина сторінки на телефоні читалась як суцільна нескінченна
// стрічка — звужуємо праву частину через фіксований відступ.
//
// Три окремі речі довелось виправляти по черзі, жодна не була тим, що
// здавалось спочатку:
// (1) `pw.Text` НЕ спанситься між сторінками за замовчуванням —
//     `overflow` за замовчуванням `TextOverflow.visible`, а `canSpan`
//     дослівно перевіряє `overflow == TextOverflow.span`. Без явного
//     `overflow: pw.TextOverflow.span` довгий текст завжди трактується
//     як нероздільний блок, хай як його не обгортай.
// (2) Навіть зі `span`, текст мусить бути ПРЯМИМ елементом списку, який
//     обробляє сам `MultiPage` (`build:` нижче) — не вкладеним у
//     `Column`. `Column.layout()` міряє кожну дитину на її ПОВНУ
//     природну висоту (жодного обмеження по висоті на дочірні елементи
//     під час звичайного проходу) і просто вирішує, скільки цілих
//     дочірніх елементів влізло — вона не вміє "заглянути всередину"
//     однієї дитини й розбити САМЕ її.
// (3) Спроби дозволити `span` для самого тексту нотатки (щоб довгий
//     запис розбивався по сторінках, а не переїжджав цілком) послідовно
//     впирались у ту саму родину багів: розрив МІЖ датою й нотаткою, що
//     стали окремими елементами; потім розрив ВСЕРЕДИНІ одного
//     об'єднаного `RichText` рівно після рядка дати, без жодного
//     мінімуму нижче; потім те саме на рівень нижче для звичайних
//     нетривіальних заміток. Кожен наступний фікс усував один конкретний
//     симптом, залишаючи відкритою ту саму родину — "розбиття по рядках
//     без поняття, скільки лишилось на сторінці" не має природного
//     мінімуму, який можна виставити наперед константою.
//
//     Тому спан ПРИБРАНО повністю: кожен запис (дата+крапка+нотатка) —
//     ОДИН нероздільний `RichText`, який просто цілком переїжджає на
//     наступну сторінку, якщо не влазить. Ціна — для дуже довгого запису
//     може лишитись помітно порожнє місце внизу попередньої сторінки;
//     натомість жоден запис ніколи не виглядає розірваним чи сиротою.
//     Свідомий вибір простоти й передбачуваності над економією місця.
//
//     Без span нероздільний запис, ВИЩИЙ за цілу сторінку, кинув би
//     `PdfException` і зламав увесь експорт місяця — тому це безпечно
//     лише тому, що `_noteMaxLength` (`main.dart`) навмисно знижений до
//     1500 символів саме з розрахунком на це: із запасом менше за
//     будь-яку реалістичну висоту сторінки. Якщо ліміт нотатки чек-іну
//     колись підніматиметься знову — спершу перевірити цей файл.
List<pw.Widget> _buildNotesSection(
  _ReportData data,
  pw.Font headingFont,
  double contentWidth,
) {
  final rightGap = contentWidth * 0.5;
  return [
    pw.Text(
      data.notesSectionLabel,
      style: pw.TextStyle(font: headingFont, fontSize: 15, color: _pdfInk),
    ),
    pw.SizedBox(height: 10),
    for (final entry in data.sortedAsc)
      ..._buildNoteEntryWidgets(entry, rightGap),
  ];
}

// Фото навмисно НЕ вбудовуються (пробували — і мініатюру під текстом, і
// поруч із текстом, обидва варіанти на реальному контенті виглядали
// невдало: під текстом розтягувало кожен запис і ламало ритм читання
// списку, поруч — не завжди вдало компонувалось з дуже різною довжиною
// нотаток). Лишили голий текст, найчитабельніший варіант із перевірених.
List<pw.Widget> _buildNoteEntryWidgets(CheckinEntry entry, double rightGap) {
  final hasNote = entry.note != null && entry.note!.trim().isNotEmpty;
  final dateStr =
      '${entry.createdAt.day}.${entry.createdAt.month}.${entry.createdAt.year}';

  return [
    pw.Padding(
      padding: pw.EdgeInsets.only(right: rightGap, bottom: 10),
      // Свідомо БЕЗ overflow: span — цілий запис нероздільний: якщо не
      // влазить цілком на залишок сторінки, MultiPage переносить його
      // ЦІЛКОМ на наступну. Дата ніколи не лишається без нотатки, і
      // нотатка ніколи не з'являється без дати — ціна за це проста:
      // інколи трохи порожнього місця внизу попередньої сторінки.
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: '● ',
              style: pw.TextStyle(
                fontSize: 8,
                color: _toPdfColor(entry.mood.color),
              ),
            ),
            pw.TextSpan(
              text: hasNote ? '$dateStr\n' : dateStr,
              style: pw.TextStyle(fontSize: 10, color: _pdfInkMuted),
            ),
            if (hasNote)
              pw.TextSpan(
                text: entry.note!.trim(),
                style: pw.TextStyle(fontSize: 11, color: _pdfInk),
              ),
          ],
        ),
      ),
    ),
  ];
}
