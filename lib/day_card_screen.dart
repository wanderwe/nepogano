import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'history_screen.dart';
import 'main.dart';
import 'social_share.dart';
import 'style.dart';

const _weekdayNamesFull = [
  'понеділок', 'вівторок', 'середа', 'четвер', "п'ятниця", 'субота', 'неділя',
];

const _monthNamesGenitive = [
  'січня', 'лютого', 'березня', 'квітня', 'травня', 'червня',
  'липня', 'серпня', 'вересня', 'жовтня', 'листопада', 'грудня',
];

class DayCardScreen extends StatefulWidget {
  final CheckinEntry entry;

  const DayCardScreen({super.key, required this.entry});

  @override
  State<DayCardScreen> createState() => _DayCardScreenState();
}

class _DayCardScreenState extends State<DayCardScreen> {
  final _boundaryKey = GlobalKey();
  bool _sharing = false;

  Future<String> _renderCardToFile() async {
    final boundary = _boundaryKey.currentContext!.findRenderObject()
        as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/nepogano_day_card.png');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final path = await _renderCardToFile();
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], text: 'Мій день у Nepogano'),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не вдалось поділитись. Спробуй ще раз.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _openMultiShareSheet() async {
    setState(() => _sharing = true);
    String path;
    try {
      path = await _renderCardToFile();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не вдалось підготувати картку. Спробуй ще раз.')),
        );
      }
      setState(() => _sharing = false);
      return;
    }
    setState(() => _sharing = false);

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _MultiShareSheet(imagePath: path),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                    tooltip: 'Назад',
                  ),
                  const SizedBox(width: 4),
                  Text('Картка дня', style: appSerif(fontSize: 22)),
                ],
              ),
              const SizedBox(height: 32),
              Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: AppShadows.soft,
                  ),
                  child: RepaintBoundary(
                    key: _boundaryKey,
                    child: _DayCard(entry: widget.entry),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _sharing ? null : _share,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppColors.ink,
                    foregroundColor: AppColors.background,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _sharing
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.background,
                          ),
                        )
                      : const Icon(Icons.ios_share, size: 18),
                  label: const Text('Поділитись', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _sharing ? null : _openMultiShareSheet,
                  child: const Text('Поділитись у соцмережах'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MultiShareSheet extends StatefulWidget {
  final String imagePath;

  const _MultiShareSheet({required this.imagePath});

  @override
  State<_MultiShareSheet> createState() => _MultiShareSheetState();
}

class _MultiShareSheetState extends State<_MultiShareSheet> {
  final Set<String> _done = {};

  Future<void> _shareInstagram() async {
    final ok = await SocialShare.instagramStory(widget.imagePath);
    if (!ok && mounted) {
      _showNotInstalled('Instagram');
      return;
    }
    if (mounted) setState(() => _done.add('instagram'));
  }

  Future<void> _shareFacebook() async {
    final ok = await SocialShare.toPackage(widget.imagePath, 'com.facebook.katana');
    if (!ok && mounted) {
      _showNotInstalled('Facebook');
      return;
    }
    if (mounted) setState(() => _done.add('facebook'));
  }

  Future<void> _shareTikTok() async {
    var ok = await SocialShare.toPackage(widget.imagePath, 'com.zhiliaoapp.musically');
    if (!ok) {
      ok = await SocialShare.toPackage(widget.imagePath, 'com.ss.android.ugc.trill');
    }
    if (!ok && mounted) {
      _showNotInstalled('TikTok');
      return;
    }
    if (mounted) setState(() => _done.add('tiktok'));
  }

  Future<void> _shareOther() async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(widget.imagePath)], text: 'Мій день у Nepogano'),
    );
    if (mounted) setState(() => _done.add('other'));
  }

  void _showNotInstalled(String app) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$app не встановлено на пристрої.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Поділитись у соцмережах', style: appSerif(fontSize: 18)),
            const SizedBox(height: 4),
            const Text(
              'Тапни застосунок — після повернення тапни наступний.',
              style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
            ),
            const SizedBox(height: 20),
            _ShareRow(label: 'Instagram Stories', done: _done.contains('instagram'), onTap: _shareInstagram),
            _ShareRow(label: 'Facebook', done: _done.contains('facebook'), onTap: _shareFacebook),
            _ShareRow(label: 'TikTok', done: _done.contains('tiktok'), onTap: _shareTikTok),
            _ShareRow(label: 'Інше', done: _done.contains('other'), onTap: _shareOther),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Готово'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareRow extends StatelessWidget {
  final String label;
  final bool done;
  final VoidCallback onTap;

  const _ShareRow({required this.label, required this.done, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 16, color: AppColors.ink)),
            ),
            Icon(
              done ? Icons.check_circle : Icons.chevron_right,
              size: 20,
              color: done ? MoodLevel.zbs.color : AppColors.inkMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final CheckinEntry entry;

  const _DayCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final d = entry.createdAt;
    final dateLabel = '${d.day} ${_monthNamesGenitive[d.month - 1]}';
    final weekdayLabel = _weekdayNamesFull[d.weekday - 1];
    final moodIndex = MoodLevel.values.indexOf(entry.mood);

    return Container(
      width: 320,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                dateLabel,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
              Text(
                weekdayLabel,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '${entry.mood.label}.',
            style: appSerif(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          if (entry.note != null && entry.note!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              entry.note!,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade300, height: 1.4),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: List.generate(MoodLevel.values.length, (i) {
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(
                    right: i == MoodLevel.values.length - 1 ? 0 : 8,
                  ),
                  decoration: BoxDecoration(
                    color: i == moodIndex ? Colors.white : Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
          Text(
            'nepogano.app',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
