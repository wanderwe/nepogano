import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'l10n/app_localizations.dart';
import 'style.dart';

/// Дає перетягнути фото вертикально Й ГОРИЗОНТАЛЬНО та наблизити пінчем у
/// рамці тієї ж пропорції (`kPhotoAspectRatio`), що й картка дня — щоб
/// підняти/опустити/зсунути видиму частину або наблизити, якщо BoxFit.cover
/// десь зрізав важливе (наприклад, голову чи когось скраю кадру). Повертає
/// `(alignX, alignY, scale)` через Navigator.pop, або null якщо закрито
/// без змін.
class PhotoRepositionScreen extends StatefulWidget {
  final ImageProvider image;
  final double initialAlignX;
  final double initialAlignY;
  final double initialScale;

  const PhotoRepositionScreen({
    super.key,
    required this.image,
    this.initialAlignX = 0,
    this.initialAlignY = 0,
    this.initialScale = 1,
  });

  @override
  State<PhotoRepositionScreen> createState() => _PhotoRepositionScreenState();
}

class _PhotoRepositionScreenState extends State<PhotoRepositionScreen> {
  late double _alignX = widget.initialAlignX;
  late double _alignY = widget.initialAlignY;
  late double _scale = widget.initialScale;
  double _gestureStartScale = 1;

  // Палець ніколи не рухається ідеально по прямій — з двома вільними
  // осями одразу найменше "гуляння" вбік під час вертикального
  // перетягування (чи навпаки) видно як небажаний зайвий зсув. Як
  // тільки однопальцевий дотик визначив переважний напрям (перший
  // помітний рух), решта ЦЬОГО дотику рухає лише його — дрібний шум по
  // іншій осі просто ігнорується, аж до відпускання пальця. Null між
  // дотиками й під час пінчу (там обидві осі свідомо вільні одразу —
  // це вже комбінований жест зум+пан, не потребує захисту від "гуляння").
  Axis? _panAxisLock;

  // Перший кадр жесту завжди має дрібний, майже нульовий delta (палець
  // щойно торкнувся) — замикати вісь одразу на ньому означало б замикати
  // навмання на шумі. Чекаємо, поки рух хоч по одній осі перевищить цей
  // поріг, і лише тоді визначаємо домінантну.
  static const _panAxisLockThreshold = 3.0;

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

  /// Скільки пікселів фото (у координатах рамки) звисає з відповідного боку
  /// разом після BoxFit.cover+`_scale` у квадратну рамку розміром
  /// [boxSize] — саме цю відстань перетягування має "з'їсти" цілком, від -1
  /// до +1. Null, поки реальний розмір фото ще не резолвнувся, або якщо
  /// звисати нічому (панорамувати в цей бік просто нема куди).
  ///
  /// На відміну від "базового" overflow при масштабі 1, тут МНОЖИМО на
  /// поточний `_scale` ВСЕРЕДИНІ формули (не окремим множником у виклику,
  /// як було раніше лише для вертикалі) — бо для "тісного" виміру фото
  /// (типово ширина в портретному фото) базовий overflow точно 0, і
  /// множення нуля на будь-який `_scale` так і лишилось би нулем. Реальний
  /// horizontal overflow з'являється лише ПІСЛЯ наближення пінчем
  /// (`Transform.scale` в `ScaledPhoto` розтягує вже "щільно" підігнаний
  /// вимір за межі рамки) — формула нижче це враховує з самого початку.
  double? _overflow({
    required double boxSize,
    required double naturalDimension,
    required double coverScale,
  }) {
    final overflow = naturalDimension * coverScale * _scale - boxSize;
    return overflow > 0 ? overflow : null;
  }

