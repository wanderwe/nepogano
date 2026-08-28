import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'l10n/app_localizations.dart';
import 'style.dart';

/// Дає перетягнути фото вертикально й наблизити пінчем у рамці тієї ж
/// пропорції (`kPhotoAspectRatio`), що й картка дня — щоб підняти/опустити
/// видиму частину або наблизити, якщо BoxFit.cover десь зрізав важливе
/// (наприклад, голову). Повертає `(alignY, scale)` через Navigator.pop,
/// або null якщо закрито без змін.
class PhotoRepositionScreen extends StatefulWidget {
  final ImageProvider image;
  final double initialAlignY;
  final double initialScale;

  const PhotoRepositionScreen({
    super.key,
    required this.image,
    this.initialAlignY = 0,
    this.initialScale = 1,
  });

  @override
  State<PhotoRepositionScreen> createState() => _PhotoRepositionScreenState();
}

class _PhotoRepositionScreenState extends State<PhotoRepositionScreen> {
  late double _alignY = widget.initialAlignY;
  late double _scale = widget.initialScale;
  double _gestureStartScale = 1;

  ImageStream? _imageStream;
  late final ImageStreamListener _imageStreamListener;
  Size? _naturalSize;

  @override
  void initState() {
    super.initState();
    // Розмір фото в пікселях потрібен, щоб порахувати, скільки САМЕ
    // "зайвого" звисає за рамкою після BoxFit.cover — без цього палець і
    // формула не знають, на яку відстань реально є куди панорамувати.
    _imageStreamListener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() {
        _naturalSize = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
      });
    });
    _imageStream = widget.image.resolve(const ImageConfiguration())
      ..addListener(_imageStreamListener);
  }

  @override
  void dispose() {
    _imageStream?.removeListener(_imageStreamListener);
    super.dispose();
  }

  /// Скільки пікселів фото (у координатах рамки) звисає зверху й знизу
  /// разом після BoxFit.cover у квадратну рамку розміром [boxSize] — саме
  /// цю відстань перетягування має "з'їсти" цілком, від -1 до +1. Null,
  /// поки реальний розмір фото ще не резолвнувся, або якщо звисати
  /// нічому (майже квадратне чи ширше за рамку фото — панорамувати
  /// вертикально просто нема куди).
  double? _verticalOverflow(double boxSize) {
    final size = _naturalSize;
    if (size == null || size.width <= 0 || size.height <= 0) return null;
    final coverScale = math.max(boxSize / size.width, boxSize / size.height);
    final overflow = size.height * coverScale - boxSize;
    return overflow > 0 ? overflow : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(PhosphorIconsLight.x, size: 20),
                    tooltip: l10n.cancel,
                  ),
                  Expanded(
                    child: Text(
                      l10n.repositionPhoto,
                      textAlign: TextAlign.center,
                      style: appScreenTitle(fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l10n.repositionPhotoHint,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
              ),
              const SizedBox(height: 24),
              AspectRatio(
                aspectRatio: kPhotoAspectRatio,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: GestureDetector(
                        onScaleStart: (_) => _gestureStartScale = _scale,
                        onScaleUpdate: (details) {
                          setState(() {
                            _scale = (_gestureStartScale * details.scale).clamp(
                              1.0,
                              3.0,
                            );
                            // Мінус, не плюс: фото має "триматись" пальця,
                            // як у стандартних фоторедакторах (Instagram,
                            // Google Photos) — тягнеш вниз, і сама картинка
                            // з'їжджає вниз під пальцем, відкриваючи те, що
                            // було зверху.
                            //
                            // Ділимо на РЕАЛЬНИЙ overflow конкретного фото
                            // (не на висоту рамки) і додатково на _scale —
                            // інакше швидкість перетягування "стрибала" між
                            // фото різних пропорцій (майже квадратне фото
                            // майже нема куди панорамувати — те саме
                            // перетягування пальцем відчувалось як "повільно"
                            // проти витягнутого портрета), і додатково
                            // "прискорювалась" саму собою, щойно
                            // наближуєш пінчем (Transform.scale в
                            // ScaledPhoto множить видимий зсув). Формула
                            // нижче тримає 1px пальця ≈ 1px видимого зсуву
                            // завжди, незалежно від фото й поточного зуму.
                            final overflow = _verticalOverflow(
                              constraints.maxHeight,
                            );
                            if (overflow != null) {
                              _alignY =
                                  (_alignY -
                                          details.focalPointDelta.dy *
                                              2 /
                                              (overflow * _scale))
                                      .clamp(-1.0, 1.0);
                            }
                          });
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ScaledPhoto(
                              scale: _scale,
                              child: Image(
                                image: widget.image,
                                fit: BoxFit.cover,
                                alignment: Alignment(0, _alignY),
                              ),
                            ),
                            IgnorePointer(
                              child: _FeedCropOverlay(alignY: _alignY),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop((_alignY, _scale)),
                  child: Text(l10n.done),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Затемнює зверху й знизу квадратної рамки позиціювання ту частину, яку
/// показує ЛИШЕ картка дня (`kPhotoAspectRatio` — квадрат) — стрічка,
/// друзі й учасники кола бачать вужчу [kCompactPhotoAspectRatio] (4:3),
/// тому та сама позиція/зум може виглядати добре в картці дня, але
/// зрізати важливе (наприклад, голову) у компактному перегляді. Юзер
/// раніше дізнавався про це лише постфактум, побачивши обрізаний
/// прев'ю в Історії чи в друга.
///
/// Формула виведена геометрично, не виміряна на пікселях фото: обидві
/// рамки рендерять те саме фото на ту саму ширину через `BoxFit.cover`,
/// тож натуральний розмір фото скорочується з формули — лишається
/// тільки співвідношення висот рамок. Похибка можлива тільки для дуже
/// вузьких/панорамних фото, де ширина насправді НЕ є "зв'язуючим"
/// виміром для одного з двох `BoxFit.cover` — прийнятний компроміс для
/// візуальної підказки, не для точного розрахунку.
class _FeedCropOverlay extends StatelessWidget {
  final double alignY;

  const _FeedCropOverlay({required this.alignY});

  @override
  Widget build(BuildContext context) {
    final compactHeightFraction = kPhotoAspectRatio / kCompactPhotoAspectRatio;
    final topFraction = (1 - compactHeightFraction) * (alignY + 1) / 2;
    final bottomFraction = topFraction + compactHeightFraction;

    return LayoutBuilder(
      builder: (context, constraints) {
        final topHeight = constraints.maxHeight * topFraction;
        final bottomHeight = constraints.maxHeight * (1 - bottomFraction);
        const dim = Color(0x99000000);
        const lineColor = AppColors.accent;

        return Column(
          children: [
            SizedBox(
              height: topHeight,
              width: double.infinity,
              child: const ColoredBox(color: dim),
            ),
            Container(height: 1.5, color: lineColor),
            SizedBox(height: constraints.maxHeight - topHeight - bottomHeight),
            Container(height: 1.5, color: lineColor),
            SizedBox(
              height: bottomHeight,
              width: double.infinity,
              child: const ColoredBox(color: dim),
            ),
          ],
        );
      },
    );
  }
}
