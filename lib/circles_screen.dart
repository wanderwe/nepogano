import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'l10n/app_localizations.dart';
import 'main.dart';
import 'style.dart';

/// Скільки днів назад можна побачити й здогадати чек-іни людини з кола.
const kGuessWindowDays = 7;

/// Унікальний ключ для (учасник, день) — щоб кожен день зберігав власний
/// статус вгадування незалежно від інших днів того самого учасника.
String _entryKey(String userId, DateTime date) =>
    '$userId|${date.year}-${date.month}-${date.day}';

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Один чек-ін конкретного учасника за конкретний день у вікні "нещодавно" —
/// дозволяє бачити й вгадувати кожен день окремо, а не тільки останній.
class _MemberDayEntry {
  final String userId;
  final MoodLevel mood;
  final String? note;
  final DateTime date;

  _MemberDayEntry({
    required this.userId,
    required this.mood,
    required this.note,
    required this.date,
  });
}

/// Короткий підсумок по учаснику кола для списку членів — останній настрій
/// (якщо є) і чи лишився серед його останніх днів хоч один невгаданий.
/// Саме вгадування відбувається на окремому екрані людини (PersonDetailScreen).
class _MemberSummary {
  final String userId;
  final String displayEmail;
  final MoodLevel? latestMood;
  final DateTime? latestDate;
  final bool hasUnguessed;

