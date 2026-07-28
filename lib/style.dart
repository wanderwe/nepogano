import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Пропорція фото і в рамці позиціювання (`PhotoRepositionScreen`), і в
/// картці дня (`day_card_screen.dart`) — має лишатись однією константою:
/// якщо вони розійдуться, юзер побачить у шері не те, що обрізав рамкою.
/// Квадрат — свідомий компроміс між старою пласкою смужкою (16:10, замале
/// фото) і попередньою спробою 4:5 (заскладно витягувало картку в
/// месенджері й Instagram Stories).
const kPhotoAspectRatio = 1.0;

/// Пропорція для компактних прев'ю фото (запис в Історії, у друга, підсумок
/// на головному екрані) — свідомо НЕ [kPhotoAspectRatio]: там економимо
/// вертикальний простір списку/кнопок, тож ширша за квадрат. Але й не така
/// пласка, як стара смужка (~2:1–3.8:1 залежно від ширини екрана) — це
/// зрізало значно більше кадру, ніж юзер бачив при кадруванні в
/// [kPhotoAspectRatio]-рамці, і виглядало неочікувано порівняно з карткою дня.
const kCompactPhotoAspectRatio = 4 / 3;

/// Скільки днів назад можна побачити й здогадати чек-іни друга чи (за тим
/// самим ритуалом) відкритого щоденника сутності — спільне для
/// `PersonDetailScreen` і `SubjectDetailScreen`, тому тут, а не в одному з
/// цих двох файлів (інакше довелось би імпортувати один з одного).
const kGuessWindowDays = 7;

/// Обгортка для фото з урахуванням zoom (`photo_scale` у БД) — єдина
/// точка, де застосовується масштаб, щоб він не розійшовся між формою
/// вводу, підсумком дня, історією, друзями й карткою дня так само, як
/// щойно розійшлась пропорція рамки. `scale <= 1` — no-op (найчастіший
/// випадок, без зайвого ClipRect у дереві).
class ScaledPhoto extends StatelessWidget {
  final double scale;
  final Widget child;

  const ScaledPhoto({super.key, required this.scale, required this.child});

  @override
  Widget build(BuildContext context) {
    if (scale <= 1.0) return child;
    return ClipRect(
      child: Transform.scale(scale: scale, child: child),
    );
  }
}

/// Спільна дизайн-система застосунку: темна тема (у стилі картки дня),
/// два шрифти (serif для "голосу" бренду, sans для функціонального UI).
/// Глибина на темному тлі передається тоном поверхні, а не тінями.
class AppColors {
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF1E1E1E);
  static const surfaceRaised = Color(0xFF272727);
  static const ink = Colors.white;
  // Теплий сірий (легкий домішок бурштинового accent), а не чисто нейтральний —
  // щоб іконки й приглушений текст (дата, підписи) читались як один тон,
  // а не як дві різні палітри поруч.
  static const inkMuted = Color(0xFFAC9D8A);
  static const divider = Color(0x1FFFFFFF);

  /// Позначка "є щось нове" (непрочитана активність у колі) — навмисно
  /// не збігається з жодним кольором шкали настрою (сірий/бурштиновий/бірюзовий).
  static const notification = Color(0xFFFF6B8A);

  /// Бренд-акцент (той самий відтінок, що colorSchemeSeed) — для виділених
  /// чіпів, кнопок і рамок, де потрібен точний контроль кольору поза
  /// згенерованою Material-палітрою.
  static const accent = Color(0xFFE0A458);
  static const accentInk = Color(0xFF2B1D0E);
}

class AppShadows {
  static List<BoxShadow> soft = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.35),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];

  static List<BoxShadow> subtle = [];
}

/// Serif — для моментів "голосу" бренду: питання настрою, онбординг, назва
/// застосунку на вході. НЕ для щоденних заголовків екранів (Друзі/Історія/
/// Профіль тощо) — там serif лише виглядає чужорідним елементом поруч із
/// рештою уніфікованого UI, для цього — [appScreenTitle] нижче.
TextStyle appSerif({
  required double fontSize,
  FontWeight fontWeight = FontWeight.w600,
  Color color = AppColors.ink,
  double? height,
}) {
  return GoogleFonts.lora(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
  );
}

