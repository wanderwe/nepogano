import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'l10n/app_localizations.dart';
import 'main.dart';
import 'photo_storage.dart';
import 'style.dart';

/// Скільки днів назад можна побачити й здогадати чек-іни друга.
const kGuessWindowDays = 7;

/// Унікальний ключ для (друг, день) — щоб кожен день зберігав власний
/// статус вгадування незалежно від інших днів того самого друга.
String _entryKey(String userId, DateTime date) =>
    '$userId|${date.year}-${date.month}-${date.day}';

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Один чек-ін конкретного друга за конкретний день у вікні "нещодавно" —
/// дозволяє бачити й вгадувати кожен день окремо, а не тільки останній.
class _FriendDayEntry {
  final String userId;
  final MoodLevel mood;
  final String? note;
  final String? photoPath;
  final double photoAlignY;
  final DateTime date;

  _FriendDayEntry({
    required this.userId,
    required this.mood,
    required this.note,
    required this.photoPath,
    required this.photoAlignY,
    required this.date,
  });
}

/// Один друг у списку — парний зв'язок (я додав або мене додали, обидва
/// боки бачать одне одного однаково), плюс короткий підсумок останньої
/// активності для рядка списку. Саме вгадування — на PersonDetailScreen.
class Friend {
  final String friendshipId;
  final String userId;
  final String displayEmail;
  final MoodLevel? latestMood;
  final DateTime? latestDate;
  final bool hasUnguessed;

  Friend({
    required this.friendshipId,
    required this.userId,
    required this.displayEmail,
    required this.latestMood,
    required this.latestDate,
    required this.hasUnguessed,
  });
}

class FriendFolder {
  final String id;
  final String name;

  FriendFolder({required this.id, required this.name});
}

String _relativeDay(DateTime dateTime, AppLocalizations l10n) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dateTime.year, dateTime.month, dateTime.day);
  final diff = today.difference(day).inDays;

  if (diff == 0) return l10n.today;
  if (diff == 1) return l10n.yesterday;
  return '${dateTime.day}.${dateTime.month}';
}

