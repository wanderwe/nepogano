import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  if (code != null) {
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
