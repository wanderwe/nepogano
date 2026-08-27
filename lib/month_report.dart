import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Border;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'date_labels.dart';
import 'history_screen.dart';
import 'l10n/app_localizations.dart';
import 'main.dart';
import 'photo_storage.dart';
import 'share_utils.dart';
import 'style.dart';

PdfColor _toPdfColor(Color color) => PdfColor.fromInt(color.toARGB32());

// Темна тема звіту — той самий AppColors, що й сам застосунок, а не
// "офісний" білий папір. PDF як архів все одно рідко друкують, а
// візуально відірваний від бренду звіт читався як щось стороннє.
final _pdfBackground = _toPdfColor(AppColors.background);
final _pdfSurface = _toPdfColor(AppColors.surface);
final _pdfInk = _toPdfColor(AppColors.ink);
final _pdfInkMuted = _toPdfColor(AppColors.inkMuted);
final _pdfAccent = _toPdfColor(AppColors.accent);

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

  // Статичні (не variable) збірки — пакет `pdf` не вміє парсити variable
  // TTF-файли, якими користується решта застосунку (див. коментар у pubspec.yaml).
  final interData = await rootBundle.load(
    'assets/fonts/Inter-Static-Regular.ttf',
  );
  final loraData = await rootBundle.load('assets/fonts/Lora-Static-Bold.ttf');
  final baseFont = pw.Font.ttf(interData);
  final headingFont = pw.Font.ttf(loraData);

  final entriesByDay = <int, CheckinEntry>{};
  for (final entry in monthEntries) {
    entriesByDay[entry.createdAt.day] = entry;
  }
  final sortedAsc = [...monthEntries]
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  // Фото завантажуються заздалегідь, до побудови дерева `pw`-віджетів —
  // на відміну від звичайних Flutter-віджетів, у пакета `pdf` немає
  // FutureBuilder-подібного механізму: усе дерево будується синхронно.
  // Той самий `downloadCheckinPhoto`, що й так вже викликається при
  // відкритті Історії за цей місяць — тож для юзера це не новий трафік,
  // а перевикористання того, що й без цього довантажилось би на екран.
  final photoEntries = sortedAsc.where((e) => e.photoPath != null).toList();
  final photoResults = await Future.wait(
    photoEntries.map((e) => downloadCheckinPhoto(e.photoPath!)),
  );
  final photosById = <String, Uint8List>{
    for (var i = 0; i < photoEntries.length; i++)
      if (photoResults[i] != null) photoEntries[i].id: photoResults[i]!,
  };

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 36),
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
                '${monthName(month.month, locale)} ${month.year}',
                style: pw.TextStyle(fontSize: 9, color: _pdfInkMuted),
              ),
            ),
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerLeft,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text(
          l10n.reportFooterBrand,
          style: pw.TextStyle(fontSize: 8, color: _pdfInkMuted),
        ),
      ),
      build: (ctx) => [
        _buildHeader(l10n, locale, month, subjectName, headingFont),
        pw.SizedBox(height: 24),
        _buildCalendar(monthEntries, month, locale, baseFont),
        pw.SizedBox(height: 24),
        _buildMoodDistribution(l10n, entriesByDay, moodLabels),
        pw.SizedBox(height: 20),
        _buildInsights(l10n, entriesByDay, month),
        pw.SizedBox(height: 24),
        if (sortedAsc.isNotEmpty)
          _buildNotesSection(l10n, sortedAsc, headingFont, photosById),
      ],
    ),
  );

  final bytes = await doc.save();
  final dir = await getTemporaryDirectory();
  final monthSlug = '${month.year}-${month.month.toString().padLeft(2, '0')}';
  final file = File('${dir.path}/nepogano_$monthSlug.pdf');
  await file.writeAsBytes(bytes, flush: true);

  if (!context.mounted) return;
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path)],
      sharePositionOrigin: shareOriginFrom(context),
    ),
  );
}

