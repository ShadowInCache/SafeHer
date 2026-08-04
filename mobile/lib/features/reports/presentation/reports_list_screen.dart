import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/components/cards/sa_incident_card.dart';
import '../../../shared/components/feedback/sa_empty_state.dart';
import '../../../shared/components/feedback/sa_loading_shimmer.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../data/reports_providers.dart';

/// Full history of past incident reports.
class ReportsListScreen extends ConsumerWidget {
  const ReportsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(reportsListProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            leading: IconButton(
              icon: const SaIcon(SaIconGlyph.chevronLeft),
              onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
              tooltip: 'Back',
            ),
            title: reportsAsync.maybeWhen(
              data: (reports) => Text('Reports (${reports.length})'),
              orElse: () => const Text('Reports'),
            ),
          ),
          reportsAsync.when(
            data: (reports) => reports.isEmpty
                ? const SliverFillRemaining(
                    child: SaEmptyState(
                      title: 'No reports yet',
                      body: 'Incidents detected by your devices will show up here.',
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.all(AppSpacing.screenMarginPhone),
                    sliver: SliverList.separated(
                      itemCount: reports.length,
                      separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.space3),
                      itemBuilder: (context, index) {
                        final report = reports[index];
                        return SaIncidentCard(
                          date: report.date,
                          type: report.type,
                          level: report.level,
                          summarySnippet: report.summarySnippet,
                          onTap: () => context.go('/reports/${report.id}'),
                        );
                      },
                    ),
                  ),
            loading: () => SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.screenMarginPhone),
              sliver: SliverList.list(
                children: [
                  for (var i = 0; i < 4; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.space3),
                      child: SaLoadingShimmer(
                        child: Container(
                          height: 76,
                          decoration: BoxDecoration(color: Colors.white, borderRadius: AppRadius.lgRadius),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            error: (error, stackTrace) => SliverFillRemaining(
              child: SaEmptyState(
                title: "Couldn't load your reports",
                body: 'Check your connection and try again.',
                ctaLabel: 'Retry',
                onCtaTap: () => ref.invalidate(reportsListProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
