import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Спільна дизайн-система застосунку: темна тема (у стилі картки дня),
/// два шрифти (serif для "голосу" бренду, sans для функціонального UI).
/// Глибина на темному тлі передається тоном поверхні, а не тінями.
class AppColors {
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF1E1E1E);
  static const surfaceRaised = Color(0xFF272727);
  static const ink = Colors.white;
  static const inkMuted = Color(0xFF9B9B9B);
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

/// Serif — для моментів "голосу" бренду: заголовки, назва оцінки, назва застосунку.
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

  const AppChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
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
              const Icon(Icons.check, size: 14, color: AppColors.accent),
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
/// стандартний Material AlertDialog, serif-заголовок (той самий "голос
/// бренду", що й деінде), одна виразна повношира кнопка основної дії замість
/// двох дрібних TextButton поруч — так з першого погляду видно, яка дія
/// очікувана, а яка другорядна.
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: appSerif(fontSize: 20, height: 1.25)),
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
    );
  }
}