  double? _coverScale(double boxWidth, double boxHeight) {
    final size = _naturalSize;
    if (size == null || size.width <= 0 || size.height <= 0) return null;
    return math.max(boxWidth / size.width, boxHeight / size.height);
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
                        onScaleStart: (_) {
                          _gestureStartScale = _scale;
                          _panAxisLock = null;
                        },
                        onScaleUpdate: (details) {
                          setState(() {
                            _scale = (_gestureStartScale * details.scale).clamp(
                              1.0,
                              3.0,
                            );
                            // Мінус, не плюс: фото має "триматись" пальця,
                            // як у стандартних фоторедакторах (Instagram,
                            // Google Photos) — тягнеш, і сама картинка
                            // з'їжджає під пальцем, відкриваючи те, що було
                            // приховано за краєм.
                            //
                            // Ділимо на РЕАЛЬНИЙ overflow конкретного фото
                            // (не на розмір рамки) — інакше швидкість
                            // перетягування "стрибала" б між фото різних
                            // пропорцій (майже квадратне фото мало куди
                            // панорамувати — те саме перетягування пальцем
                            // відчувалось би як "повільно" проти
                            // витягнутого портрета). `_overflow` вже сам
                            // враховує поточний `_scale` всередині формули,
                            // тож тут його вдруге множити НЕ треба (на
                            // відміну від старої версії саме для
                            // вертикалі) — формула тримає 1px пальця ≈ 1px
                            // видимого зсуву завжди, незалежно від фото чи
                            // поточного зуму.
                            //
                            // Однопальцевий дотик визначає переважну вісь
                            // ОДИН РАЗ, щойно рух перевищив дрібний шум
                            // (_panAxisLockThreshold), і тримає її до
                            // відпускання пальця — без цього найменше
                            // "гуляння" по діагоналі (палець ніколи не
                            // рухається ідеально по прямій) видно як
                            // небажаний зсув по обох осях одразу. Пінч
                            // (2+ пальці) навмисно НЕ замикає вісь — це вже
                            // свідомо комбінований жест зум+пан.
                            if (details.pointerCount == 1 &&
                                _panAxisLock == null) {
                              final dx = details.focalPointDelta.dx.abs();
                              final dy = details.focalPointDelta.dy.abs();
                              if (dx > _panAxisLockThreshold ||
                                  dy > _panAxisLockThreshold) {
                                _panAxisLock = dx > dy
                                    ? Axis.horizontal
                                    : Axis.vertical;
                              }
                            }

                            final coverScale = _coverScale(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            );
                            if (coverScale != null) {
                              final verticalAllowed =
                                  details.pointerCount != 1 ||
                                  _panAxisLock != Axis.horizontal;
                              if (verticalAllowed) {
                                final vOverflow = _overflow(
                                  boxSize: constraints.maxHeight,
                                  naturalDimension: _naturalSize!.height,
                                  coverScale: coverScale,
                                );
                                if (vOverflow != null) {
                                  _alignY =
                                      (_alignY -
                                              details.focalPointDelta.dy *
                                                  2 /
                                                  vOverflow)
                                          .clamp(-1.0, 1.0);
                                }
                              }
                              final horizontalAllowed =
                                  details.pointerCount != 1 ||
                                  _panAxisLock != Axis.vertical;
                              if (horizontalAllowed) {
                                final hOverflow = _overflow(
                                  boxSize: constraints.maxWidth,
                                  naturalDimension: _naturalSize!.width,
                                  coverScale: coverScale,
                                );
                                debugPrint(
                                  'reposition dx=${details.focalPointDelta.dx} '
                                  'dy=${details.focalPointDelta.dy} '
                                  'pointers=${details.pointerCount} '
                                  'lock=$_panAxisLock scale=$_scale '
                                  'naturalW=${_naturalSize!.width} '
                                  'naturalH=${_naturalSize!.height} '
                                  'boxW=${constraints.maxWidth} '
                                  'hOverflow=$hOverflow alignX=$_alignX',
                                );
                                if (hOverflow != null) {
                                  _alignX =
                                      (_alignX -
                                              details.focalPointDelta.dx *
                                                  2 /
                                                  hOverflow)
                                          .clamp(-1.0, 1.0);
                                }
                              }
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
                                alignment: Alignment(_alignX, _alignY),
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
                  onPressed: () =>
                      Navigator.of(context).pop((_alignX, _alignY, _scale)),
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