  _MemberSummary({
    required this.userId,
    required this.displayEmail,
    required this.latestMood,
    required this.latestDate,
    required this.hasUnguessed,
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

class Circle {
  final String id;
  final String name;
  final String ownerId;
  final String inviteCode;

  Circle({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.inviteCode,
  });
}

class CircleMember {
  final String id;
  final String circleId;
  final String? userId;
  final String invitedEmail;
  final String status;

  CircleMember({
    required this.id,
    required this.circleId,
    required this.userId,
    required this.invitedEmail,
    required this.status,
  });
}

/// Одна людина в стрічці "Нещодавно" — один запис на людину (дедубльовано,
/// навіть якщо вона в кількох спільних колах), з датою найновішого чек-іну
/// та ознакою "чи є серед останніх днів хоч один ще не вгаданий".
class RecentActivityItem {
  final String userId;
  final String displayEmail;
  final DateTime latestCreatedAt;
  final bool hasUnguessed;

  RecentActivityItem({
    required this.userId,
    required this.displayEmail,
    required this.latestCreatedAt,
    required this.hasUnguessed,
  });
}

/// Чи є серед членів кіл юзера чек-ін за останні kGuessWindowDays днів, який
/// юзер ще не здогадував (для того самого дня, коли той чек-ін зроблено).
/// Використовується для тихої крапки-індикатора на іконці "Коло" — те саме
/// вікно, що й у стрічці "Нещодавно"/екрані людини.
Future<bool> hasUnseenCircleActivity(SupabaseClient supabase) async {
  final myId = supabase.auth.currentUser?.id;
  if (myId == null) return false;

  final memberRows = await supabase
      .from('circle_members')
      .select('circle_id')
      .eq('user_id', myId)
      .eq('status', 'accepted');
  final circleIds = (memberRows as List).map((r) => r['circle_id'] as String).toList();
  if (circleIds.isEmpty) return false;

  final otherRows = await supabase
      .from('circle_members')
      .select('user_id')
      .inFilter('circle_id', circleIds)
      .eq('status', 'accepted')
      .neq('user_id', myId);
  final otherIds = (otherRows as List)
      .map((r) => r['user_id'] as String?)
      .whereType<String>()
      .toSet()
      .toList();
  if (otherIds.isEmpty) return false;

  final since = DateTime.now().subtract(const Duration(days: kGuessWindowDays));
  final sinceUtc = DateTime(since.year, since.month, since.day).toUtc().toIso8601String();

  final checkinRows = await supabase
      .from('checkins')
      .select('user_id, created_at')
      .inFilter('user_id', otherIds)
      .gte('created_at', sinceUtc)
      .order('created_at', ascending: false);

  final latestByUser = <String, DateTime>{};
  for (final row in checkinRows as List) {
    final uid = row['user_id'] as String;
    if (latestByUser.containsKey(uid)) continue;
    latestByUser[uid] = DateTime.parse(row['created_at'] as String).toLocal();
  }
  if (latestByUser.isEmpty) return false;

  final sinceDate = DateTime(since.year, since.month, since.day).toIso8601String().split('T').first;
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

class CirclesScreen extends StatefulWidget {
  const CirclesScreen({super.key});

  @override
  State<CirclesScreen> createState() => _CirclesScreenState();
}

class _CirclesScreenState extends State<CirclesScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Circle> _myCircles = [];
  List<Map<String, dynamic>> _pendingInvites = [];
  List<RecentActivityItem> _recentActivity = [];

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
      final myEmail = _supabase.auth.currentUser?.email ?? '';

      final memberRows = await _supabase
          .from('circle_members')
          .select('circle_id, circles(id, name, owner_id, invite_code)')
          .eq('user_id', _supabase.auth.currentUser!.id)
          .eq('status', 'accepted');

      final inviteRows = await _supabase
          .from('circle_members')
          .select('id, circle_id, circles(name)')
          .eq('invited_email', myEmail)
          .eq('status', 'invited');

      if (!mounted) return;
      setState(() {
        _myCircles = (memberRows as List).map((row) {
          final c = row['circles'];
          return Circle(
            id: c['id'],
            name: c['name'],
            ownerId: c['owner_id'],
            inviteCode: c['invite_code'],
          );
        }).toList();
        _pendingInvites = (inviteRows as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
      unawaited(_loadRecentActivity());
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context).couldNotLoadCircles;
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadRecentActivity() async {
    final myId = _supabase.auth.currentUser!.id;
    if (_myCircles.isEmpty) {
      if (mounted) setState(() => _recentActivity = []);
      return;
    }
    final circleIds = _myCircles.map((c) => c.id).toList();

    final memberRows = await _supabase
        .from('circle_members')
        .select('user_id, invited_email')
        .inFilter('circle_id', circleIds)
        .eq('status', 'accepted')
        .neq('user_id', myId);

    // Дедуплікація: та сама людина може бути в кількох спільних колах —
    // у "Нещодавно" вона має з'явитись лише раз.
    final emailByUserId = <String, String>{};
    for (final row in memberRows as List) {
      final uid = row['user_id'] as String?;
      if (uid != null) emailByUserId[uid] = row['invited_email'] as String;
    }
    if (emailByUserId.isEmpty) {
      if (mounted) setState(() => _recentActivity = []);
      return;
    }

    final since = DateTime.now().subtract(const Duration(days: kGuessWindowDays));
    final sinceUtc = DateTime(since.year, since.month, since.day).toUtc().toIso8601String();
    final checkinRows = await _supabase
        .from('checkins')
        .select('user_id, created_at')
        .inFilter('user_id', emailByUserId.keys.toList())
        .gte('created_at', sinceUtc)
        .order('created_at', ascending: false);

    final datesByUser = <String, List<DateTime>>{};
    for (final row in checkinRows as List) {
      final uid = row['user_id'] as String;
      final createdAt = DateTime.parse(row['created_at'] as String).toLocal();
      datesByUser.putIfAbsent(uid, () => []).add(createdAt);
    }
    if (datesByUser.isEmpty) {
      if (mounted) setState(() => _recentActivity = []);
      return;
    }

    final sinceDate = DateTime(since.year, since.month, since.day).toIso8601String().split('T').first;
    final guessRows = await _supabase
        .from('circle_guesses')
        .select('target_user_id, target_date')
        .eq('guesser_id', myId)
        .gte('target_date', sinceDate)
        .inFilter('target_user_id', datesByUser.keys.toList());

    final guessedKeys = <String>{};
    for (final row in guessRows as List) {
      final uid = row['target_user_id'] as String;
      final targetDate = DateTime.parse(row['target_date'] as String);
      guessedKeys.add(_entryKey(uid, targetDate));
    }

    final activity = <RecentActivityItem>[];
    for (final entry in datesByUser.entries) {
      final uid = entry.key;
      final dates = entry.value..sort((a, b) => b.compareTo(a));
      final hasUnguessed = dates.any((d) => !guessedKeys.contains(_entryKey(uid, d)));
      activity.add(RecentActivityItem(
        userId: uid,
        displayEmail: emailByUserId[uid] ?? '',
        latestCreatedAt: dates.first,
        hasUnguessed: hasUnguessed,
      ));
    }

    activity.sort((a, b) => b.latestCreatedAt.compareTo(a.latestCreatedAt));

    if (mounted) setState(() => _recentActivity = activity);
  }

  Future<void> _acceptInvite(String memberRowId) async {
    try {
      await _supabase.from('circle_members').update({
        'user_id': _supabase.auth.currentUser!.id,
        'status': 'accepted',
      }).eq('id', memberRowId);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).couldNotAcceptInvite)),
        );
      }
    }
  }

