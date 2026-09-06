import 'package:flutter/material.dart';

import 'style.dart';

/// Малює офіційний логотип Google ("G") — у пакеті `google_sign_in` немає
/// готового вектора, на відміну від `AppleLogoPainter` з `sign_in_with_apple`.
/// Координати — це офіційний path Google (viewBox 0..48), перенесений як
/// Canvas-команди й проскейлений під розмір `size`.
class GoogleLogoPainter extends CustomPainter {
  const GoogleLogoPainter();

  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 48;
    final sy = size.height / 48;
    canvas.save();
    canvas.scale(sx, sy);

    final blue = Path()
      ..moveTo(45.12, 24.5)
      ..cubicTo(45.12, 22.94, 44.98, 21.44, 44.72, 20.0)
      ..lineTo(24, 20.0)
      ..lineTo(24, 28.51)
      ..lineTo(35.84, 28.51)
      ..cubicTo(35.33, 31.26, 33.78, 33.59, 31.45, 35.15)
      ..lineTo(31.45, 40.67)
      ..lineTo(38.56, 40.67)
      ..cubicTo(42.72, 36.84, 45.12, 31.2, 45.12, 24.5)
      ..close();
    canvas.drawPath(blue, Paint()..color = _blue);

    final green = Path()
      ..moveTo(24, 46)
      ..cubicTo(29.94, 46, 34.92, 44.03, 38.56, 40.67)
      ..lineTo(31.45, 35.15)
      ..cubicTo(29.48, 36.47, 26.96, 37.25, 24.0, 37.25)
      ..cubicTo(18.27, 37.25, 13.42, 33.38, 11.69, 28.18)
      ..lineTo(4.34, 28.18)
      ..lineTo(4.34, 33.88)
      ..cubicTo(7.96, 41.07, 15.4, 46, 24, 46)
      ..close();
    canvas.drawPath(green, Paint()..color = _green);

    final yellow = Path()
      ..moveTo(11.69, 28.18)
      ..cubicTo(11.25, 26.86, 11, 25.45, 11, 24)
      ..cubicTo(11, 22.55, 11.25, 21.14, 11.69, 19.82)
      ..lineTo(11.69, 14.12)
      ..lineTo(4.34, 14.12)
      ..cubicTo(2.85, 17.09, 2, 20.45, 2, 24)
      ..cubicTo(2, 27.55, 2.85, 30.91, 4.34, 33.88)
      ..lineTo(11.69, 28.18)
      ..close();
    canvas.drawPath(yellow, Paint()..color = _yellow);

    final red = Path()
      ..moveTo(24, 10.75)
      ..cubicTo(27.23, 10.75, 30.13, 11.86, 32.41, 14.04)
      ..lineTo(38.72, 7.73)
      ..cubicTo(34.91, 4.18, 29.93, 2, 24, 2)
      ..cubicTo(15.4, 2, 7.96, 6.93, 4.34, 14.12)
      ..lineTo(11.69, 19.82)
      ..cubicTo(13.42, 14.62, 18.27, 10.75, 24.0, 10.75)
      ..close();
    canvas.drawPath(red, Paint()..color = _red);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Компактна кругла кнопка соцлогіну — лише іконка, без тексту. Apple
/// вимагає рівноцінного вигляду для всіх провайдерів, показаних поряд
/// (Guideline 4.8/HIG), тож коли Apple-кнопка на iOS переходить у цей
/// компактний стиль, Google-кнопка поруч має отримати той самий розмір і
/// трактування — звідси єдиний спільний віджет для обох.
class CompactSocialButton extends StatelessWidget {
  const CompactSocialButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.semanticLabel,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  static const _diameter = 52.0;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: _diameter,
            height: _diameter,
            child: Center(
              // Звичайний OutlinedButton, який ця кнопка замінила,
              // автоматично притлумлював себе через ButtonStyle, коли
              // onPressed == null — тут своєї теми нема, тож без цього
              // юзер не бачив би жодної різниці між "триває вхід" і
              // "можна тиснути ще раз".
              child: Opacity(
                opacity: enabled ? 1 : 0.4,
                child: SizedBox(width: 22, height: 22, child: icon),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
