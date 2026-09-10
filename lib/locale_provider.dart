import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'style.dart';

/// Поточна мова застосунку. Слухай через ValueListenableBuilder,
/// міняй через setAppLocale (зберігає вибір на диск).
final ValueNotifier<Locale> appLocale = ValueNotifier<Locale>(const Locale('uk'));

const _localePrefKey = 'app_locale';

/// Мови, які реально має застосунок (тримати в парі з
/// AppLocalizations.supportedLocales) — потрібно окремо від нього, бо
/// system locale може прийти з кодом, якого ми взагалі не перекладали.
const _supportedLanguageCodes = ['en', 'uk'];

Future<void> loadSavedLocale() async {
  final prefs = await SharedPreferences.getInstance();
  final code = prefs.getString(_localePrefKey);
  // Той самий фільтр _supportedLanguageCodes, що й для системної мови
  // нижче — раніше збережений код довірявся без перевірки: якщо колись
  // прибрати підтримувану мову чи значення пошкодиться, appLocale.value
  // містив би непідтримуваний код, а перемикач (лише 'en'/'uk') не міг
  // би це виправити тапом.
  if (code != null && _supportedLanguageCodes.contains(code)) {
    appLocale.value = Locale(code);
    return;
  }

  // Юзер ще жодного разу не обирав мову вручну — перший запуск. Підбираємо
  // з мови системи (як робить більшість застосунків), а не завжди
  // показуємо українську: якщо систему поставили не в Україні, юзер має
  // побачити англійську, а не незрозумілий йому текст. Виняток — російська
  // системна мова: замість неї теж українська, а не англійська.
  final systemCode = PlatformDispatcher.instance.locale.languageCode;
  final resolvedCode = switch (systemCode) {
    'ru' => 'uk',
    _ when _supportedLanguageCodes.contains(systemCode) => systemCode,
    _ => 'en',
  };
  appLocale.value = Locale(resolvedCode);
}

Future<void> setAppLocale(Locale locale) async {
  appLocale.value = locale;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_localePrefKey, locale.languageCode);
}

/// Перемикач мови EN/UK — той самий вигляд на онбордингу, логіні й екрані
/// примусового оновлення, раніше скопійований у кожному з трьох місць
/// окремо.
///
/// ValueListenableBuilder тут ОБОВ'ЯЗКОВИЙ, не просто підстраховка —
/// реальний баг, знайдений повторним аудитом: усі три виклики створюють
/// цей віджет як `const LanguageTogglePill()`. Const-віджети з однаковими
/// аргументами — той САМИЙ канонічний instance, і Flutter's reconciliation
/// (`identical(oldWidget, newWidget)`) пропускає повторний build() для
/// незмінного const-піддерева, НАВІТЬ якщо предок (тут — кореневий
/// MaterialApp через `ValueListenableBuilder&lt;Locale&gt;` у main.dart)
/// перебудовується цілком. Без власного прямого підписки на [appLocale]
/// напис EN/UA застрягав на значенні з першого рендеру — усі інші
/// локалізовані тексти на екрані міняли мову коректно (вони не const),
/// а сам перемикач — ні, аж доки екран не перемонтується заново.
class LanguageTogglePill extends StatelessWidget {
  const LanguageTogglePill({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: appLocale,
      builder: (context, locale, _) {
        return GestureDetector(
          onTap: () {
            final next = locale.languageCode == 'uk' ? 'en' : 'uk';
            setAppLocale(Locale(next));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              // Мітка — не сам ISO-код мови (той лишається 'uk', це
              // окреме, коректне значення для Locale). "UK" тут читалось
              // би як Велика Британія, а не як скорочення "українська" —
              // "UA" однозначне.
              locale.languageCode == 'uk' ? 'EN' : 'UA',
              style: const TextStyle(
                color: AppColors.inkMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      },
    );
  }
}
