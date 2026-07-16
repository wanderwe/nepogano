import 'package:flutter/material.dart';

const _monthNamesUk = [
  'Січень', 'Лютий', 'Березень', 'Квітень', 'Травень', 'Червень',
  'Липень', 'Серпень', 'Вересень', 'Жовтень', 'Листопад', 'Грудень',
];
const _monthNamesEn = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const _monthNamesGenitiveUk = [
  'січня', 'лютого', 'березня', 'квітня', 'травня', 'червня',
  'липня', 'серпня', 'вересня', 'жовтня', 'листопада', 'грудня',
];
// В англійській немає родового відмінка — той самий список, що й називний.
const _monthNamesGenitiveEn = _monthNamesEn;

const _weekdayLabelsUk = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Нд'];
const _weekdayLabelsEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

const _weekdayNamesFullUk = [
  'понеділок', 'вівторок', 'середа', 'четвер', "п'ятниця", 'субота', 'неділя',
];
const _weekdayNamesFullEn = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

bool _isEn(Locale locale) => locale.languageCode == 'en';

/// Назва місяця, називний відмінок ("Липень"). [month] 1-12.
String monthName(int month, Locale locale) =>
    (_isEn(locale) ? _monthNamesEn : _monthNamesUk)[month - 1];

/// Назва місяця, родовий відмінок для дат ("13 липня"). [month] 1-12.
String monthNameGenitive(int month, Locale locale) =>
    (_isEn(locale) ? _monthNamesGenitiveEn : _monthNamesGenitiveUk)[month - 1];

/// Скорочена назва дня тижня ("Пн"). [weekday] 1(Пн)-7(Нд), як DateTime.weekday.
String weekdayLabel(int weekday, Locale locale) =>
    (_isEn(locale) ? _weekdayLabelsEn : _weekdayLabelsUk)[weekday - 1];

/// Повна назва дня тижня ("понеділок"). [weekday] 1(Пн)-7(Нд), як DateTime.weekday.
String weekdayNameFull(int weekday, Locale locale) =>
    (_isEn(locale) ? _weekdayNamesFullEn : _weekdayNamesFullUk)[weekday - 1];
