import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/components/feedback/sa_empty_state.dart';
import '../../../shared/components/feedback/sa_loading_shimmer.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../data/device_providers.dart';
import 'widgets/ble_pairing_sheet.dart';
import 'widgets/device_expandable_card.dart';
import 'widgets/pair_device_card.dart';

/// Device list + per-device expansion + BLE pairing. Also serves as the
/// "/devices/:id" deep-link target from Home — when [initialExpandedId] is
/// set, that device's card starts expanded.
class DeviceManagementScreen extends ConsumerWidget {
  const DeviceManagementScreen({super.key, this.initialExpandedId});

  final String? initialExpandedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(devicesProvider);

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
            title: devicesAsync.maybeWhen(
              data: (devices) => Text('Devices (${devices.length})'),
              orElse: () => const Text('Devices'),
            ),
          ),
          devicesAsync.when(
            data: (devices) => devices.isEmpty
                ? SliverFillRemaining(
                    child: SaEmptyState(
                      title: 'No devices yet',
                      body: 'Pair a SafeHer device to start monitoring.',
                      ctaLabel: 'Pair Device',
                      onCtaTap: () => showBlePairingSheet(context),
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.all(AppSpacing.screenMarginPhone),
                    sliver: SliverList.separated(
                      itemCount: devices.length + 1,
                      separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.space4),
                      itemBuilder: (context, index) {
                        if (index == devices.length) {
                          return PairDeviceCard(onTap: () => showBlePairingSheet(context));
                        }
                        final device = devices[index];
                        return DeviceExpandableCard(
                          key: ValueKey(device.id),
                          device: device,
                          initiallyExpanded: device.id == initialExpandedId,
                        );
                      },
                    ),
                  ),
            loading: () => SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.screenMarginPhone),
              sliver: SliverList.list(
                children: [
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.space4),
                      child: SaLoadingShimmer(
                        child: Container(
                          height: 170,
                          decoration: BoxDecoration(color: Colors.white, borderRadius: AppRadius.xl2Radius),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            error: (error, stackTrace) => SliverFillRemaining(
              child: SaEmptyState(
                title: "Couldn't load your devices",
                body: 'Check your connection and try again.',
                ctaLabel: 'Retry',
                onCtaTap: () => ref.invalidate(devicesProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