/// Заголовок екрана (шапка "← Назва") — свідомо sans (Inter, той самий
/// шрифт, що й решта UI), не serif. Один хелпер замість повторення того
/// самого TextStyle на кожному екрані.
TextStyle appScreenTitle({double fontSize = 22}) {
  return TextStyle(
    fontSize: fontSize,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
  );
}

/// Однаковий стиль текстових полів у діалогах по всьому застосунку: заповнене
/// тло замість системного підкресленого поля (те, що виглядало "застарілим"
/// у формах створення друга/кола/щоденника), заокруглені кути, акцентна рамка
/// у фокусі.
InputDecoration appFieldDecoration(String hint) {
  final radius = BorderRadius.circular(14);
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.inkMuted),
    filled: true,
    fillColor: AppColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
    ),
  );
}

/// Спільний чіп-вибір (сутність, коло, тип сутності тощо) — навмисно НЕ
/// Material ChoiceChip: той резервує змінну ширину під галочку вибору, через
/// що ряд чіпів "стрибає" між рядками залежно від того, який саме вибраний.
/// Тут ширина залежить лише від тексту мітки, і вона стабільна завжди.
class AppChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  // Тільки коли НЕ selected — напр. позначає "це не твій щоденник, а
  // спільний з кимось" на чіпі перемикача сутностей, ще до того, як юзер
  // тапне й побачить деталі. Коли чіп вибраний, галочка важливіша.
  final IconData? leadingIcon;

  const AppChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.leadingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceRaised : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
          ),
        ),
        // Контейнер сам визначає свою ширину за вмістом (Row всередині
        // Container, без фіксованого розміру) — на відміну від Material
        // ChoiceChip, галочка тут просто додає трохи ширини, а не стискає
        // текст мітки в уже зарезервованому просторі.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(
                PhosphorIconsLight.check,
                size: 14,
                color: AppColors.accent,
              ),
              const SizedBox(width: 6),
            ] else if (leadingIcon != null) ...[
              Icon(leadingIcon, size: 14, color: AppColors.inkMuted),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected ? AppColors.ink : AppColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Спільна картка-діалог для всього застосунку: заокруглена сильніше за
/// стандартний Material AlertDialog, sans-заголовок (функціональний UI, не
/// "голос бренду" — serif лишається лише для ритуалу настрою), одна виразна
/// повношира кнопка основної дії замість двох дрібних TextButton поруч —
/// так з першого погляду видно, яка дія очікувана, а яка другорядна.
/// Контент прокручується (SingleChildScrollView) — без цього клавіатура під
/// текстовим полем легко зіштовхує діалог в overflow знизу.
class AppDialog extends StatelessWidget {
  final String title;
  final Widget? content;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final Color primaryColor;
  final Color primaryForeground;
  final String secondaryLabel;
  final VoidCallback onSecondary;
  final Color secondaryColor;

  const AppDialog({
    super.key,
    required this.title,
    this.content,
    required this.primaryLabel,
    required this.onPrimary,
    this.primaryColor = AppColors.accent,
    this.primaryForeground = AppColors.accentInk,
    required this.secondaryLabel,
    required this.onSecondary,
    this.secondaryColor = AppColors.inkMuted,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceRaised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        // Клавіатура з'їдає частину висоти екрана — фіксований Column без
        // скролу тоді просто overflow'ить знизу (як щойно показав скріншот:
        // "BOTTOM OVERFLOWED BY 4.0 PIXELS" у діалозі з текстовим полем).
        // Спільний компонент для всіх діалогів застосунку — фікс тут
        // покриває їх усі одразу, не тільки цей конкретний випадок.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: appScreenTitle(fontSize: 20)),
              if (content != null) ...[const SizedBox(height: 18), content!],
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: primaryForeground,
                    disabledBackgroundColor: AppColors.surface,
                    disabledForegroundColor: AppColors.inkMuted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: onPrimary,
                  child: Text(
                    primaryLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: TextButton(
                  onPressed: onSecondary,
                  child: Text(
                    secondaryLabel,
                    style: TextStyle(color: secondaryColor),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