  Future<void> _joinByCode() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text(l10n.joinCircle),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.none,
          decoration: InputDecoration(hintText: l10n.joinCircleHint),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(l10n.join),
          ),
        ],
      ),
    );

    if (code == null || code.isEmpty) return;

    try {
      await _supabase.rpc('join_circle_by_code', params: {'code': code});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.joinedCircleSuccess)),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.invalidInviteCode)),
        );
      }
    }
  }

  Future<void> _createCircle() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text(l10n.newCircle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.circleNameHint),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(l10n.create),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    try {
      final myEmail = _supabase.auth.currentUser?.email ?? '';
      final inserted = await _supabase
          .from('circles')
          .insert({'name': name, 'owner_id': _supabase.auth.currentUser!.id})
          .select('id')
          .single();

      await _supabase.from('circle_members').insert({
        'circle_id': inserted['id'],
        'user_id': _supabase.auth.currentUser!.id,
        'invited_email': myEmail,
        'status': 'accepted',
      });

      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).couldNotCreateCircle)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                  Expanded(child: Text(l10n.circle, style: appSerif(fontSize: 22))),
                  IconButton(
                    onPressed: _joinByCode,
                    icon: const Icon(Icons.vpn_key_outlined, size: 20),
                    tooltip: l10n.haveInviteCode,
                  ),
                  IconButton(
                    onPressed: _createCircle,
                    icon: const Icon(Icons.add, size: 22),
                    tooltip: l10n.newCircle,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Expanded(child: Center(child: Text(_error!, style: const TextStyle(color: AppColors.inkMuted))))
              else
                Expanded(
                  child: ListView(
                    children: [
                      Text(l10n.myCircles, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                      const SizedBox(height: 8),
                      if (_myCircles.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            l10n.noCirclesYet,
                            style: const TextStyle(color: AppColors.inkMuted),
                          ),
                        ),
                      ..._myCircles.map((circle) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => CircleDetailScreen(circle: circle)),
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(circle.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                  ),
                                  const Icon(Icons.chevron_right, size: 20, color: AppColors.inkMuted),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      if (_pendingInvites.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(l10n.invitations, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                        const SizedBox(height: 8),
                        ..._pendingInvites.map((invite) {
                          final circleName = invite['circles']?['name'] ?? l10n.circle;
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
                                  child: Text(circleName, style: const TextStyle(fontSize: 15)),
                                ),
                                TextButton(
                                  onPressed: () => _acceptInvite(invite['id'] as String),
                                  child: Text(l10n.accept),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                      if (_recentActivity.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(l10n.recentActivity, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                        const SizedBox(height: 8),
                        ..._recentActivity.take(5).map((item) {
                          final displayName = item.displayEmail.split('@').first;
                          return InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PersonDetailScreen(
                                  userId: item.userId,
                                  displayEmail: item.displayEmail,
                                ),
                              ),
                            ),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(displayName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                            if (item.hasUnguessed) ...[
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
                                          _relativeDay(item.latestCreatedAt, l10n),
                                          style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right, size: 18, color: AppColors.inkMuted),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CircleMenuRow({
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
            Text(label, style: const TextStyle(fontSize: 16, color: AppColors.ink)),
          ],
        ),
      ),
    );
  }
}

class CircleDetailScreen extends StatefulWidget {
  final Circle circle;

  const CircleDetailScreen({super.key, required this.circle});

  @override
  State<CircleDetailScreen> createState() => _CircleDetailScreenState();
}

class _CircleDetailScreenState extends State<CircleDetailScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  List<CircleMember> _members = [];
  List<CircleMember> _pendingMembers = [];
  List<_MemberSummary> _memberSummaries = [];

  bool get _isOwner => widget.circle.ownerId == _supabase.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final memberRows = await _supabase
        .from('circle_members')
        .select('id, circle_id, user_id, invited_email, status')
        .eq('circle_id', widget.circle.id);

    final allMembers = (memberRows as List).map((row) {
      return CircleMember(
        id: row['id'],
        circleId: row['circle_id'],
        userId: row['user_id'],
        invitedEmail: row['invited_email'],
        status: row['status'],
      );
    }).toList();

    final members = allMembers.where((m) => m.status == 'accepted').toList();
    final pending = allMembers.where((m) => m.status == 'invited').toList();

    final myId = _supabase.auth.currentUser!.id;
    final otherIds = members.map((m) => m.userId).whereType<String>().where((id) => id != myId).toList();
    final emailByUserId = {
      for (final m in members)
        if (m.userId != null) m.userId!: m.invitedEmail,
    };

    final summaries = <_MemberSummary>[];

    if (otherIds.isNotEmpty) {
      // Тільки короткий підсумок по кожному учаснику тут — сама можливість
      // вгадати кожен окремий день живе на екрані конкретної людини.
      final since = DateTime.now().subtract(const Duration(days: kGuessWindowDays));
      final sinceUtc = DateTime(since.year, since.month, since.day).toUtc().toIso8601String();

      final checkinRows = await _supabase
          .from('checkins')
          .select('user_id, mood, created_at')
          .inFilter('user_id', otherIds)
          .gte('created_at', sinceUtc)
          .order('created_at', ascending: false);

      final datesByUser = <String, List<DateTime>>{};
      final latestMoodByUser = <String, MoodLevel>{};
      final latestDateByUser = <String, DateTime>{};
      for (final row in checkinRows as List) {
        final uid = row['user_id'] as String;
        final createdAt = DateTime.parse(row['created_at'] as String).toLocal();
        final date = DateTime(createdAt.year, createdAt.month, createdAt.day);
        datesByUser.putIfAbsent(uid, () => []).add(date);
        if (!latestMoodByUser.containsKey(uid)) {
          latestMoodByUser[uid] = moodFromDbValue(row['mood'] as String);
          latestDateByUser[uid] = date;
        }
      }

      final guessedKeys = <String>{};
      if (datesByUser.isNotEmpty) {
        final sinceDate = DateTime(since.year, since.month, since.day).toIso8601String().split('T').first;
        final guessRows = await _supabase
            .from('circle_guesses')
            .select('target_user_id, target_date')
            .eq('guesser_id', myId)
            .gte('target_date', sinceDate)
            .inFilter('target_user_id', otherIds);

        for (final row in guessRows as List) {
          final uid = row['target_user_id'] as String;
          final targetDate = DateTime.parse(row['target_date'] as String);
          guessedKeys.add(_entryKey(uid, targetDate));
        }
      }

      for (final uid in otherIds) {
        final dates = datesByUser[uid];
        final hasUnguessed = dates != null && dates.any((d) => !guessedKeys.contains(_entryKey(uid, d)));
        summaries.add(_MemberSummary(
          userId: uid,
          displayEmail: emailByUserId[uid] ?? '',
          latestMood: latestMoodByUser[uid],
          latestDate: latestDateByUser[uid],
          hasUnguessed: hasUnguessed,
        ));
      }
    }

    if (!mounted) return;
    setState(() {
      _members = members;
      _pendingMembers = pending;
      _memberSummaries = summaries;
      _loading = false;
    });
  }

  Future<void> _invite() async {
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
              _CircleMenuRow(
                icon: Icons.ios_share,
                label: l10n.shareInviteLink,
                onTap: () => Navigator.of(context).pop('link'),
              ),
              _CircleMenuRow(
                icon: Icons.email_outlined,
                label: l10n.inviteByEmail,
                onTap: () => Navigator.of(context).pop('email'),
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == 'link') {
      await _shareInviteLink();
    } else if (choice == 'email') {
      await _inviteByEmail();
    }
  }

  Future<void> _shareInviteLink() async {
    final l10n = AppLocalizations.of(context);
    final text = l10n.inviteShareText(widget.circle.name, widget.circle.inviteCode);
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _inviteByEmail() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text(l10n.inviteToCircle),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(hintText: l10n.personEmailHint),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(l10n.invite),
          ),
        ],
      ),
    );

    if (email == null || email.isEmpty) return;

    try {
      await _supabase.from('circle_members').insert({
        'circle_id': widget.circle.id,
        'invited_email': email,
        'status': 'invited',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.inviteAdded)),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.couldNotInvite)),
        );
      }
    }
  }

  Future<void> _cancelInvite(String memberId) async {
    try {
      await _supabase.from('circle_members').delete().eq('id', memberId);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).couldNotCancelInvite)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final myId = _supabase.auth.currentUser!.id;
    final others = _members.where((m) => m.userId != myId).toList();

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
                  Expanded(child: Text(widget.circle.name, style: appSerif(fontSize: 22))),
                  if (_isOwner)
                    IconButton(
                      onPressed: _invite,
                      icon: const Icon(Icons.person_add_alt, size: 20),
                      tooltip: l10n.invite,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else
                Expanded(
                  child: ListView(
                    children: [
                      if (_isOwner && _pendingMembers.isNotEmpty) ...[
                        Text(l10n.pending, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                        const SizedBox(height: 8),
                        ..._pendingMembers.map((m) => Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          m.invitedEmail,
                                          style: const TextStyle(fontSize: 14),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          l10n.notJoinedYet,
                                          style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => _cancelInvite(m.id),
                                    icon: const Icon(Icons.close, size: 18),
                                    tooltip: l10n.cancelInviteTooltip,
                                    color: AppColors.inkMuted,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            )),
                        const SizedBox(height: 20),
                      ],
                      if (others.isEmpty && _pendingMembers.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            l10n.nobodyHereYet,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.inkMuted),
                          ),
                        )
                      else if (others.isNotEmpty) ...[
                        Text(l10n.circle, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                        const SizedBox(height: 8),
                        ..._memberSummaries.map(_buildMemberSummaryRow),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMemberSummaryRow(_MemberSummary summary) {
    final l10n = AppLocalizations.of(context);
    final displayName = summary.displayEmail.split('@').first;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PersonDetailScreen(
            userId: summary.userId,
            displayEmail: summary.displayEmail,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            if (summary.latestMood != null) ...[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: summary.latestMood!.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(displayName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      if (summary.hasUnguessed) ...[
                        const SizedBox(width: 6),
                        const DecoratedBox(
                          decoration: BoxDecoration(color: AppColors.notification, shape: BoxShape.circle),
                          child: SizedBox(width: 6, height: 6),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    summary.latestDate == null ? l10n.notCheckedInToday : _relativeDay(summary.latestDate!, l10n),
                    style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.inkMuted),
          ],
        ),
      ),
    );
  }
}

/// Екран однієї людини — до kGuessWindowDays останніх днів її чек-інів,
/// кожен окремо можна вгадати. Єдине місце в застосунку, де відбувається
/// вгадування (список кіл і екран кола ведуть саме сюди).
class PersonDetailScreen extends StatefulWidget {
  final String userId;
  final String displayEmail;

  const PersonDetailScreen({super.key, required this.userId, required this.displayEmail});

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  List<_MemberDayEntry> _entries = [];
  final Map<String, String?> _myGuesses = {};
  final Set<String> _expandedDetails = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final myId = _supabase.auth.currentUser!.id;
    final since = DateTime.now().subtract(const Duration(days: kGuessWindowDays));
    final sinceUtc = DateTime(since.year, since.month, since.day).toUtc().toIso8601String();

    final checkinRows = await _supabase
        .from('checkins')
        .select('mood, note, created_at')
        .eq('user_id', widget.userId)
        .gte('created_at', sinceUtc)
        .order('created_at', ascending: false);

    final entries = <_MemberDayEntry>[];
    final seenDayKeys = <String>{};
    for (final row in checkinRows as List) {
      final createdAt = DateTime.parse(row['created_at'] as String).toLocal();
      final date = DateTime(createdAt.year, createdAt.month, createdAt.day);
      if (!seenDayKeys.add(_entryKey(widget.userId, date))) continue;
      entries.add(_MemberDayEntry(
        userId: widget.userId,
        mood: moodFromDbValue(row['mood'] as String),
        note: row['note'] as String?,
        date: date,
      ));
    }

    final guesses = <String, String?>{};
    if (entries.isNotEmpty) {
      final sinceDate = DateTime(since.year, since.month, since.day).toIso8601String().split('T').first;
      final guessRows = await _supabase
          .from('circle_guesses')
          .select('guessed_mood, target_date')
          .eq('guesser_id', myId)
          .eq('target_user_id', widget.userId)
          .gte('target_date', sinceDate);

      for (final row in guessRows as List) {
        final targetDate = DateTime.parse(row['target_date'] as String);
        guesses[_entryKey(widget.userId, targetDate)] = row['guessed_mood'] as String;
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

  Future<void> _guess(_MemberDayEntry entry, MoodLevel guessedMood) async {
    final targetDate = entry.date.toIso8601String().split('T').first;

    try {
      await _supabase.from('circle_guesses').insert({
        'guesser_id': _supabase.auth.currentUser!.id,
        'target_user_id': entry.userId,
        'target_date': targetDate,
        'guessed_mood': guessedMood.dbValue,
        'correct': guessedMood == entry.mood,
      });
      setState(() => _myGuesses[_entryKey(entry.userId, entry.date)] = guessedMood.dbValue);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).couldNotSaveGuess)),
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
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (_entries.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(l10n.notCheckedInToday, style: const TextStyle(color: AppColors.inkMuted)),
                  ),
                )
              else
                Expanded(
                  child: ListView(children: _entries.map(_buildEntryCard).toList()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntryCard(_MemberDayEntry entry) {
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
                  decoration: BoxDecoration(color: entry.mood.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(entry.mood.label(context), style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 10),
                Text(
                  myGuess == entry.mood.dbValue ? l10n.guessedRight : l10n.guessedWrong,
                  style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                ),
              ],
            ),
            if ((entry.note ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () => setState(() {
                  if (_expandedDetails.contains(key)) {
                    _expandedDetails.remove(key);
                  } else {
                    _expandedDetails.add(key);
                  }
                }),
                child: Text(
                  _expandedDetails.contains(key) ? l10n.hideDetails : l10n.showDetails,
                  style: TextStyle(fontSize: 12, color: MoodLevel.zbs.color),
                ),
              ),
              if (_expandedDetails.contains(key)) ...[
                const SizedBox(height: 6),
                Text(
                  entry.note!,
                  style: const TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
                ),
              ],
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    child: Text(mood.label(context), style: const TextStyle(fontSize: 13)),
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
