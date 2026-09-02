import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'avatar_storage.dart';
import 'checkin_date.dart';
import 'comments_section.dart';
import 'l10n/app_localizations.dart';
import 'main.dart';
import 'photo_storage.dart';
import 'share_utils.dart';
import 'style.dart';
import 'subject_detail_screen.dart';

/// Унікальний ключ для (друг, день) — щоб кожен день зберігав власний
/// статус вгадування незалежно від інших днів того самого друга.
String _entryKey(String userId, DateTime date) =>
    '$userId|${date.year}-${date.month}-${date.day}';

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Скорочує великі числа для статистики вгадувань (1234 -> "1.2k"), щоб
/// рядок не розтягувався разом із роками накопичених вгадувань. Ціле число
/// без десяткової частини, якщо округлення дало рівну тисячу (1000 -> "1k").
String _formatGuessCount(int n) {
  if (n < 1000) return '$n';
  final thousands = (n / 100).round() / 10;
  final isWhole = thousands == thousands.truncateToDouble();
  return '${isWhole ? thousands.toStringAsFixed(0) : thousands.toStringAsFixed(1)}k';
}

/// Назва кола — той самий ліміт, що `_displayNameMaxLength`/
/// `_subjectNameMaxLength` (`profile_screen.dart`/`main.dart`), з тієї
/// самої причини: показується в чіпах.
const _folderNameMaxLength = 30;

/// Один чек-ін конкретного друга за конкретний день у вікні "нещодавно" —
/// дозволяє бачити й вгадувати кожен день окремо, а не тільки останній.
class _FriendDayEntry {
  final String id;
  final String userId;
  final MoodLevel mood;
  final String? note;
  final String? photoPath;
  final double photoAlignX;
  final double photoAlignY;
  final double photoScale;
  final DateTime date;

