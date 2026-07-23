import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('nepogano/install_referrer');

/// Код запрошення в друзі з Play Install Referrer, якщо застосунок
/// встановили за посиланням nepogano.app/join/<code> без попереднього
/// встановлення (deferred deep link). Android-only — на інших платформах
/// цього каналу немає, і виклик просто повертає null.
Future<String?> fetchInstallReferrerJoinCode() async {
  if (!Platform.isAndroid) return null;
  try {
    return await _channel
        .invokeMethod<String>('getJoinCode')
        .timeout(const Duration(seconds: 5));
  } catch (e) {
    return null;
  }
}
