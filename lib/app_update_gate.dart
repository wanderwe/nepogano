import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'l10n/app_localizations.dart';
import 'style.dart';

/// App Store: https://apps.apple.com/app/id6796667458 (той самий ID, що на
/// index.html лендінгу). Play Store: офіційний пакет com.nepogano.app.
const _appStoreUrl = 'https://apps.apple.com/app/id6796667458';
const _playStoreUrl =
    'https://play.google.com/store/apps/details?id=com.nepogano.app';

/// Перевіряє, чи поточний білд застосунку нижчий за мінімальний
/// підтримуваний для цієї платформи (`app_config`, Supabase). `null`, якщо
/// перевірку неможливо виконати (мережа, таблиці ще нема тощо) — свідомо
/// "fail open": тимчасова мережева проблема не має блокувати весь
/// застосунок, це лише додатковий шар, не заміна звичайного
/// bootstrap-коннекшн-чеку вище.
Future<bool> isUpdateRequired() async {
  try {
    final platform = Platform.isIOS ? 'ios' : 'android';
    final row = await Supabase.instance.client
        .from('app_config')
        .select('min_build_number')
        .eq('platform', platform)
        .maybeSingle();
    final minBuild = row?['min_build_number'] as int?;
    if (minBuild == null) return false;

    final info = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(info.buildNumber);
    if (currentBuild == null) return false;

    return currentBuild < minBuild;
  } catch (_) {
    return false;
  }
}

/// Блокуючий екран — жодної кнопки "Закрити"/"Пропустити", системний
/// back теж не випускає (`PopScope(canPop: false)`) — на відміну від УСІХ
/// інших екранів застосунку, тут навмисно нема шляху обійти, це весь сенс
/// force-update.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  Future<void> _openStore() async {
    final url = Platform.isIOS ? _appStoreUrl : _playStoreUrl;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.updateRequiredTitle,
                    textAlign: TextAlign.center,
                    style: appScreenTitle(fontSize: 22),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.updateRequiredBody,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.inkMuted),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _openStore,
                      child: Text(l10n.updateRequiredButton),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