  _FriendDayEntry({
    required this.id,
    required this.userId,
    required this.mood,
    required this.note,
    required this.photoPath,
    required this.photoAlignX,
    required this.photoAlignY,
    required this.photoScale,
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
  final String? displayName;
  final String? avatarPath;
  final double avatarAlignX;
  final double avatarAlignY;
  final double avatarScale;
  final MoodLevel? latestMood;
  final DateTime? latestDate;
  final bool hasUnguessed;
  // Скільки разів саме цей друг намагався вгадати мій настрій і скільки з
  // цих спроб — вірно (на відміну від _guessesTotal/_guessesCorrect на рівні
  // екрану, які сумують усіх друзів разом). null, якщо ще жодної спроби.
  final int? guessesTotal;
  final int? guessesCorrect;

  Friend({
    required this.friendshipId,
    required this.userId,
    required this.displayEmail,
    required this.displayName,
    required this.avatarPath,
    this.avatarAlignX = 0,
    this.avatarAlignY = 0,
    this.avatarScale = 1,
    required this.latestMood,
    required this.latestDate,
    required this.hasUnguessed,
    this.guessesTotal,
    this.guessesCorrect,
  });

  String get name => displayName ?? displayEmail.split('@').first;
}

class FriendFolder {
  final String id;
  final String name;

  FriendFolder({required this.id, required this.name});
}

/// Щоденник сутності (дитина/улюбленець) чужого власника, відкритий на
/// перегляд колу, в якому я є учасником — веде на SubjectDetailScreen, той
/// самий ритуал вгадування, що з друзями.
class SharedSubject {
  final String subjectId;
  final String subjectName;
  final String? ownerName;
  final String ownerId;

  SharedSubject({
    required this.subjectId,
    required this.subjectName,
    required this.ownerName,
    required this.ownerId,
  });
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
      .select('user_id, created_at, local_date')
      .inFilter('user_id', friendIds)
      .gte('created_at', sinceUtc)
      .order('created_at', ascending: false);

  final latestByUser = <String, DateTime>{};
  for (final row in checkinRows as List) {
    final uid = row['user_id'] as String;
    if (latestByUser.containsKey(uid)) continue;
    latestByUser[uid] = effectiveCheckinDate(row);
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

const _nudgesLastSeenKey = 'nudges_last_seen';
// Скільки днів між поштовхами одному й тому самому другу — м'яке обмеження
// на клієнті (той самий підхід, що й до інших не-критичних лімітів у
// застосунку), щоб один настирливий друг не міг закидати поштовхами щодня.
const kNudgeCooldownDays = 7;

/// Один рядок у списку "хто цікавиться" — id потрібен, щоб тап по імені міг
/// вести на профіль цього друга, не лише показувати текст.
class NudgeFrom {
  final String userId;
  final String name;

  NudgeFrom({required this.userId, required this.name});
}

/// Хто й скільки людей "поштовхнули" мене з часу останнього перегляду —
/// null, якщо нікого. Показується пасивно на головному екрані при
/// наступному відкритті застосунку (немає push-інфраструктури, свідомо).
class PendingNudges {
  // Усі, хто поштовхнув, найновіші перші — щоб можна було показати повний
  // список за тапом, а не лише "перший + N інших", де ці N лишались
  // невідомими.
  final List<NudgeFrom> from;

  PendingNudges({required this.from});
}

Future<PendingNudges?> loadPendingNudges(SupabaseClient supabase) async {
  final myId = supabase.auth.currentUser?.id;
  if (myId == null) return null;

  final prefs = await SharedPreferences.getInstance();
  final lastSeenIso = prefs.getString(_nudgesLastSeenKey);
  final since = lastSeenIso != null
      ? DateTime.parse(lastSeenIso)
      : DateTime.fromMillisecondsSinceEpoch(0);

  final rows = await supabase
      .from('friend_nudges')
      .select('from_user_id, created_at')
      .eq('to_user_id', myId)
      .gt('created_at', since.toUtc().toIso8601String())
      .order('created_at', ascending: false);

  final fromIds = (rows as List)
      .map((r) => r['from_user_id'] as String)
      .toSet()
      .toList();
  if (fromIds.isEmpty) return null;

  final nameRows = await supabase
      .from('profiles')
      .select('user_id, display_name')
      .inFilter('user_id', fromIds);
  final nameById = <String, String?>{
    for (final row in nameRows as List)
      row['user_id'] as String: row['display_name'] as String?,
  };

  return PendingNudges(
    from: fromIds
        .map((id) => NudgeFrom(userId: id, name: nameById[id] ?? ''))
        .toList(),
  );
}

Future<void> markNudgesSeen() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _nudgesLastSeenKey,
    DateTime.now().toUtc().toIso8601String(),
  );
}

class NudgeStatus {
  final bool canSend;
  final DateTime? lastSentAt;
  final DateTime? availableAgainAt;

  NudgeStatus({
    required this.canSend,
    required this.lastSentAt,
    required this.availableAgainAt,
  });
}

/// Чи можна зараз поштовхнути саме цього друга (false — вже робив це
/// протягом [kNudgeCooldownDays] днів) і коли востаннє, якщо взагалі колись —
/// іконка тепер завжди на екрані, і без цього тапнути на неї під час
/// кулдауну не було б чим пояснити ("чому нічого не відбувається").
Future<NudgeStatus> nudgeStatus(
  SupabaseClient supabase,
  String friendUserId,
) async {
  final myId = supabase.auth.currentUser?.id;
  if (myId == null) {
    return NudgeStatus(
      canSend: false,
      lastSentAt: null,
      availableAgainAt: null,
    );
  }

  final rows = await supabase
      .from('friend_nudges')
      .select('created_at')
      .eq('from_user_id', myId)
      .eq('to_user_id', friendUserId)
      .order('created_at', ascending: false)
      .limit(1);

  final list = rows as List;
  if (list.isEmpty) {
    return NudgeStatus(canSend: true, lastSentAt: null, availableAgainAt: null);
  }

  final lastSentAt = DateTime.parse(
    list.first['created_at'] as String,
  ).toLocal();
  final cooldownEnds = lastSentAt.add(const Duration(days: kNudgeCooldownDays));
  return NudgeStatus(
    canSend: DateTime.now().isAfter(cooldownEnds),
    lastSentAt: lastSentAt,
    availableAgainAt: cooldownEnds,
  );
}

Future<void> sendNudge(SupabaseClient supabase, String friendUserId) async {
  await supabase.from('friend_nudges').insert({
    'from_user_id': supabase.auth.currentUser!.id,
    'to_user_id': friendUserId,
  });
}

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
    final rowColor = color ?? AppColors.ink;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: rowColor),
            const SizedBox(width: 16),
            Text(label, style: TextStyle(fontSize: 16, color: rowColor)),
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
  String? _myDisplayName;
  List<Friend> _friends = [];
  Map<String, Uint8List> _friendAvatars = {};
  List<Map<String, dynamic>> _pendingInvites = [];
  List<FriendFolder> _folders = [];
  Map<String, Set<String>> _folderMembership = {};
  String? _selectedFolderId;

  List<SharedSubject> _sharedSubjects = [];

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  bool _searchOpen = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    if (_searchOpen) {
      setState(() {
        _searchOpen = false;
        _searchQuery = '';
        _searchController.clear();
      });
      return;
    }
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
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
          .select('friend_code, display_name')
          .eq('user_id', myId)
          .maybeSingle();

