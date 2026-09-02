import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'l10n/app_localizations.dart';
import 'style.dart';

/// Дає перетягнути фото вертикально Й ГОРИЗОНТАЛЬНО та наблизити пінчем у
/// рамці тієї ж пропорції (`kCompactPhotoAspectRatio`, 4:3), що й компактні
/// прев'ю фото скрізь у застосунку (запис в Історії, у друга, підсумок на
/// головному екрані) — саме там юзер і бачить фото після публікації.
/// Раніше рамка була квадратною (`kPhotoAspectRatio`, тепер прибрано),
/// не тією самою пропорцією, що фактичний перегляд: `BoxFit.cover`
/// обрізає по-різному залежно від пропорції рамки (для фото, чия
/// натуральна пропорція лежить МІЖ 1:1 і 4:3, "покривний" вимір взагалі
/// перемикається між шириною й висотою), тож те, що юзер бачив і
/// кадрував у квадраті, після публікації показувалось інакше — реальний
/// фідбек ("бачу 1/3 фото в редакторі, після публікації бачу 2/3").
/// Тепер редактор і кінцевий перегляд — той самий кадр, підписаний як
/// такий. Картка дня (`day_card_screen.dart`) — окрема історія, 9:16,
/// свідомо інша пропорція, не канонічна тут — для неї поруч є власне
/// маленьке живе прев'ю (той самий `ScaledPhoto`, лише 9:16), а не
/// порахована підказка: та сама пастка з "перемиканням покривного
/// виміру" так само реальна для пари 4:3↔9:16, тож замість повторно
/// ризикувати неточною формулою — просто інший розмір того самого
/// реального рендеру.
///
/// Повертає `(alignX, alignY, scale)` через Navigator.pop, або null якщо
/// закрито без змін.
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
                aspectRatio: kCompactPhotoAspectRatio,
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
                            // Вертикаль (нижче) ділить на РЕАЛЬНИЙ overflow
                            // конкретного фото (не на розмір рамки) —
                            // інакше швидкість перетягування "стрибала" б
                            // між фото різних пропорцій (майже квадратне
                            // фото мало куди панорамувати — те саме
                            // перетягування пальцем відчувалось би як
                            // "повільно" проти витягнутого портрета).
                            // `_overflow` вже сам враховує поточний
                            // `_scale` всередині формули, тож тут його
                            // вдруге множити НЕ треба — формула тримає 1px
                            // пальця ≈ 1px видимого зсуву завжди, незалежно
                            // від фото чи поточного зуму. Горизонталь має
                            // ІНШУ формулу — див. коментар нижче біля
                            // `hOverflow`.
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
                                // На відміну від вертикалі, тут НЕ рахуємо
                                // запас від натуральних пікселів фото —
                                // `ScaledPhoto` (яка й реально показує
                                // фото скрізь у застосунку) реалізує
                                // горизонтальний пан не через
                                // BoxFit.cover-кадрування, а окремим
                                // `Transform.translate` поверх
                                // center-anchored зуму, і рахує доступний
                                // запас так само суто від розміру РАМКИ
                                // (`boxWidth * (scale - 1)`). Якщо тут
                                // порахувати інакше — прев'ю в редакторі
                                // й реальний рендер розійдуться.
                                final hOverflow =
                                    constraints.maxWidth * (_scale - 1);
                                if (hOverflow > 0) {
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
                        child: ScaledPhoto(
                          scale: _scale,
                          alignX: _alignX,
                          child: Image(
                            image: widget.image,
                            fit: BoxFit.cover,
                            alignment: Alignment(_alignX, _alignY),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.repositionPhotoPostPreviewLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
              ),
              const SizedBox(height: 20),
              // Живий прев'ю Картки дня (9:16) — той самий ScaledPhoto+Image
              // з поточними alignX/alignY/scale, лише маленький, не
              // порахована окремо геометрія. Що бачить юзер тут, те й буде
              // в Картці дня, без ризику розійтись формулою.
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 64,
                    child: AspectRatio(
                      aspectRatio: 9 / 16,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: ScaledPhoto(
                          scale: _scale,
                          alignX: _alignX,
                          child: Image(
                            image: widget.image,
                            fit: BoxFit.cover,
                            alignment: Alignment(_alignX, _alignY),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.repositionPhotoDayCardPreview,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
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
