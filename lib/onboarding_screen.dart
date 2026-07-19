import 'package:flutter/material.dart';
import 'l10n/app_localizations.dart';
import 'style.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;

  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pageCount = 5;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _pageCount - 1) {
      widget.onDone();
      return;
    }
    _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pages = [
      _OnboardingPage(
        headline: l10n.onboarding1Headline,
        body: l10n.onboarding1Body,
      ),
      _OnboardingPage(
        headline: l10n.onboarding2Headline,
        body: l10n.onboarding2Body,
      ),
      _OnboardingPage(
        headline: l10n.onboarding3Headline,
        body: l10n.onboarding3Body,
      ),
      _OnboardingPage(
        headline: l10n.onboarding4Headline,
        body: l10n.onboarding4Body,
      ),
      _OnboardingPage(
        headline: l10n.onboarding5Headline,
        body: l10n.onboarding5Body,
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: widget.onDone,
                  child: Text(l10n.skip, style: const TextStyle(color: AppColors.inkMuted)),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: pages,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pageCount, (i) {
                  final active = i == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active ? AppColors.ink : AppColors.divider,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _next,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppColors.ink,
                  foregroundColor: AppColors.background,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(_page == _pageCount - 1 ? l10n.getStarted : l10n.next),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final String headline;
  final String body;

  const _OnboardingPage({required this.headline, required this.body});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            headline,
            textAlign: TextAlign.center,
            style: appSerif(fontSize: 28, fontWeight: FontWeight.w700, height: 1.2),
          ),
          const SizedBox(height: 16),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: AppColors.inkMuted, height: 1.4),
          ),
        ],
      ),
    );
  }
}
