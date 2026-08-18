import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'avatar_storage.dart';
import 'l10n/app_localizations.dart';
import 'photo_reposition_screen.dart';
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
  String? _avatarPath;
  Uint8List? _avatarBytes;
  double _avatarAlignY = 0;
  double _avatarScale = 1;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final row = await _supabase
        .from('profiles')
        .select(
          'display_name, friend_code, avatar_path, avatar_align_y, avatar_scale',
        )
        .eq('user_id', _supabase.auth.currentUser!.id)
        .maybeSingle();
    if (!mounted) return;
    setState(() {
      _displayName = row?['display_name'] as String?;
      _friendCode = row?['friend_code'] as String?;
      _avatarPath = row?['avatar_path'] as String?;
      _avatarAlignY = (row?['avatar_align_y'] as num?)?.toDouble() ?? 0;
      _avatarScale = (row?['avatar_scale'] as num?)?.toDouble() ?? 1;
      _loading = false;
    });
    final path = _avatarPath;
    if (path != null) {
      final bytes = await downloadAvatar(path);
      if (mounted) setState(() => _avatarBytes = bytes);
    }
  }

  Future<void> _changeAvatar() async {
    final l10n = AppLocalizations.of(context);
    final action = await showModalBottomSheet<_AvatarAction>(
      context: context,
      backgroundColor: AppColors.surfaceRaised,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MenuRow(
                icon: PhosphorIconsLight.camera,
                label: l10n.takePhoto,
                onTap: () => Navigator.of(context).pop(_AvatarAction.camera),
              ),
              _MenuRow(
                icon: PhosphorIconsLight.images,
                label: l10n.chooseFromGallery,
                onTap: () => Navigator.of(context).pop(_AvatarAction.gallery),
              ),
              if (_avatarBytes != null) ...[
                _MenuRow(
                  icon: PhosphorIconsLight.arrowsOutCardinal,
                  label: l10n.repositionPhoto,
                  onTap: () =>
                      Navigator.of(context).pop(_AvatarAction.reposition),
                ),
                _MenuRow(
                  icon: PhosphorIconsLight.trash,
                  label: l10n.removeAvatar,
                  color: Colors.redAccent,
                  onTap: () => Navigator.of(context).pop(_AvatarAction.remove),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;

    if (action == _AvatarAction.reposition) {
      await _repositionExistingAvatar();
      return;
    }
    if (action == _AvatarAction.remove) {
      await _removeAvatar();
      return;
    }

    final picked = await ImagePicker().pickImage(
      source: action == _AvatarAction.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    final file = File(picked.path);
    final result = await Navigator.of(context).push<(double, double)>(
      MaterialPageRoute(
        builder: (_) => PhotoRepositionScreen(image: FileImage(file)),
      ),
    );
    if (result == null || !mounted) return;
    final alignY = result.$1;
    final scale = result.$2;

    setState(() => _uploadingAvatar = true);
    try {
      final path = await uploadAvatar(file);
      await _supabase
          .from('profiles')
          .update({
            'avatar_path': path,
            'avatar_align_y': alignY,
            'avatar_scale': scale,
          })
          .eq('user_id', _supabase.auth.currentUser!.id);
      final bytes = await file.readAsBytes();
      if (mounted) {
        setState(() {
          _avatarPath = path;
          _avatarBytes = bytes;
          _avatarAlignY = alignY;
          _avatarScale = scale;
          _uploadingAvatar = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.couldNotSaveAvatar)));
      }
    }
  }

  /// Той самий файл, лише нове кадрування — на відміну від вибору нового
  /// фото, тут не треба нічого перезавантажувати в Storage.
  Future<void> _repositionExistingAvatar() async {
    final bytes = _avatarBytes;
    if (bytes == null) return;
    final result = await Navigator.of(context).push<(double, double)>(
      MaterialPageRoute(
        builder: (_) => PhotoRepositionScreen(
          image: MemoryImage(bytes),
          initialAlignY: _avatarAlignY,
          initialScale: _avatarScale,
        ),
      ),
    );
    if (result == null || !mounted) return;

    final alignY = result.$1;
    final scale = result.$2;
    try {
      await _supabase
          .from('profiles')
          .update({'avatar_align_y': alignY, 'avatar_scale': scale})
          .eq('user_id', _supabase.auth.currentUser!.id);
      if (mounted) {
        setState(() {
          _avatarAlignY = alignY;
          _avatarScale = scale;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).couldNotSaveAvatar),
          ),
        );
      }
    }
  }

  Future<void> _removeAvatar() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: l10n.removeAvatarConfirmTitle,
        content: Text(
          l10n.removeAvatarConfirmBody,
          style: const TextStyle(color: AppColors.inkMuted),
        ),
        primaryLabel: l10n.cancel,
        onPrimary: () => Navigator.of(context).pop(false),
        secondaryLabel: l10n.delete,
        secondaryColor: Colors.redAccent,
        onSecondary: () => Navigator.of(context).pop(true),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _uploadingAvatar = true);
    try {
      await deleteAvatar();
      await _supabase
          .from('profiles')
          .update({'avatar_path': null, 'avatar_align_y': 0, 'avatar_scale': 1})
          .eq('user_id', _supabase.auth.currentUser!.id);
      if (mounted) {
        setState(() {
          _avatarPath = null;
          _avatarBytes = null;
          _avatarAlignY = 0;
          _avatarScale = 1;
          _uploadingAvatar = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.couldNotRemoveAvatar)));
      }
    }
  }

  Future<void> _editDisplayName() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: _displayName ?? '');
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
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
                Center(child: _buildAvatarPicker()),
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

  Widget _buildAvatarPicker() {
    final initial =
        (_displayName?.trim().isNotEmpty == true
                ? _displayName!.trim()
                : (_supabase.auth.currentUser?.email ?? '?'))[0]
            .toUpperCase();

    return GestureDetector(
      onTap: _uploadingAvatar ? null : _changeAvatar,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipOval(
            child: Container(
              width: 88,
              height: 88,
              color: AppColors.surface,
              child: _avatarBytes != null
                  ? ScaledPhoto(
                      scale: _avatarScale,
                      child: Image.memory(
                        _avatarBytes!,
                        fit: BoxFit.cover,
                        alignment: Alignment(0, _avatarAlignY),
                      ),
                    )
                  : Center(child: Text(initial, style: appSerif(fontSize: 32))),
            ),
          ),
          if (_uploadingAvatar)
            const SizedBox(
              width: 88,
              height: 88,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                PhosphorIconsLight.camera,
                size: 14,
                color: AppColors.accentInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _AvatarAction { camera, gallery, reposition, remove }

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? AppColors.ink;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: textColor),
            const SizedBox(width: 16),
            Text(label, style: TextStyle(fontSize: 16, color: textColor)),
          ],
        ),
      ),
    );
  }
}
