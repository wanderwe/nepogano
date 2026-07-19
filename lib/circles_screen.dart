import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'l10n/app_localizations.dart';
import 'main.dart';
import 'style.dart';

/// Унікальний ключ для (учасник, день) — щоб кожен день зберігав власний
/// статус вгадування незалежно від інших днів того самого учасника.
String _entryKey(String userId, DateTime date) =>
    '$userId|${date.year}-${date.month}-${date.day}';

/// Один чек-ін конкретного учасника за конкретний день у вікні "нещодавно"
/// (останні 3 дні) — на відміну від "тільки останній запис", дозволяє
/// бачити й вгадувати кожен день окремо.
class _MemberDayEntry {
  final String userId;
  final String displayEmail;
  final MoodLevel mood;
  final String? note;
  final DateTime date;

  _MemberDayEntry({
    required this.userId,
    required this.displayEmail,
    required this.mood,
    required this.note,
    required this.date,
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

class RecentActivityItem {
  final String circleId;
  final String circleName;
  final String userId;
  final String displayEmail;
  final DateTime createdAt;
  final bool isGuessed;

  RecentActivityItem({
    required this.circleId,
    required this.circleName,
    required this.userId,
    required this.displayEmail,
    required this.createdAt,
    required this.isGuessed,
  });
}

/// Чи є серед членів кіл юзера чек-ін за останні 3 дні, який юзер ще не здогадував
/// (для того самого дня, коли той чек-ін зроблено). Використовується для тихої
/// крапки-індикатора на іконці "Коло" — той самий вікно, що й у стрічці "Нещодавно".
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

  final since = DateTime.now().subtract(const Duration(days: 3));
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
        .select('user_id, invited_email, circle_id')
        .inFilter('circle_id', circleIds)
        .eq('status', 'accepted')
        .neq('user_id', myId);

    final membersByUserId = <String, Map<String, dynamic>>{};
    for (final row in memberRows as List) {
      final uid = row['user_id'] as String?;
      if (uid != null) membersByUserId[uid] = row;
    }
    if (membersByUserId.isEmpty) {
      if (mounted) setState(() => _recentActivity = []);
      return;
    }

    final since = DateTime.now().subtract(const Duration(days: 3));
    final sinceUtc = since.toUtc().toIso8601String();
    final checkinRows = await _supabase
        .from('checkins')
        .select('user_id, created_at')
        .inFilter('user_id', membersByUserId.keys.toList())
        .gte('created_at', sinceUtc)
        .order('created_at', ascending: false);

    final sinceDate = DateTime(since.year, since.month, since.day).toIso8601String().split('T').first;
    final guessRows = await _supabase
        .from('circle_guesses')
        .select('target_user_id, target_date')
        .eq('guesser_id', myId)
        .gte('target_date', sinceDate)
        .inFilter('target_user_id', membersByUserId.keys.toList());

    final guessedDatesByUser = <String, Set<String>>{};
    for (final row in guessRows as List) {
      final uid = row['target_user_id'] as String;
      final date = row['target_date'] as String;
      guessedDatesByUser.putIfAbsent(uid, () => {}).add(date);
    }

    final circleNameById = {for (final c in _myCircles) c.id: c.name};

    final activity = <RecentActivityItem>[];
    for (final row in checkinRows as List) {
      final uid = row['user_id'] as String;
      final member = membersByUserId[uid];
      if (member == null) continue;
      final circleId = member['circle_id'] as String;
      final createdAt = DateTime.parse(row['created_at'] as String).toLocal();
      final entryDate = DateTime(createdAt.year, createdAt.month, createdAt.day).toIso8601String().split('T').first;
      activity.add(RecentActivityItem(
        circleId: circleId,
        circleName: circleNameById[circleId] ?? '',
        userId: uid,
        displayEmail: member['invited_email'] as String,
        createdAt: createdAt,
        isGuessed: guessedDatesByUser[uid]?.contains(entryDate) ?? false,
      ));
    }

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
                            onTap: () {
                              final circle = _myCircles.firstWhere((c) => c.id == item.circleId);
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => CircleDetailScreen(circle: circle)),
                              );
                            },
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
                                            if (!item.isGuessed) ...[
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
                                          '${item.circleName} · ${_relativeDay(item.createdAt, l10n)}',
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
  List<_MemberDayEntry> _recentEntries = [];
  final Map<String, String?> _myGuesses = {};
  final Set<String> _expandedDetails = {};

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

    final entries = <_MemberDayEntry>[];
    final guesses = <String, String?>{};

    if (otherIds.isNotEmpty) {
      // Кожен день кожного за останні 3 дні окремо (не тільки останній) —
      // щоб стрічка "Нещодавно" (яка сягає на кілька днів назад) вела до
      // конкретного дня, а не завжди до того, що зараз найновіше.
      final since = DateTime.now().subtract(const Duration(days: 3));
      final sinceUtc = DateTime(since.year, since.month, since.day).toUtc().toIso8601String();

      final checkinRows = await _supabase
          .from('checkins')
          .select('user_id, mood, note, created_at')
          .inFilter('user_id', otherIds)
          .gte('created_at', sinceUtc)
          .order('created_at', ascending: false);

      final seenDayKeys = <String>{};
      for (final row in checkinRows as List) {
        final uid = row['user_id'] as String;
        final createdAt = DateTime.parse(row['created_at'] as String).toLocal();
        final date = DateTime(createdAt.year, createdAt.month, createdAt.day);
        // На день гарантовано один чек-ін, але про всяк випадок лишаємо
        // найновіший запис цього дня (перший у desc-порядку).
        if (!seenDayKeys.add(_entryKey(uid, date))) continue;
        entries.add(_MemberDayEntry(
          userId: uid,
          displayEmail: emailByUserId[uid] ?? '',
          mood: moodFromDbValue(row['mood'] as String),
          note: row['note'] as String?,
          date: date,
        ));
      }

      if (entries.isNotEmpty) {
        final sinceDate = DateTime(since.year, since.month, since.day).toIso8601String().split('T').first;
        final guessRows = await _supabase
            .from('circle_guesses')
            .select('target_user_id, guessed_mood, target_date')
            .eq('guesser_id', myId)
            .gte('target_date', sinceDate)
            .inFilter('target_user_id', otherIds);

        for (final row in guessRows as List) {
          final uid = row['target_user_id'] as String;
          final targetDate = DateTime.parse(row['target_date'] as String);
          guesses[_entryKey(uid, targetDate)] = row['guessed_mood'] as String;
        }
      }
    }

    entries.sort((a, b) => b.date.compareTo(a.date));

    if (!mounted) return;
    setState(() {
      _members = members;
      _pendingMembers = pending;
      _recentEntries = entries;
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
                        ..._recentEntries.map(_buildEntryCard),
                        ...others
                            .where((m) => !_recentEntries.any((e) => e.userId == m.userId))
                            .map(_buildNoEntryCard),
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

  Widget _buildNoEntryCard(CircleMember member) {
    final l10n = AppLocalizations.of(context);
    final displayName = member.invitedEmail.split('@').first;

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
          Text(displayName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text(
            l10n.notCheckedInToday,
            style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryCard(_MemberDayEntry entry) {
    final l10n = AppLocalizations.of(context);
    final displayName = entry.displayEmail.split('@').first;
    final key = _entryKey(entry.userId, entry.date);
    final myGuess = _myGuesses[key];
    final isToday = entry.date.year == DateTime.now().year &&
        entry.date.month == DateTime.now().month &&
        entry.date.day == DateTime.now().day;

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
          Row(
            children: [
              Text(displayName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              if (!isToday) ...[
                const SizedBox(width: 8),
                Text(
                  _relativeDay(entry.date, l10n),
                  style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
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