      // Скільки разів друзі намагались вгадати мій настрій і скільки з цих
      // спроб — вірно. Потребує окремої RLS-політики на select (нижче) —
      // стара дозволяла бачити тільки власні здогадки (guesser_id = я),
      // не ті, що про мене (guess-stats-migration.sql).
      // Підрахунок окремо на кожного друга — щоб порівняти, хто вгадує
      // краще (замість однієї сумарної цифри по всіх друзях одразу).
      final myGuessRows =
          await _supabase
                  .from('circle_guesses')
                  .select('correct, guesser_id')
                  .eq('target_user_id', myId)
              as List;
      final guessesTotalByFriend = <String, int>{};
      final guessesCorrectByFriend = <String, int>{};
      for (final row in myGuessRows) {
        final guesserId = row['guesser_id'] as String;
        guessesTotalByFriend[guesserId] =
            (guessesTotalByFriend[guesserId] ?? 0) + 1;
        if (row['correct'] == true) {
          guessesCorrectByFriend[guesserId] =
              (guessesCorrectByFriend[guesserId] ?? 0) + 1;
        }
      }

      // Щоденники сутностей, які чиїсь власники відкрили колам, де я є
      // учасником — суто перегляд із вгадуванням (SubjectDetailScreen).
      // Виключаємо ті, де я вже власник або співавтор: до них і так є повний
      // прямий доступ через мій перемикач на головному екрані, а вгадувати
      // настрій щоденника, який я сам можу редагувати, безглуздо — саме цей
      // збіг (власника поділився з колом, де є і мій співавтор) і призводив
      // до "навіщо мені вгадувати, я ж сам це записував".
      final myMembershipRows = await _supabase
          .from('friend_folder_members')
          .select('folder_id')
          .eq('friend_user_id', myId);
      final myFolderIds = (myMembershipRows as List)
          .map((r) => r['folder_id'] as String)
          .toList();

      final myOwnedSubjectRows = await _supabase
          .from('subjects')
          .select('id')
          .eq('owner_id', myId);
      final myCoauthoredSubjectRows = await _supabase
          .from('subject_coauthors')
          .select('subject_id')
          .eq('coauthor_user_id', myId);
      final myOwnSubjectIds = <String>{
        ...(myOwnedSubjectRows as List).map((r) => r['id'] as String),
        ...(myCoauthoredSubjectRows as List).map(
          (r) => r['subject_id'] as String,
        ),
      };

      final sharedSubjects = <SharedSubject>[];
      if (myFolderIds.isNotEmpty) {
        final shareRows = await _supabase
            .from('subject_folder_shares')
            .select('subject_id, subjects(id, name, owner_id)')
            .inFilter('folder_id', myFolderIds);

        final byId = <String, Map<String, dynamic>>{};
        for (final row in shareRows as List) {
          final subjectRow = row['subjects'] as Map<String, dynamic>?;
          if (subjectRow == null) continue;
          if (myOwnSubjectIds.contains(subjectRow['id'] as String)) continue;
          byId[subjectRow['id'] as String] = subjectRow;
        }

        if (byId.isNotEmpty) {
          final ownerIds = byId.values
              .map((s) => s['owner_id'] as String)
              .toSet()
              .toList();
          final ownerRows = await _supabase
              .from('profiles')
              .select('user_id, display_name')
              .inFilter('user_id', ownerIds);
          final ownerNameById = <String, String?>{
            for (final row in ownerRows as List)
              row['user_id'] as String: row['display_name'] as String?,
          };

          for (final subjectRow in byId.values) {
            final ownerId = subjectRow['owner_id'] as String;
            sharedSubjects.add(
              SharedSubject(
                subjectId: subjectRow['id'] as String,
                subjectName: subjectRow['name'] as String,
                ownerName: ownerNameById[ownerId],
                ownerId: ownerId,
              ),
            );
          }
        }
      }

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
            .select('user_id, mood, created_at, local_date')
            .inFilter('user_id', friendIds)
            .gte('created_at', sinceUtc)
            .order('created_at', ascending: false);

        for (final row in checkinRows as List) {
          final uid = row['user_id'] as String;
          final date = effectiveCheckinDate(row);
          datesByUser.putIfAbsent(uid, () => []).add(date);
          if (!latestMoodByUser.containsKey(uid)) {
            latestMoodByUser[uid] = moodFromDbValue(row['mood'] as String);
            latestDateByUser[uid] = date;
          }
        }

