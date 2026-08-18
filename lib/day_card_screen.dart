import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'date_labels.dart';
import 'history_screen.dart';
import 'l10n/app_localizations.dart';
import 'main.dart';
import 'photo_storage.dart';
import 'share_utils.dart';
import 'social_share.dart';
import 'style.dart';

class DayCardScreen extends StatefulWidget {
  final CheckinEntry entry;
  // Якщо картка належить щоденнику сутності (дитина/улюбленець), а не
  // власному чек-іну — підписуємо шер її іменем, а не "Мій день".
  final String? subjectName;

  const DayCardScreen({super.key, required this.entry, this.subjectName});

  @override
  State<DayCardScreen> createState() => _DayCardScreenState();
}

class _DayCardScreenState extends State<DayCardScreen> {
  final _boundaryKey = GlobalKey();
  bool _sharing = false;
  bool _photoLoading = false;
  Uint8List? _photoBytes;

  String get _shareText {
    final l10n = AppLocalizations.of(context);
    final name = widget.subjectName;
    return name == null
        ? l10n.myDayInNepogano
        : l10n.subjectDayInNepogano(name);
  }

  @override
  void initState() {
    super.initState();
    final photoPath = widget.entry.photoPath;
    if (photoPath != null) {
      _photoLoading = true;
      downloadCheckinPhoto(photoPath).then((bytes) {
        if (!mounted) return;
        setState(() {
          _photoBytes = bytes;
          _photoLoading = false;
        });
      });
    }
  }

  Future<String> _renderCardToFile() async {
    final boundary =
        _boundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/nepogano_day_card.png');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    final shareText = _shareText;
    try {
      final path = await _renderCardToFile();
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          text: shareText,
          sharePositionOrigin: shareOriginFrom(context),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).shareFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _openMultiShareSheet() async {
    setState(() => _sharing = true);
    String path;
    try {
      path = await _renderCardToFile();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).prepareCardFailed),
          ),
        );
      }
      setState(() => _sharing = false);
      return;
    }
    setState(() => _sharing = false);

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (context) =>
          _MultiShareSheet(imagePath: path, shareText: _shareText),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SingleChildScrollView(
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
                    Text(l10n.dayCard, style: appScreenTitle()),
                  ],
                ),
                const SizedBox(height: 32),
                Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(boxShadow: AppShadows.soft),
                    child: _photoLoading
                        ? const SizedBox(
                            width: _cardWidth,
                            height: _cardHeight,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : RepaintBoundary(
                            key: _boundaryKey,
                            child: _DayCard(
                              entry: widget.entry,
                              photoBytes: _photoBytes,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (_sharing || _photoLoading) ? null : _share,
                    icon: _sharing
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accentInk,
                            ),
                          )
                        : const Icon(PhosphorIconsLight.export, size: 18),
                    label: Text(l10n.share),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: (_sharing || _photoLoading)
                        ? null
                        : _openMultiShareSheet,
                    child: Text(l10n.shareOnSocial),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MultiShareSheet extends StatefulWidget {
  final String imagePath;
  final String shareText;

  const _MultiShareSheet({required this.imagePath, required this.shareText});

  @override
  State<_MultiShareSheet> createState() => _MultiShareSheetState();
}

class _MultiShareSheetState extends State<_MultiShareSheet> {
  final Set<String> _done = {};

  Future<void> _shareInstagram() async {
    final ok = await SocialShare.instagramStory(widget.imagePath);
    if (!ok && mounted) {
      _showNotInstalled('Instagram');
      return;
    }
    if (mounted) setState(() => _done.add('instagram'));
  }

  Future<void> _shareTikTok() async {
    var ok = await SocialShare.toPackage(
      widget.imagePath,
      'com.zhiliaoapp.musically',
    );
    if (!ok) {
      ok = await SocialShare.toPackage(
        widget.imagePath,
        'com.ss.android.ugc.trill',
      );
    }
    if (!ok && mounted) {
      _showNotInstalled('TikTok');
      return;
    }
    if (mounted) setState(() => _done.add('tiktok'));
  }

  Future<void> _shareOther() async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(widget.imagePath)],
          text: widget.shareText,
          sharePositionOrigin: shareOriginFrom(context),
        ),
      );
      if (mounted) setState(() => _done.add('other'));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).shareFailed)),
        );
      }
    }
  }

  void _showNotInstalled(String app) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).notInstalled(app))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.shareOnSocial, style: appScreenTitle(fontSize: 18)),
              const SizedBox(height: 4),
              Text(
                l10n.shareEverywhereHint,
                style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
              ),
              const SizedBox(height: 20),
              // Instagram Stories тепер має нативного відповідача на обох
              // платформах (MainActivity.kt / AppDelegate.swift), той самий
              // публічний контракт, різний лише механізм (intent vs
              // pasteboard+URL scheme) — тому без гейту по платформі.
              // TikTok лишається лише на Android: там це загальний
              // ACTION_SEND, спрямований на пакет TikTok, а публічного
              // еквівалента такого "спрямованого інтенту" на iOS немає —
              // прямий шер туди вимагав би реєстрації в TikTok for
              // Developers і їхнього SDK, окрема, набагато більша задача.
              // Facebook свідомо прибраний: немає публічного
              // Stories-контракту, як в Instagram (`ADD_TO_STORY`), тож
              // прямий шер падав на власний внутрішній вибір застосунку
              // Facebook замість чіткого переходу в Stories — а Instagram
              // Stories й так вміє дублювати в Facebook Stories зі своїх
              // налаштувань, окрема кнопка тут переважно дублювала цю
              // можливість.
              _ShareRow(
                label: 'Instagram Stories',
                done: _done.contains('instagram'),
                onTap: _shareInstagram,
              ),
              if (Platform.isAndroid)
                _ShareRow(
                  label: 'TikTok',
                  done: _done.contains('tiktok'),
                  onTap: _shareTikTok,
                ),
              _ShareRow(
                label: l10n.other,
                done: _done.contains('other'),
                onTap: _shareOther,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.done),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareRow extends StatelessWidget {
  final String label;
  final bool done;
  final VoidCallback onTap;

  const _ShareRow({
    required this.label,
    required this.done,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 16, color: AppColors.ink),
              ),
            ),
            Icon(
              // Контурна галочка акцентного кольору, не заповнена зелена —
              // ОС не повертає жоден сигнал "юзер справді опублікував" (ні
              // для прямого запуску Instagram/TikTok, ні для системного
              // шер-вікна "Інше"), тому "done" тут чесно означає лише
              // "відкрито", а не "успішно поширено". Той самий вигляд для
              // всіх варіантів — не вдавати, ніби для когось із них є
              // надійніший сигнал, ніж для решти.
              done
                  ? PhosphorIconsLight.checkCircle
                  : PhosphorIconsLight.caretRight,
              size: 20,
              color: done ? AppColors.accent : AppColors.inkMuted,
            ),
          ],
        ),
      ),
    );
  }
}

