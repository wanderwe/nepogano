import 'package:flutter/services.dart';

/// Тонка обгортка над нативним Android-каналом для прямого шеру
/// в конкретні соцмережі, без екрана вибору застосунку.
class SocialShare {
  static const _channel = MethodChannel('nepogano/social_share');

  static Future<bool> instagramStory(String filePath) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        'shareInstagramStory',
        {'filePath': filePath},
      );
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> toPackage(String filePath, String packageName) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        'shareToPackage',
        {'filePath': filePath, 'packageName': packageName},
      );
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