        final nameRows = await _supabase
            .from('profiles')
            .select(
              'user_id, display_name, avatar_path, avatar_align_x, avatar_align_y, avatar_scale',
            )
            .inFilter('user_id', friendIds);
        final displayNameByUser = <String, String?>{
          for (final row in nameRows as List)
            row['user_id'] as String: row['display_name'] as String?,
        };
        final avatarPathByUser = <String, String?>{
          for (final row in nameRows)
            row['user_id'] as String: row['avatar_path'] as String?,
        };
        final avatarAlignXByUser = <String, double>{
          for (final row in nameRows)
            row['user_id'] as String:
                (row['avatar_align_x'] as num?)?.toDouble() ?? 0,
        };
        final avatarAlignYByUser = <String, double>{
          for (final row in nameRows)
            row['user_id'] as String:
                (row['avatar_align_y'] as num?)?.toDouble() ?? 0,
        };
        final avatarScaleByUser = <String, double>{
          for (final row in nameRows)
            row['user_id'] as String:
                (row['avatar_scale'] as num?)?.toDouble() ?? 1,
        };

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
              displayName: displayNameByUser[friendUserId],
              avatarPath: avatarPathByUser[friendUserId],
              avatarAlignX: avatarAlignXByUser[friendUserId] ?? 0,
              avatarAlignY: avatarAlignYByUser[friendUserId] ?? 0,
              avatarScale: avatarScaleByUser[friendUserId] ?? 1,
              latestMood: latestMoodByUser[friendUserId],
              latestDate: latestDateByUser[friendUserId],
              hasUnguessed: hasUnguessed,
              guessesTotal: guessesTotalByFriend[friendUserId],
              guessesCorrect: guessesCorrectByFriend[friendUserId],
            ),
          );
        }
        friends.sort((a, b) {
          if (a.latestDate == null && b.latestDate == null) return 0;
          if (a.latestDate == null) return 1;
          if (b.latestDate == null) return -1;
          return b.latestDate!.compareTo(a.latestDate!);
        });

        final avatars = await downloadAvatars(
          friends.map((f) => f.avatarPath).whereType<String>(),
        );

        if (!mounted) return;
        setState(() {
          _myFriendCode = profileRow?['friend_code'] as String?;
          _myDisplayName = profileRow?['display_name'] as String?;
          _friends = friends;
          _friendAvatars = avatars;
          _pendingInvites = (inviteRows as List).cast<Map<String, dynamic>>();
          _folders = folders;
          _folderMembership = membership;
          _sharedSubjects = sharedSubjects;
          _loading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _myFriendCode = profileRow?['friend_code'] as String?;
          _myDisplayName = profileRow?['display_name'] as String?;
          _friends = [];
          _pendingInvites = (inviteRows as List).cast<Map<String, dynamic>>();
          _folders = folders;
          _folderMembership = membership;
          _sharedSubjects = sharedSubjects;
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
      builder: (context) => AppDialog(
        title: l10n.removeFriendConfirmTitle,
        content: Text(
          l10n.removeFriendConfirmBody,
          style: const TextStyle(color: AppColors.inkMuted),
        ),
        primaryLabel: l10n.cancel,
        onPrimary: () => Navigator.of(context).pop(false),
        secondaryLabel: l10n.delete,
        secondaryColor: Colors.redAccent,
        onSecondary: () => Navigator.of(context).pop(true),
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
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MenuRow(
                icon: PhosphorIconsLight.export,
                label: l10n.shareMyLink,
                onTap: () => Navigator.of(context).pop('link'),
              ),
              _MenuRow(
                icon: PhosphorIconsLight.envelopeSimple,
                label: l10n.inviteFriendByEmail,
                onTap: () => Navigator.of(context).pop('email'),
              ),
              _MenuRow(
                icon: PhosphorIconsLight.key,
                label: l10n.haveCode,
                onTap: () => Navigator.of(context).pop('code'),
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
    final myName =
        _myDisplayName ??
        (_supabase.auth.currentUser?.email ?? '').split('@').first;
    final text = l10n.friendInviteShareText(
      myName,
      code,
      Uri.encodeComponent(myName),
    );
    try {
      await SharePlus.instance.share(
        ShareParams(text: text, sharePositionOrigin: shareOriginFrom(context)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.somethingWentWrong)));
      }
    }
  }

  Future<void> _enterFriendCode() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AppDialog(
          title: l10n.enterFriendCode,
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.none,
            decoration: appFieldDecoration(l10n.friendCodeHint),
            onChanged: (_) => setState(() {}),
          ),
          primaryLabel: l10n.join,
          onPrimary: controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(controller.text.trim()),
          secondaryLabel: l10n.cancel,
          onSecondary: () => Navigator.of(context).pop(),
        ),
      ),
    );

    if (code == null || code.isEmpty) return;

    try {
      await _supabase.rpc('add_friend_by_code', params: {'code': code});
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(l10n.friendAdded),
            duration: const Duration(seconds: 2),
          ),
        );
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
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AppDialog(
          title: l10n.inviteFriendByEmail,
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: appFieldDecoration(l10n.personEmailHint),
            onChanged: (_) => setState(() {}),
          ),
          primaryLabel: l10n.invite,
          onPrimary: controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(controller.text.trim()),
          secondaryLabel: l10n.cancel,
          onSecondary: () => Navigator.of(context).pop(),
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
        ).showSnackBar(
          SnackBar(
            content: Text(l10n.friendInviteSent),
            duration: const Duration(seconds: 2),
          ),
        );
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
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AppDialog(
          title: l10n.newFolder,
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: _folderNameMaxLength,
            buildCounter:
                (
                  context, {
                  required currentLength,
                  required isFocused,
                  maxLength,
                }) => null,
            decoration: appFieldDecoration(l10n.folderNameHint),
            onChanged: (_) => setState(() {}),
          ),
          primaryLabel: l10n.create,
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

  Future<void> _openFolderMenu(FriendFolder folder) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MenuRow(
                icon: PhosphorIconsLight.pencilSimple,
                label: l10n.renameFolder,
                onTap: () => Navigator.of(context).pop('rename'),
              ),
              _MenuRow(
                icon: PhosphorIconsLight.trash,
                label: l10n.delete,
                color: Colors.redAccent,
                onTap: () => Navigator.of(context).pop('delete'),
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == 'rename') {
      await _renameFolder(folder);
    } else if (choice == 'delete') {
      await _removeFolder(folder);
    }
  }

  Future<void> _renameFolder(FriendFolder folder) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: folder.name);
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AppDialog(
          title: l10n.renameFolder,
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: _folderNameMaxLength,
            buildCounter:
                (
                  context, {
                  required currentLength,
                  required isFocused,
                  maxLength,
                }) => null,
            decoration: appFieldDecoration(l10n.folderNameHint),
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

    if (name == null || name.isEmpty || name == folder.name) return;

    try {
      await _supabase
          .from('friend_folders')
          .update({'name': name})
          .eq('id', folder.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).couldNotRenameFolder),
          ),
        );
      }
    }
  }

  Future<void> _removeFolder(FriendFolder folder) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: l10n.removeFolderConfirmTitle(folder.name),
        primaryLabel: l10n.cancel,
        onPrimary: () => Navigator.of(context).pop(false),
        secondaryLabel: l10n.delete,
        secondaryColor: Colors.redAccent,
        onSecondary: () => Navigator.of(context).pop(true),
      ),
    );
    if (confirmed != true) return;

    try {
      await _supabase.from('friend_folders').delete().eq('id', folder.id);
      if (_selectedFolderId == folder.id) {
        setState(() => _selectedFolderId = null);
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).couldNotRemoveFolder),
          ),
        );
      }
    }
  }

  Future<void> _openFriendMenu(Friend friend) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MenuRow(
                icon: PhosphorIconsLight.circlesThreePlus,
                label: l10n.addToFolder,
                onTap: () => Navigator.of(context).pop('folder'),
              ),
              _MenuRow(
                icon: PhosphorIconsLight.userMinus,
                label: l10n.removeFriend,
                color: Colors.redAccent,
                onTap: () => Navigator.of(context).pop('remove'),
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == 'folder') {
      await _assignToFolders(friend);
    } else if (choice == 'remove') {
      await _removeFriend(friend);
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
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.addToFolder, style: appScreenTitle(fontSize: 18)),
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
                  icon: const Icon(PhosphorIconsLight.plus, size: 18),
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
    final byFolder = _selectedFolderId == null
        ? _friends
        : _friends
              .where(
                (f) => (_folderMembership[_selectedFolderId] ?? {}).contains(
                  f.userId,
                ),
              )
              .toList();
    // Пошук працює ПОВЕРХ вибраного кола, а не замість нього — фільтрує
    // список, що вже звужений колом, а не весь список друзів одразу.
    final query = _searchQuery.trim().toLowerCase();
    final visibleFriends = query.isEmpty
        ? byFolder
        : byFolder
              .where(
                (f) =>
                    f.name.toLowerCase().contains(query) ||
                    f.displayEmail.toLowerCase().contains(query),
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
                    icon: const Icon(PhosphorIconsLight.arrowLeft, size: 20),
                    tooltip: l10n.back,
                  ),
                  const SizedBox(width: 4),
                  Expanded(child: Text(l10n.friends, style: appScreenTitle())),
                  IconButton(
                    onPressed: _toggleSearch,
                    icon: Icon(
                      _searchOpen
                          ? PhosphorIconsLight.x
                          : PhosphorIconsLight.magnifyingGlass,
                      size: 20,
                    ),
                    tooltip: l10n.search,
                  ),
                  IconButton(
                    onPressed: _openAddFriendSheet,
                    icon: const Icon(PhosphorIconsLight.userPlus, size: 20),
                    tooltip: l10n.addFriend,
                  ),
                ],
              ),
              if (_searchOpen) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: appFieldDecoration(l10n.searchFriendHint)
                      .copyWith(
                        prefixIcon: const Icon(
                          PhosphorIconsLight.magnifyingGlass,
                          size: 18,
                        ),
                      ),
                ),
              ],
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
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 36,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  // Завжди видима, навіть без жодного кола —
                                  // інакше цей рядок порожній, і лишається
                                  // самотня іконка "додати коло" незрозумілого
                                  // призначення (як щойно показав скріншот).
                                  _FolderChip(
                                    label: l10n.allFriends,
                                    selected: _selectedFolderId == null,
                                    onTap: () => setState(
                                      () => _selectedFolderId = null,
                                    ),
                                  ),
                                  ..._folders.map(
                                    (folder) => _FolderChip(
                                      label: folder.name,
                                      selected: _selectedFolderId == folder.id,
                                      onTap: () => setState(
                                        () => _selectedFolderId = folder.id,
                                      ),
                                      onLongPress: () =>
                                          _openFolderMenu(folder),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _createFolder,
                            icon: const Icon(
                              PhosphorIconsLight.circlesThreePlus,
                              size: 22,
                            ),
                            tooltip: l10n.newFolder,
                            color: AppColors.inkMuted,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
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

  Widget _buildFriendAvatar(Friend friend, String displayName) {
    final bytes = friend.avatarPath == null
        ? null
        : _friendAvatars[friend.avatarPath];
    return ClipOval(
      child: Container(
        width: 36,
        height: 36,
        color: AppColors.surfaceRaised,
        child: bytes != null
            ? ScaledPhoto(
                scale: friend.avatarScale,
                alignX: friend.avatarAlignX,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  alignment: Alignment(
                    friend.avatarAlignX,
                    friend.avatarAlignY,
                  ),
                ),
              )
            : Center(
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                  style: appSerif(fontSize: 14),
                ),
              ),
      ),
    );
  }

  Widget _buildFriendRow(Friend friend) {
    final l10n = AppLocalizations.of(context);
    final displayName = friend.name;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PersonDetailScreen(
              userId: friend.userId,
              displayEmail: friend.displayEmail,
              displayName: friend.displayName,
              sharedSubjects: _sharedSubjects
                  .where((s) => s.ownerId == friend.userId)
                  .toList(),
            ),
          ),
        );
        if (mounted) _load();
      },
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
            _buildFriendAvatar(friend, displayName),
            const SizedBox(width: 12),
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
                  const SizedBox(height: 2),
                  Text(
                    (friend.guessesTotal ?? 0) > 0
                        ? l10n.friendGuessStats(
                            _formatGuessCount(friend.guessesCorrect ?? 0),
                            _formatGuessCount(friend.guessesTotal!),
                            (((friend.guessesCorrect ?? 0) /
                                        friend.guessesTotal!) *
                                    100)
                                .round(),
                          )
                        : l10n.friendNeverGuessed,
                    // Скорочення чисел (_formatGuessCount) покриває звичний
                    // випадок, це — чиста страховка на екстремальний
                    // edge-case (дуже вузький екран/великий шрифт
                    // доступності): рядок фізично не може зламати висоту
                    // картки друга, хай там що станеться з довжиною тексту.
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _openFriendMenu(friend),
              icon: const Icon(PhosphorIconsLight.dotsThreeVertical, size: 18),
              tooltip: l10n.moreTooltip,
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
  final VoidCallback? onLongPress;

  const _FolderChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: AppChip(
        label: label,
        selected: selected,
        onTap: onTap,
        onLongPress: onLongPress,
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
  final String? displayName;
  final List<SharedSubject> sharedSubjects;

  const PersonDetailScreen({
    super.key,
    required this.userId,
    required this.displayEmail,
    this.displayName,
    this.sharedSubjects = const [],
  });

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  List<_FriendDayEntry> _entries = [];
  final Map<String, String?> _myGuesses = {};
  NudgeStatus? _nudgeStatus;

  // RLS уже й так дає друзям повний доступ до всієї історії одне одного,
  // незалежно від дати — kGuessWindowDays лише клієнтське вікно першого
  // завантаження. "Показати ще" розширює його на стільки ж днів назад, той
  // самий запит, просто ширше вікно — без окремої пагінації/курсора.
  int _windowDays = kGuessWindowDays;
  bool _loadingMore = false;
  bool _hasMore = true;

  /// Той самий фікс, що в Історії й на головному екрані — довга нотатка
  /// друга без обрізання змушувала нескінченно свайпати повз неї.
  final Set<String> _expandedNoteIds = {};

  @override
  void initState() {
    super.initState();
    _load();
    _refreshNudgeStatus();
  }

  Future<void> _refreshNudgeStatus() async {
    final status = await nudgeStatus(_supabase, widget.userId);
    if (mounted) setState(() => _nudgeStatus = status);
  }

  // Іконка тепер завжди на екрані (раніше зникала одразу після відправки —
  // якщо тапнути її під час кулдауну, не було чим пояснити, чому нічого не
  // відбувається). Тап відкриває діалог замість миттєвої відправки: коли
  // можна — просить підтвердити, коли не можна — показує, коли востаннє
  // штовхав і що спробувати можна за тиждень. Той самий діалог для обох
  // станів, просто основна кнопка вимкнена під час кулдауну.
  Future<void> _openNudgeDialog() async {
    final l10n = AppLocalizations.of(context);
    final status = _nudgeStatus;
    if (status == null) return;

    final bodyText = status.canSend
        ? l10n.nudgeDialogBody
        : l10n.nudgeAlreadySent(_relativeDay(status.availableAgainAt!, l10n));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: l10n.nudgeDialogTitle,
        content: Text(
          bodyText,
          style: const TextStyle(color: AppColors.inkMuted),
        ),
        primaryLabel: l10n.nudgeDialogSend,
        onPrimary: status.canSend
            ? () => Navigator.of(context).pop(true)
            : null,
        secondaryLabel: status.canSend ? l10n.cancel : l10n.done,
        onSecondary: () => Navigator.of(context).pop(false),
      ),
    );

    if (confirmed == true) await _sendNudgeToFriend();
  }

  Future<void> _sendNudgeToFriend() async {
    final l10n = AppLocalizations.of(context);
    try {
      await sendNudge(_supabase, widget.userId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(l10n.nudgeSent),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      await _refreshNudgeStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.couldNotSendNudge)));
      }
    }
  }

  /// Розширює вікно кроками по [kGuessWindowDays], поки не з'явиться хоч
  /// один новий запис (або поки старших записів не лишиться взагалі) —
  /// без цього кожен клік розширював вікно рівно на тиждень, і якщо
  /// конкретний тиждень виявлявся порожнім, список виглядав так, ніби
  /// "Показати ще" нічого не робить, і доводилось тицяти кілька разів
  /// підряд, щоб дістатись тижня з реальними записами.
  Future<void> _loadMoreEntries() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final previousCount = _entries.length;
    do {
      _windowDays += kGuessWindowDays;
      await _load(isLoadMore: true);
    } while (_hasMore && _entries.length == previousCount);
    if (mounted) setState(() => _loadingMore = false);
  }

  Future<void> _load({bool isLoadMore = false}) async {
    if (!isLoadMore) setState(() => _loading = true);

    final myId = _supabase.auth.currentUser!.id;
    final since = DateTime.now().subtract(Duration(days: _windowDays));
    final sinceUtc = DateTime(
      since.year,
      since.month,
      since.day,
    ).toUtc().toIso8601String();

    // Чи є хоч один чек-ін СТАРШИЙ за поточне вікно — пряма перевірка,
    // а не порівняння кількості записів між викликами (те раніше
    // рахувалось лише при "Показати ще", тож кнопка завжди висіла після
    // першого відкриття екрана, навіть коли підвантажувати вже нічого).
    final olderRows = await _supabase
        .from('checkins')
        .select('id')
        .eq('user_id', widget.userId)
        .lt('created_at', sinceUtc)
        .limit(1);
    final hasMore = (olderRows as List).isNotEmpty;

    final checkinRows = await _supabase
        .from('checkins')
        .select(
          'id, mood, note, photo_path, photo_align_x, photo_align_y, photo_scale, created_at, local_date',
        )
        .eq('user_id', widget.userId)
        .gte('created_at', sinceUtc)
        .order('created_at', ascending: false);

    final entries = <_FriendDayEntry>[];
    final seenDayKeys = <String>{};
    for (final row in checkinRows as List) {
      final date = effectiveCheckinDate(row);
      if (!seenDayKeys.add(_entryKey(widget.userId, date))) continue;
      entries.add(
        _FriendDayEntry(
          id: row['id'] as String,
          userId: widget.userId,
          mood: moodFromDbValue(row['mood'] as String),
          note: row['note'] as String?,
          photoPath: row['photo_path'] as String?,
          photoAlignX: (row['photo_align_x'] as num?)?.toDouble() ?? 0,
          photoAlignY: (row['photo_align_y'] as num?)?.toDouble() ?? 0,
          photoScale: (row['photo_scale'] as num?)?.toDouble() ?? 1,
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
      _hasMore = hasMore;
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
    final displayName =
        widget.displayName ?? widget.displayEmail.split('@').first;

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
                    icon: const Icon(PhosphorIconsLight.arrowLeft, size: 20),
                    tooltip: l10n.back,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      displayName,
                      overflow: TextOverflow.ellipsis,
                      style: appScreenTitle(),
                    ),
                  ),
                  // Компактна іконка замість окремої кнопки на весь рядок —
                  // та раніше виглядала зайвим, відірваним блоком над усім
                  // іншим. Завжди на екрані (навіть під час кулдауну) —
                  // раніше зникала одразу після відправки, і тап під час
                  // кулдауну не мав чим пояснити тишу. Тап відкриває діалог
                  // із поясненням і, якщо кулдаун ще не минув, датою
                  // останнього поштовху — не миттєва відправка одним тапом.
                  if (_nudgeStatus != null)
                    IconButton(
                      onPressed: _openNudgeDialog,
                      icon: Icon(
                        PhosphorIconsLight.handWaving,
                        size: 20,
                        color: _nudgeStatus!.canSend
                            ? AppColors.ink
                            : AppColors.inkMuted,
                      ),
                      tooltip: l10n.nudgeButtonTooltip,
                    ),
                ],
              ),
              if (widget.sharedSubjects.isNotEmpty) ...[
                const SizedBox(height: 12),
                // Підпис "Відкрито для перегляду" тут прибрали — самі чіпи
                // з назвами щоденників і так зрозумілі в контексті сторінки
                // друга, підпис лише займав рядок без реальної користі.
                // Ці щоденники завжди прив'язані до ОДНІЄЇ людини (цього
                // екрана) — на відміну від кіл, тут реалістично не буде
                // десятка позицій, тож горизонтальний свайп (той самий
                // патерн, що й перемикач сутностей/кіл деінде в застосунку)
                // зручніший за шторку з окремим тапом для відкриття.
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.sharedSubjects.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final shared = widget.sharedSubjects[index];
                      return AppChip(
                        label: shared.subjectName,
                        selected: false,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SubjectDetailScreen(
                              subjectId: shared.subjectId,
                              subjectName: shared.subjectName,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_entries.isEmpty)
                // Порожньо в поточному вікні — сам напис і так інформативний
                // (є/нема свіжих новин), центрований, як завжди. Якщо
                // старіші записи все ж є (_hasMore), під написом додається
                // кнопка з окремим формулюванням "Показати старіші" —
                // "Показати ще" тут звучало б дивно, бо показувати після
                // порожнього списку нічого "ще", лише щось старе.
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.notCheckedInToday,
                          style: const TextStyle(color: AppColors.inkMuted),
                        ),
                        if (_hasMore) ...[
                          const SizedBox(height: 12),
                          _loadingMore
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : TextButton(
                                  onPressed: _loadMoreEntries,
                                  // Точково акцентний колір замість
                                  // приглушеного дефолту теми — інакше
                                  // кнопка зливається з написом над нею й не
                                  // виглядає як щось клікабельне.
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.accent,
                                  ),
                                  child: Text(l10n.showOlder),
                                ),
                        ],
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    children: [
                      ..._entries.map(_buildEntryCard),
                      if (_hasMore)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: _loadingMore
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : TextButton(
                                    onPressed: _loadMoreEntries,
                                    child: Text(l10n.showMore),
                                  ),
                          ),
                        ),
                    ],
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
              ExpandableNote(
                text: entry.note!,
                expanded: _expandedNoteIds.contains(entry.id),
                onToggle: () => setState(() {
                  if (!_expandedNoteIds.add(entry.id)) {
                    _expandedNoteIds.remove(entry.id);
                  }
                }),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.ink,
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
                    return const AspectRatio(
                      aspectRatio: kCompactPhotoAspectRatio,
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
                    child: AspectRatio(
                      aspectRatio: kCompactPhotoAspectRatio,
                      child: ScaledPhoto(
                        scale: entry.photoScale,
                        alignX: entry.photoAlignX,
                        child: Image.memory(
                          snapshot.data!,
                          fit: BoxFit.cover,
                          alignment: Alignment(
                            entry.photoAlignX,
                            entry.photoAlignY,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
            CommentsSection(
              key: ValueKey('comments-${entry.id}'),
              checkinId: entry.id,
              canComment: true,
              isOwner: false,
            ),
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
                  child: GuessMoodButton(
                    mood: mood,
                    onTap: () => _guess(entry, mood),
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
