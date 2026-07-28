import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'l10n/app_localizations.dart';
import 'style.dart';

/// Особистий профіль — ім'я, яке бачать друзі, і код для додавання в друзі.
/// Живе в головному меню (не на екрані Друзі) — це налаштування себе, не
/// частина списку інших людей. Сам завантажує свої дані, не залежить від
/// того, звідки на нього перейшли.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  String? _displayName;
  String? _friendCode;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final row = await _supabase
        .from('profiles')
        .select('display_name, friend_code')
        .eq('user_id', _supabase.auth.currentUser!.id)
        .maybeSingle();
    if (!mounted) return;
    setState(() {
      _displayName = row?['display_name'] as String?;
      _friendCode = row?['friend_code'] as String?;
      _loading = false;
    });
  }

  Future<void> _editDisplayName() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: _displayName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AppDialog(
          title: l10n.editDisplayName,
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: appFieldDecoration(l10n.displayNameHint),
            onChanged: (_) => setState(() {}),
          ),
          primaryLabel: l10n.save,
          onPrimary: controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(controller.text.trim()),
          secondaryLabel: l10n.cancel,
          onSecondary: () => Navigator.of(context).pop(),
        ),
      ),
    );

    if (name == null || name.isEmpty) return;

    try {
      await _supabase
          .from('profiles')
          .update({'display_name': name})
          .eq('user_id', _supabase.auth.currentUser!.id);
      if (mounted) setState(() => _displayName = name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).couldNotSaveDisplayName),
          ),
        );
      }
    }
  }

  Future<void> _copyFriendCode() async {
    final code = _friendCode;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    // Android сам показує системне повідомлення про копіювання з 13 версії —
    // власне поверх нього було б дублюванням. На інших платформах такого
    // системного фідбеку нема, тож лишаємо свій.
    if (mounted && !Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).codeCopied)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(PhosphorIconsLight.arrowLeft, size: 20),
                    tooltip: l10n.back,
                  ),
                  const SizedBox(width: 4),
                  Expanded(child: Text(l10n.profile, style: appScreenTitle())),
                ],
              ),
              const SizedBox(height: 24),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _editDisplayName,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          PhosphorIconsLight.identificationBadge,
                          size: 18,
                          color: AppColors.inkMuted,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.editDisplayName,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.inkMuted,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _displayName ?? l10n.setDisplayName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: AppColors.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          PhosphorIconsLight.caretRight,
                          size: 18,
                          color: AppColors.inkMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_friendCode != null) ...[
                  const SizedBox(height: 12),
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _copyFriendCode,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            PhosphorIconsLight.key,
                            size: 18,
                            color: AppColors.inkMuted,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.myFriendCode,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.inkMuted,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _friendCode!,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            PhosphorIconsLight.copy,
                            size: 18,
                            color: AppColors.inkMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