pw.Widget _buildHeader(
  AppLocalizations l10n,
  Locale locale,
  DateTime month,
  String? subjectName,
  pw.Font headingFont,
) {
  final title = subjectName == null
      ? '${monthName(month.month, locale)} ${month.year}'
      : '${monthName(month.month, locale)} ${month.year} · $subjectName';
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
  AppLocalizations l10n,
  Map<int, CheckinEntry> entriesByDay,
  Map<MoodLevel, String> moodLabels,
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
        l10n.reportMoodDistribution,
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
                '${moodLabels[mood]} · ${counts[mood]}',
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
// не один.
// Один рядок, без маркера-крапки на початку — той мав сенс, поки під ним
// був ще другий пункт (прогноз по днях тижня, прибраний як статистично
// ненадійний на місячному вікні). Самотня крапка перед єдиним реченням
// виглядала як сирота, не як список.
pw.Widget _buildInsights(
  AppLocalizations l10n,
  Map<int, CheckinEntry> entriesByDay,
  DateTime month,
) {
  final today = DateTime.now();
  final isCurrentMonth = month.year == today.year && month.month == today.month;
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  final consideredDays = isCurrentMonth ? today.day : daysInMonth;
  final filled = entriesByDay.length;
  final missed = (consideredDays - filled).clamp(0, consideredDays);

  return pw.Text(
    l10n.reportDaysFilled(filled, consideredDays, missed),
    style: pw.TextStyle(fontSize: 11, color: _pdfInk),
  );
}

// Повна ширина сторінки на телефоні читалась як суцільна нескінченна
// стрічка (рядки завдовжки на весь екран). Пробував справжні 2 колонки
// через `Partitions` — але цей віджет резервує місце наперед і, якщо не
// влазить ціле, кидає весь блок на наступну сторінку (порожня половина
// першої сторінки, як показав юзер). Та сама проблема була б із будь-яким
// одним великим `LayoutBuilder`-обгортанням навколо всього списку — він
// сам не вміє текти через сторінки, тож блок так само стрибав би
// цілком. Рішення: кожен запис лишається ОКРЕМИМ прямим елементом
// зовнішньої `Column` (як і було до колонок) — це те, що вміє коректно
// розбиватись між сторінками — а `LayoutBuilder` обгортає лише ОДИН
// запис за раз, щоб виміряти доступну ширину й підрізати праву частину.
pw.Widget _buildNotesSection(
  AppLocalizations l10n,
  List<CheckinEntry> sortedAsc,
  pw.Font headingFont,
  Map<String, Uint8List> photosById,
) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        l10n.reportNotesSection,
        style: pw.TextStyle(font: headingFont, fontSize: 15, color: _pdfInk),
      ),
      pw.SizedBox(height: 10),
      for (final entry in sortedAsc)
        _buildNoteEntry(entry, photosById[entry.id]),
    ],
  );
}

// Фото завжди ПІД текстом, фіксованого мініатюрного розміру — не поруч
// із текстом: колонка й так звужена вдвічі, а довжина нотатки заздалегідь
// невідома (від одного слова до кількох абзаців), тож розміщення поруч
// лишало б то величезну порожню діру біля короткого запису, то тісноту
// біля довгого. Фіксований розмір знизу від тексту уникає цього завжди.
pw.Widget _buildNoteEntry(CheckinEntry entry, Uint8List? photoBytes) {
  return pw.LayoutBuilder(
    builder: (context, constraints) {
      final rightGap = constraints!.maxWidth * 0.5;
      return pw.Padding(
        padding: pw.EdgeInsets.only(bottom: 10, right: rightGap),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              children: [
                pw.Container(
                  width: 7,
                  height: 7,
                  margin: const pw.EdgeInsets.only(right: 6),
                  decoration: pw.BoxDecoration(
                    color: _toPdfColor(entry.mood.color),
                    shape: pw.BoxShape.circle,
                  ),
                ),
                pw.Text(
                  '${entry.createdAt.day}.${entry.createdAt.month}.${entry.createdAt.year}',
                  style: pw.TextStyle(fontSize: 10, color: _pdfInkMuted),
                ),
              ],
            ),
            if (entry.note != null && entry.note!.trim().isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 3, left: 13),
                child: pw.Text(
                  entry.note!.trim(),
                  style: pw.TextStyle(fontSize: 11, color: _pdfInk),
                ),
              ),
            if (photoBytes != null)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 6, left: 13),
                child: pw.ClipRRect(
                  horizontalRadius: 6,
                  verticalRadius: 6,
                  child: pw.SizedBox(
                    height: 90,
                    width: 90 * kCompactPhotoAspectRatio,
                    child: pw.Image(
                      pw.MemoryImage(photoBytes),
                      fit: pw.BoxFit.cover,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