// 9:16 — той самий кадр, що й Instagram/TikTok Stories, куди картку
// найчастіше й шерять. Раніше висота йшла "скільки контенту вистачить"
// (без фото — приземкувата, з довгою нотаткою й фото — випадково витягнута
// сильніше за сам формат історій), і в самих Stories це висіло маленьким
// прямокутником посеред порожнього кадру замість заповнювати його.
const _cardWidth = 320.0;
const _cardHeight = _cardWidth * 16 / 9;

class _DayCard extends StatelessWidget {
  final CheckinEntry entry;
  final Uint8List? photoBytes;

  const _DayCard({required this.entry, this.photoBytes});

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final l10n = AppLocalizations.of(context);
    final d = entry.createdAt;
    final dateLabel = '${d.day} ${monthNameGenitive(d.month, locale)}';
    final weekdayName = weekdayNameFull(d.weekday, locale);
    final noteText = entry.note?.trim();
    final hasNote = noteText != null && noteText.isNotEmpty;
    final hasPhoto = photoBytes != null;

    // Тінь під текстом — і на заголовку, і на нотатці, і на даті — не дає
    // тексту зливатись із фото незалежно від того, яке саме воно (світле
    // небо, темний ліс, строкатий фон): скрім-градієнти покривають типовий
    // випадок, тінь підстраховує на межах чи нетипово яскравих ділянках.
    const photoTextShadow = [
      Shadow(color: Color(0xB3000000), blurRadius: 6, offset: Offset(0, 1)),
    ];

