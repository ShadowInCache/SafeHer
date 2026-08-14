import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/components/cards/sa_card.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../domain/models/safety_guide.dart';

/// Short, original safety and self-defence guidance.
///
/// Kept intentionally small — this complements the wearable system rather
/// than competing with it for the user's attention.
class SafetyGuidesScreen extends StatefulWidget {
  const SafetyGuidesScreen({super.key});

  @override
  State<SafetyGuidesScreen> createState() => _SafetyGuidesScreenState();
}

class _SafetyGuidesScreenState extends State<SafetyGuidesScreen> {
  SafetyGuideCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final guides = _filter == null ? SafetyGuides.all : SafetyGuides.byCategory(_filter!);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space2,
                AppSpacing.space2,
                AppSpacing.screenMarginPhone,
                0,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const SaIcon(SaIconGlyph.chevronLeft),
                    onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
                    tooltip: 'Back',
                  ),
                  Expanded(
                    child: Text(
                      'Safety & Awareness',
                      style: AppTypography.headingM.copyWith(color: onSurface),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
                children: [
                  _FilterChip(
                    label: 'All',
                    isSelected: _filter == null,
                    onTap: () => setState(() => _filter = null),
                  ),
                  for (final category in SafetyGuideCategory.values)
                    _FilterChip(
                      label: category.label,
                      isSelected: _filter == category,
                      onTap: () => setState(() => _filter = _filter == category ? null : category),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenMarginPhone,
                  AppSpacing.space3,
                  AppSpacing.screenMarginPhone,
                  AppSpacing.space6,
                ),
                itemCount: guides.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.space3),
                itemBuilder: (context, index) => _GuideCard(guide: guides[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.isSelected, required this.onTap});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.space2),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.violet500 : onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: AppTypography.labelM.copyWith(
              color: isSelected ? Colors.white : onSurface.withValues(alpha: 0.75),
            ),
          ),
        ),
      ),
    );
  }
}

class _GuideCard extends StatefulWidget {
  const _GuideCard({required this.guide});

  final SafetyGuide guide;

  @override
  State<_GuideCard> createState() => _GuideCardState();
}

class _GuideCardState extends State<_GuideCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return SaCard(
      onTap: () => setState(() => _expanded = !_expanded),
      semanticsLabel: widget.guide.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.guide.category.label.toUpperCase(),
            style: AppTypography.labelM.copyWith(
              color: AppColors.violet500,
              letterSpacing: 1.1,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: AppSpacing.space2),
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.guide.title,
                  style: AppTypography.labelL.copyWith(color: onSurface),
                ),
              ),
              SaIcon(
                _expanded ? SaIconGlyph.chevronLeft : SaIconGlyph.chevronRight,
                size: 18,
                color: onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space1),
          Text(
            widget.guide.summary,
            style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.6)),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.space3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final point in widget.guide.points)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.space2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 7, right: AppSpacing.space2),
                            child: Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                color: AppColors.violet500,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              point,
                              style: AppTypography.bodyM.copyWith(
                                color: onSurface.withValues(alpha: 0.8),
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
        ],
      ),
    );
  }
}
