import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'l10n/app_localizations.dart';
import 'style.dart';

/// Особистий профіль — ім'я, яке бачать друзі, і код для додавання в друзі.
/// Винесено з екрану Друзі, щоб не змішувати "налаштування себе" зі списком
/// інших людей.
class ProfileScreen extends StatefulWidget {
  final String? displayName;
  final String? friendCode;

  const ProfileScreen({super.key, this.displayName, this.friendCode});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _supabase = Supabase.instance.client;
  late String? _displayName = widget.displayName;

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
                    onPressed: () => Navigator.of(context).pop(_displayName),
                    icon: const Icon(Icons.arrow_back, size: 20),
                    tooltip: l10n.back,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(l10n.profile, style: appSerif(fontSize: 22)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
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
                        Icons.badge_outlined,
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
                        Icons.chevron_right,
                        size: 18,
                        color: AppColors.inkMuted,
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.friendCode != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.vpn_key_outlined,
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
                              widget.friendCode!,
                              style: const TextStyle(
                                fontSize: 16,
                                color: AppColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