    final headline = Text.rich(
      TextSpan(
        style: appSerif(
          fontSize: hasPhoto ? 20 : 32,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          height: 1.2,
        ).copyWith(shadows: hasPhoto ? photoTextShadow : null),
        children: [
          TextSpan(text: '${l10n.todayWasPrefix} '),
          TextSpan(
            text: entry.mood.label(context).toLowerCase(),
            style: TextStyle(color: entry.mood.color),
          ),
        ],
      ),
      textAlign: hasPhoto ? TextAlign.left : TextAlign.center,
    );

    final updatedLabel = entry.updateCount > 0
        ? l10n.updatedCount(entry.updateCount)
        : null;

    return Container(
      // Навмисно без borderRadius/clip: це саме той віджет, що йде у
      // RepaintBoundary.toImage() для шеру. Заокруглені кути означали б
      // прозорі трикутники по кутах експортованого PNG — а прозорість там,
      // де накладається чужий фон (сторіс, месенджер), не контрольована:
      // хост сам домальовує туди щось своє (тінь стікера тощо), і виходить
      // видима "виїмка" в кутах. Суцільний прямокутник цього не має.
      // Гострота кутів пом'якшена косметично — див. віньєтку внизу build().
      width: _cardWidth,
      height: _cardHeight,
      color: const Color(0xFF141414),
      child: Stack(
        fit: StackFit.expand,
        children: [
          hasPhoto
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    // Кадр картки завжди 9:16, а не kPhotoAspectRatio (квадрат
                    // у рамці позиціювання при чек-іні) — той квадрат обраний
                    // під місце для кнопок у формі, тут такого обмеження нема.
                    // Фото фізично не обрізане під квадрат, лиш показане в
                    // ньому — тому ширший кадр із тим самим photoAlignY/Scale
                    // просто розкриває більше того самого кадрування, а не
                    // показує щось інше, ніж юзер підбирав.
                    ScaledPhoto(
                      scale: entry.photoScale,
                      child: Image.memory(
                        photoBytes!,
                        fit: BoxFit.cover,
                        alignment: Alignment(0, entry.photoAlignY),
                      ),
                    ),
                    // Знизу — темніший і вищий скрім (там основний текст,
                    // потребує найбільше контрасту), зверху — коротший і
                    // легший (там лише дата). Обидва тримають текст читабельним
                    // незалежно від того, яке саме фото — світле небо, темний
                    // ліс чи щось строкате.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xE6000000), Color(0x00000000)],
                          stops: [0, 0.55],
                        ),
                      ),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x99000000), Color(0x00000000)],
                          stops: [0, 0.18],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 20,
                      left: 20,
                      child: Text(
                        '$dateLabel · $weekdayName',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xD9FFFFFF),
                          shadows: photoTextShadow,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 20,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          headline,
                          if (hasNote) ...[
                            const SizedBox(height: 8),
                            Text(
                              noteText,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xD9FFFFFF),
                                height: 1.4,
                                shadows: photoTextShadow,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                updatedLabel ?? '',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0x99FFFFFF),
                                ),
                              ),
                              const Text(
                                'nepogano.app',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0x99FFFFFF),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.5),
                      radius: 1.1,
                      colors: [
                        entry.mood.color.withValues(alpha: 0.32),
                        const Color(0xFF141414),
                      ],
                      stops: const [0, 0.75],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              dateLabel,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade400,
                              ),
                            ),
                            Text(
                              weekdayName,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ],
                        ),
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                headline,
                                if (hasNote) ...[
                                  const SizedBox(height: 16),
                                  Text(
                                    noteText,
                                    textAlign: TextAlign.center,
                                    maxLines: 6,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      color: AppColors.ink,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              updatedLabel ?? '',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              'nepogano.app',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
          // Легка віньєтка поверх усього: чисто косметичне пом'якшення
          // гострих кутів (оптична ілюзія через градієнт, не прозорість) —
          // сама картка лишається суцільним непрозорим прямокутником, тож
          // безпечна для full-screen фону в Instagram/TikTok (коментар
          // вище). Найтемніша рівно в кутах (найдальші точки від центру),
          // прозора в межах більшої частини кадру, де сидять фото й текст.
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.9,
                  colors: [Colors.transparent, Color(0x40000000)],
                  stops: [0.55, 1],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