/// Чи є серед друзів юзера чек-ін за останні kGuessWindowDays днів, який
/// юзер ще не здогадував (для того самого дня, коли той чек-ін зроблено).
/// Використовується для тихої крапки-індикатора на іконці "Друзі".
Future<bool> hasUnseenFriendActivity(SupabaseClient supabase) async {
  final myId = supabase.auth.currentUser?.id;
  if (myId == null) return false;

  final rows = await supabase
      .from('friendships')
      .select('requester_id, addressee_id')
      .or('requester_id.eq.$myId,addressee_id.eq.$myId')
      .eq('status', 'accepted');

  final friendIds = (rows as List)
      .map(
        (r) =>
            r['requester_id'] == myId ? r['addressee_id'] : r['requester_id'],
      )
      .whereType<String>()
      .toSet()
      .toList();
  if (friendIds.isEmpty) return false;

  final since = DateTime.now().subtract(const Duration(days: kGuessWindowDays));
  final sinceUtc = DateTime(
    since.year,
    since.month,
    since.day,
  ).toUtc().toIso8601String();

  final checkinRows = await supabase
      .from('checkins')
      .select('user_id, created_at')
      .inFilter('user_id', friendIds)
      .gte('created_at', sinceUtc)
      .order('created_at', ascending: false);

  final latestByUser = <String, DateTime>{};
  for (final row in checkinRows as List) {
    final uid = row['user_id'] as String;
    if (latestByUser.containsKey(uid)) continue;
    latestByUser[uid] = DateTime.parse(row['created_at'] as String).toLocal();
  }
  if (latestByUser.isEmpty) return false;

  final sinceDate = DateTime(
    since.year,
    since.month,
    since.day,
  ).toIso8601String().split('T').first;
  final guessRows = await supabase
      .from('circle_guesses')
      .select('target_user_id, target_date')
      .eq('guesser_id', myId)
      .gte('target_date', sinceDate)
      .inFilter('target_user_id', latestByUser.keys.toList());

  for (final row in guessRows as List) {
    final uid = row['target_user_id'] as String;
    final entryDate = latestByUser[uid];
    final targetDate = DateTime.parse(row['target_date'] as String);
    if (entryDate != null &&
        targetDate.year == entryDate.year &&
        targetDate.month == entryDate.month &&
        targetDate.day == entryDate.day) {
      latestByUser.remove(uid);
    }
  }

  return latestByUser.isNotEmpty;
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.ink),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(fontSize: 16, color: AppColors.ink),
            ),
          ],
        ),
      ),
    );
  }
}

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  String? _myFriendCode;
  List<Friend> _friends = [];
  List<Map<String, dynamic>> _pendingInvites = [];
  List<FriendFolder> _folders = [];
  Map<String, Set<String>> _folderMembership = {};
  String? _selectedFolderId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final myId = _supabase.auth.currentUser!.id;
      final myEmail = _supabase.auth.currentUser?.email ?? '';

      final profileRow = await _supabase
          .from('profiles')
          .select('friend_code')
          .eq('user_id', myId)
          .maybeSingle();

      final friendshipRows = await _supabase
          .from('friendships')
          .select(
            'id, requester_id, requester_email, addressee_id, addressee_email',
          )
          .or('requester_id.eq.$myId,addressee_id.eq.$myId')
          .eq('status', 'accepted');

      final inviteRows = await _supabase
          .from('friendships')
          .select('id, requester_email')
          .eq('addressee_email', myEmail)
          .eq('status', 'pending');

      final folderRows = await _supabase
          .from('friend_folders')
          .select('id, name')
          .eq('owner_id', myId)
          .order('created_at');

      final folders = (folderRows as List)
          .map((r) => FriendFolder(id: r['id'], name: r['name']))
          .toList();

      Map<String, Set<String>> membership = {};
      if (folders.isNotEmpty) {
        final memberRows = await _supabase
            .from('friend_folder_members')
            .select('folder_id, friend_user_id')
            .inFilter('folder_id', folders.map((f) => f.id).toList());
        for (final row in memberRows as List) {
          membership
              .putIfAbsent(row['folder_id'] as String, () => {})
              .add(row['friend_user_id'] as String);
        }
      }

      final friendBasics = <String, String>{}; // userId -> email
      for (final row in friendshipRows as List) {
        final isRequester = row['requester_id'] == myId;
        final friendUserId = isRequester
            ? row['addressee_id'] as String?
            : row['requester_id'] as String;
        final friendEmail = isRequester
            ? row['addressee_email'] as String
            : row['requester_email'] as String;
        if (friendUserId != null) friendBasics[friendUserId] = friendEmail;
      }

      final friendIds = friendBasics.keys.toList();
      final latestMoodByUser = <String, MoodLevel>{};
      final latestDateByUser = <String, DateTime>{};
      final datesByUser = <String, List<DateTime>>{};

      if (friendIds.isNotEmpty) {
        final since = DateTime.now().subtract(
          const Duration(days: kGuessWindowDays),
        );
        final sinceUtc = DateTime(
          since.year,
          since.month,
          since.day,
        ).toUtc().toIso8601String();

        final checkinRows = await _supabase
            .from('checkins')
            .select('user_id, mood, created_at')
            .inFilter('user_id', friendIds)
            .gte('created_at', sinceUtc)
            .order('created_at', ascending: false);

        for (final row in checkinRows as List) {
          final uid = row['user_id'] as String;
          final createdAt = DateTime.parse(
            row['created_at'] as String,
          ).toLocal();
          final date = DateTime(createdAt.year, createdAt.month, createdAt.day);
          datesByUser.putIfAbsent(uid, () => []).add(date);
          if (!latestMoodByUser.containsKey(uid)) {
            latestMoodByUser[uid] = moodFromDbValue(row['mood'] as String);
            latestDateByUser[uid] = date;
          }
        }

        final guessedKeys = <String>{};
        if (datesByUser.isNotEmpty) {
          final sinceDate = DateTime(
            since.year,
            since.month,
            since.day,
          ).toIso8601String().split('T').first;
          final guessRows = await _supabase
              .from('circle_guesses')
              .select('target_user_id, target_date')
              .eq('guesser_id', myId)
              .gte('target_date', sinceDate)
              .inFilter('target_user_id', friendIds);

          for (final row in guessRows as List) {
            final uid = row['target_user_id'] as String;
            final targetDate = DateTime.parse(row['target_date'] as String);
            guessedKeys.add(_entryKey(uid, targetDate));
          }
        }

        final friends = <Friend>[];
        for (final row in friendshipRows) {
          final isRequester = row['requester_id'] == myId;
          final friendUserId = isRequester
              ? row['addressee_id'] as String?
              : row['requester_id'] as String;
          if (friendUserId == null) continue;
          final dates = datesByUser[friendUserId];
          final hasUnguessed =
              dates != null &&
              dates.any(
                (d) => !guessedKeys.contains(_entryKey(friendUserId, d)),
              );
          friends.add(
            Friend(
              friendshipId: row['id'],
              userId: friendUserId,
              displayEmail: friendBasics[friendUserId] ?? '',
              latestMood: latestMoodByUser[friendUserId],
              latestDate: latestDateByUser[friendUserId],
              hasUnguessed: hasUnguessed,
            ),
          );
        }
        friends.sort((a, b) {
          if (a.latestDate == null && b.latestDate == null) return 0;
          if (a.latestDate == null) return 1;
          if (b.latestDate == null) return -1;
          return b.latestDate!.compareTo(a.latestDate!);
        });

        if (!mounted) return;
        setState(() {
          _myFriendCode = profileRow?['friend_code'] as String?;
          _friends = friends;
          _pendingInvites = (inviteRows as List).cast<Map<String, dynamic>>();
          _folders = folders;
          _folderMembership = membership;
          _loading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _myFriendCode = profileRow?['friend_code'] as String?;
          _friends = [];
          _pendingInvites = (inviteRows as List).cast<Map<String, dynamic>>();
          _folders = folders;
          _folderMembership = membership;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context).couldNotLoadFriends;
          _loading = false;
        });
      }
    }
  }

  Future<void> _acceptInvite(String friendshipId) async {
    try {
      await _supabase
          .from('friendships')
          .update({
            'addressee_id': _supabase.auth.currentUser!.id,
            'status': 'accepted',
          })
          .eq('id', friendshipId);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).couldNotAcceptInvite),
          ),
        );
      }
    }
  }

  Future<void> _removeFriend(Friend friend) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text(l10n.removeFriendConfirmTitle),
        content: Text(l10n.removeFriendConfirmBody),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l10n.delete,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _supabase
          .from('friendships')
          .delete()
          .eq('id', friend.friendshipId);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).couldNotRemoveFriend),
          ),
        );
      }
    }
  }

  Future<void> _openAddFriendSheet() async {
    final l10n = AppLocalizations.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceRaised,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MenuRow(
                icon: Icons.ios_share,
                label: l10n.shareMyLink,
                onTap: () => Navigator.of(context).pop('link'),
              ),
              _MenuRow(
                icon: Icons.vpn_key_outlined,
                label: l10n.haveCode,
                onTap: () => Navigator.of(context).pop('code'),
              ),
              _MenuRow(
                icon: Icons.email_outlined,
                label: l10n.inviteFriendByEmail,
                onTap: () => Navigator.of(context).pop('email'),
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == 'link') {
      await _shareMyLink();
    } else if (choice == 'code') {
      await _enterFriendCode();
    } else if (choice == 'email') {
      await _inviteByEmail();
    }
  }

  Future<void> _shareMyLink() async {
    final l10n = AppLocalizations.of(context);
    final code = _myFriendCode;
    if (code == null) return;
    final text = l10n.friendInviteShareText(code);
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _enterFriendCode() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppColors.surfaceRaised,
          title: Text(l10n.enterFriendCode),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.none,
            decoration: InputDecoration(hintText: l10n.friendCodeHint),
            onChanged: (_) => setState(() {}),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(controller.text.trim()),
              child: Text(l10n.join),
            ),
          ],
        ),
      ),
    );

    if (code == null || code.isEmpty) return;

    try {
      await _supabase.rpc('add_friend_by_code', params: {'code': code});
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.friendAdded)));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.invalidInviteCode)));
      }
    }
  }

  Future<void> _inviteByEmail() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppColors.surfaceRaised,
          title: Text(l10n.inviteFriendByEmail),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(hintText: l10n.personEmailHint),
            onChanged: (_) => setState(() {}),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(controller.text.trim()),
              child: Text(l10n.invite),
            ),
          ],
        ),
      ),
    );

    if (email == null || email.isEmpty) return;

    try {
      final myId = _supabase.auth.currentUser!.id;
      final myEmail = _supabase.auth.currentUser?.email ?? '';
      await _supabase.from('friendships').insert({
        'requester_id': myId,
        'requester_email': myEmail,
        'addressee_email': email,
        'status': 'pending',
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.friendInviteSent)));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.couldNotInviteFriend)));
      }
    }
  }

  Future<void> _createFolder() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppColors.surfaceRaised,
          title: Text(l10n.newFolder),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: l10n.folderNameHint),
            onChanged: (_) => setState(() {}),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(controller.text.trim()),
              child: Text(l10n.create),
            ),
          ],
        ),
      ),
    );

    if (name == null || name.isEmpty) return;

    try {
      await _supabase.from('friend_folders').insert({
        'owner_id': _supabase.auth.currentUser!.id,
        'name': name,
      });
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).couldNotCreateFolder),
          ),
        );
      }
    }
  }

  Future<void> _assignToFolders(Friend friend) async {
    final l10n = AppLocalizations.of(context);
    final selected = <String>{
      for (final entry in _folderMembership.entries)
        if (entry.value.contains(friend.userId)) entry.key,
    };

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceRaised,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.addToFolder, style: appSerif(fontSize: 18)),
                const SizedBox(height: 12),
                if (_folders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      l10n.noFoldersYet,
                      style: const TextStyle(color: AppColors.inkMuted),
                    ),
                  ),
                ..._folders.map((folder) {
                  final checked = selected.contains(folder.id);
                  return CheckboxListTile(
                    value: checked,
                    onChanged: (value) async {
                      final members = _folderMembership.putIfAbsent(
                        folder.id,
                        () => {},
                      );
                      if (value == true) {
                        selected.add(folder.id);
                        members.add(friend.userId);
                        await _supabase.from('friend_folder_members').insert({
                          'folder_id': folder.id,
                          'friend_user_id': friend.userId,
                        });
                      } else {
                        selected.remove(folder.id);
                        members.remove(friend.userId);
                        await _supabase
                            .from('friend_folder_members')
                            .delete()
                            .eq('folder_id', folder.id)
                            .eq('friend_user_id', friend.userId);
                      }
                      setSheetState(() {});
                    },
                    title: Text(folder.name),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                }),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await _createFolder();
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l10n.newFolder),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visibleFriends = _selectedFolderId == null
        ? _friends
        : _friends
              .where(
                (f) => (_folderMembership[_selectedFolderId] ?? {}).contains(
                  f.userId,
                ),
              )
              .toList();

    return Scaffold(
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
                    icon: const Icon(Icons.arrow_back, size: 20),
                    tooltip: l10n.back,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(l10n.friends, style: appSerif(fontSize: 22)),
                  ),
                  IconButton(
                    onPressed: _openAddFriendSheet,
                    icon: const Icon(Icons.person_add_alt, size: 20),
                    tooltip: l10n.addFriend,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Expanded(
                  child: Center(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.inkMuted),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    children: [
                      if (_folders.isNotEmpty) ...[
                        SizedBox(
                          height: 36,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _FolderChip(
                                label: l10n.allFriends,
                                selected: _selectedFolderId == null,
                                onTap: () =>
                                    setState(() => _selectedFolderId = null),
                              ),
                              ..._folders.map(
                                (folder) => _FolderChip(
                                  label: folder.name,
                                  selected: _selectedFolderId == folder.id,
                                  onTap: () => setState(
                                    () => _selectedFolderId = folder.id,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_pendingInvites.isNotEmpty) ...[
                        Text(
                          l10n.invitations,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.inkMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._pendingInvites.map((invite) {
                          final requesterEmail =
                              invite['requester_email'] as String? ?? '';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    requesterEmail,
                                    style: const TextStyle(fontSize: 15),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      _acceptInvite(invite['id'] as String),
                                  child: Text(l10n.accept),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 20),
                      ],
                      if (visibleFriends.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            l10n.noFriendsYet,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.inkMuted),
                          ),
                        )
                      else
                        ...visibleFriends.map(_buildFriendRow),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFriendRow(Friend friend) {
    final l10n = AppLocalizations.of(context);
    final displayName = friend.displayEmail.split('@').first;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PersonDetailScreen(
            userId: friend.userId,
            displayEmail: friend.displayEmail,
          ),
        ),
      ),
      onLongPress: () => _assignToFolders(friend),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            if (friend.latestMood != null) ...[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: friend.latestMood!.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (friend.hasUnguessed) ...[
                        const SizedBox(width: 6),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.notification,
                            shape: BoxShape.circle,
                          ),
                          child: SizedBox(width: 6, height: 6),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    friend.latestDate == null
                        ? l10n.notCheckedInToday
                        : _relativeDay(friend.latestDate!, l10n),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _removeFriend(friend),
              icon: const Icon(Icons.close, size: 18),
              tooltip: l10n.removeFriend,
              color: AppColors.inkMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FolderChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.surfaceRaised,
        side: BorderSide(
          color: selected ? const Color(0xFFE0A458) : Colors.transparent,
        ),
        labelStyle: TextStyle(
          fontSize: 13,
          color: selected ? AppColors.ink : AppColors.inkMuted,
        ),
      ),
    );
  }
}

/// Екран однієї людини — до kGuessWindowDays останніх днів її чек-інів,
/// кожен окремо можна вгадати. Єдине місце в застосунку, де відбувається
/// вгадування. Видимість тепер парна (RLS на checkins), тож цей екран
/// ніколи не показує нікого, крім твого прямого друга — жодних змін не
/// потрібно було вносити в саму логіку, лише в те, звідки на нього ведуть.
class PersonDetailScreen extends StatefulWidget {
  final String userId;
  final String displayEmail;

  const PersonDetailScreen({
    super.key,
    required this.userId,
    required this.displayEmail,
  });

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  List<_FriendDayEntry> _entries = [];
  final Map<String, String?> _myGuesses = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final myId = _supabase.auth.currentUser!.id;
    final since = DateTime.now().subtract(
      const Duration(days: kGuessWindowDays),
    );
    final sinceUtc = DateTime(
      since.year,
      since.month,
      since.day,
    ).toUtc().toIso8601String();

    final checkinRows = await _supabase
        .from('checkins')
        .select('mood, note, photo_path, photo_align_y, created_at')
        .eq('user_id', widget.userId)
        .gte('created_at', sinceUtc)
        .order('created_at', ascending: false);

    final entries = <_FriendDayEntry>[];
    final seenDayKeys = <String>{};
    for (final row in checkinRows as List) {
      final createdAt = DateTime.parse(row['created_at'] as String).toLocal();
      final date = DateTime(createdAt.year, createdAt.month, createdAt.day);
      if (!seenDayKeys.add(_entryKey(widget.userId, date))) continue;
      entries.add(
        _FriendDayEntry(
          userId: widget.userId,
          mood: moodFromDbValue(row['mood'] as String),
          note: row['note'] as String?,
          photoPath: row['photo_path'] as String?,
          photoAlignY: (row['photo_align_y'] as num?)?.toDouble() ?? 0,
          date: date,
        ),
      );
    }

    final guesses = <String, String?>{};
    if (entries.isNotEmpty) {
      final sinceDate = DateTime(
        since.year,
        since.month,
        since.day,
      ).toIso8601String().split('T').first;
      final guessRows = await _supabase
          .from('circle_guesses')
          .select('guessed_mood, target_date')
          .eq('guesser_id', myId)
          .eq('target_user_id', widget.userId)
          .gte('target_date', sinceDate);

      for (final row in guessRows as List) {
        final targetDate = DateTime.parse(row['target_date'] as String);
        guesses[_entryKey(widget.userId, targetDate)] =
            row['guessed_mood'] as String;
      }
    }

    entries.sort((a, b) => b.date.compareTo(a.date));

    if (!mounted) return;
    setState(() {
      _entries = entries;
      _myGuesses
        ..clear()
        ..addAll(guesses);
      _loading = false;
    });
  }

  Future<void> _guess(_FriendDayEntry entry, MoodLevel guessedMood) async {
    final targetDate = entry.date.toIso8601String().split('T').first;
    final key = _entryKey(entry.userId, entry.date);

    try {
      await _supabase.from('circle_guesses').insert({
        'guesser_id': _supabase.auth.currentUser!.id,
        'target_user_id': entry.userId,
        'target_date': targetDate,
        'guessed_mood': guessedMood.dbValue,
        'correct': guessedMood == entry.mood,
      });
      setState(() => _myGuesses[key] = guessedMood.dbValue);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).couldNotSaveGuess),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final displayName = widget.displayEmail.split('@').first;

    return Scaffold(
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
                    icon: const Icon(Icons.arrow_back, size: 20),
                    tooltip: l10n.back,
                  ),
                  const SizedBox(width: 4),
                  Text(displayName, style: appSerif(fontSize: 22)),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_entries.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      l10n.notCheckedInToday,
                      style: const TextStyle(color: AppColors.inkMuted),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    children: _entries.map(_buildEntryCard).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntryCard(_FriendDayEntry entry) {
    final l10n = AppLocalizations.of(context);
    final key = _entryKey(entry.userId, entry.date);
    final myGuess = _myGuesses[key];
    final isToday = _isSameDay(entry.date, DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isToday ? l10n.today : _relativeDay(entry.date, l10n),
            style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 10),
          if (myGuess != null) ...[
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: entry.mood.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  entry.mood.label(context),
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 10),
                Text(
                  myGuess == entry.mood.dbValue
                      ? l10n.guessedRight
                      : l10n.guessedWrong,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: myGuess == entry.mood.dbValue
                        ? AppColors.ink
                        : AppColors.notification,
                  ),
                ),
              ],
            ),
            if ((entry.note ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                entry.note!,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.inkMuted,
                  height: 1.4,
                ),
              ),
            ],
            if (entry.photoPath != null) ...[
              const SizedBox(height: 10),
              FutureBuilder<Uint8List?>(
                future: downloadCheckinPhoto(entry.photoPath!),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox(
                      height: 140,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      snapshot.data!,
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      alignment: Alignment(0, entry.photoAlignY),
                    ),
                  );
                },
              ),
            ],
          ] else ...[
            Text(
              l10n.howAreTheyToday,
              style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
            ),
            const SizedBox(height: 10),
            Row(
              children: MoodLevel.values.map((mood) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton(
                    onPressed: () => _guess(entry, mood),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: mood.color),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    child: Text(
                      mood.label(context),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
