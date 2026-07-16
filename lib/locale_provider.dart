import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Поточна мова застосунку. Слухай через ValueListenableBuilder,
/// міняй через setAppLocale (зберігає вибір на диск).
final ValueNotifier<Locale> appLocale = ValueNotifier<Locale>(const Locale('uk'));

const _localePrefKey = 'app_locale';

Future<void> loadSavedLocale() async {
  final prefs = await SharedPreferences.getInstance();
  final code = prefs.getString(_localePrefKey);
  if (code != null) {
    appLocale.value = Locale(code);
  }
}

Future<void> setAppLocale(Locale locale) async {
  appLocale.value = locale;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_localePrefKey, locale.languageCode);
}
