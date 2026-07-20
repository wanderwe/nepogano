import 'package:flutter/material.dart';
import 'l10n/app_localizations.dart';
import 'style.dart';

/// Дає перетягнути фото вертикально в рамці тієї ж пропорції (16:10), що
/// й картка дня — щоб підняти/опустити видиму частину, якщо BoxFit.cover
/// десь зрізав важливе (наприклад, голову). Повертає нове alignY (-1..1)
/// через Navigator.pop, або null якщо закрито без змін.
class PhotoRepositionScreen extends StatefulWidget {
  final ImageProvider image;
  final double initialAlignY;

  const PhotoRepositionScreen({
    super.key,
    required this.image,
    this.initialAlignY = 0,
  });

  @override
  State<PhotoRepositionScreen> createState() => _PhotoRepositionScreenState();
}

class _PhotoRepositionScreenState extends State<PhotoRepositionScreen> {
  late double _alignY = widget.initialAlignY;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: l10n.cancel,
                  ),
                  Expanded(
                    child: Text(
                      l10n.repositionPhoto,
                      textAlign: TextAlign.center,
                      style: appSerif(fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l10n.repositionPhotoHint,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
              ),
              const SizedBox(height: 24),
              AspectRatio(
                aspectRatio: 16 / 10,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: GestureDetector(
                        onVerticalDragUpdate: (details) {
                          setState(() {
                            _alignY =
                                (_alignY +
                                        details.delta.dy /
                                            (constraints.maxHeight / 2))
                                    .clamp(-1.0, 1.0);
                          });
                        },
                        child: Image(
                          image: widget.image,
                          fit: BoxFit.cover,
                          alignment: Alignment(0, _alignY),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(_alignY),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppColors.ink,
                    foregroundColor: AppColors.background,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(l10n.done),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
