import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/location/location_providers.dart';
import '../../../core/location/location_result.dart';
import '../../../core/platform/external_actions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/components/buttons/sa_button.dart';
import '../../../shared/components/cards/sa_card.dart';
import '../../../shared/components/feedback/sa_empty_state.dart';
import '../../../shared/components/feedback/sa_loading_shimmer.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/components/overlays/sa_toast.dart';
import '../data/safety_providers.dart';
import '../domain/models/nearby_place.dart';
import '../domain/safety_repository.dart';

/// Real police stations, hospitals, pharmacies, transit stops and shelters
/// around the user's actual position.
///
/// Every row is a real place from the backend's OpenStreetMap lookup, with a
/// real computed distance. Nothing is hardcoded and nothing is shown when the
/// lookup fails — the failure is stated instead.
class NearbySafetyScreen extends ConsumerStatefulWidget {
  const NearbySafetyScreen({super.key});

  @override
  ConsumerState<NearbySafetyScreen> createState() => _NearbySafetyScreenState();
}

class _NearbySafetyScreenState extends ConsumerState<NearbySafetyScreen> {
  static const _actions = ExternalActions();

  NearbyPlaceCategory? _filter;
  _NearbyState _state = const _NearbyLoading();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _state = const _NearbyLoading());

    final fix = await ref.read(locationServiceProvider).getCurrentLocation();
    if (!mounted) return;

    if (fix is! LocationAvailable) {
      setState(() => _state = _NearbyNoLocation(fix as LocationUnavailable));
      return;
    }

    try {
      final places = await ref
          .read(safetyRepositoryProvider)
          .findNearby(latitude: fix.latitude, longitude: fix.longitude, radiusMetres: 5000);
      if (!mounted) return;
      setState(() => _state = _NearbyLoaded(places));
    } on NearbyRateLimitedException {
      if (!mounted) return;
      setState(() => _state = const _NearbyError(
        title: 'Too many lookups right now',
        body: 'The nearby-places service is busy. Try again in a moment.',
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = const _NearbyError(
        title: "Couldn't load nearby places",
        body: 'Check your connection and try again.',
      ));
    }
  }

  Future<void> _call(String phone) async {
    if (await _actions.dial(phone)) return;
    if (mounted) showSaToast(context, message: 'No dialler available on this device', type: SaToastType.error);
  }

  Future<void> _navigate(NearbyPlace place) async {
    final ok = await _actions.navigateTo(
      latitude: place.latitude,
      longitude: place.longitude,
      label: place.name,
    );
    if (!ok && mounted) {
      showSaToast(context, message: 'No maps app available on this device', type: SaToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

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
                      'Nearby Safety',
                      style: AppTypography.headingM.copyWith(color: onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const SaIcon(SaIconGlyph.refresh),
                    onPressed: _load,
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),
            if (_state is _NearbyLoaded) _CategoryFilterBar(
              selected: _filter,
              onChanged: (value) => setState(() => _filter = value),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return switch (_state) {
      _NearbyLoading() => const _NearbyLoadingList(),
      _NearbyNoLocation(:final failure) => SaEmptyState(
        title: 'Location permission required',
        body: failure.userMessage,
        ctaLabel: 'Try again',
        onCtaTap: _load,
      ),
      _NearbyError(:final title, :final body) => SaEmptyState(
        title: title,
        body: body,
        ctaLabel: 'Retry',
        onCtaTap: _load,
      ),
      _NearbyLoaded(:final places) => _buildList(places),
    };
  }

  Widget _buildList(List<NearbyPlace> places) {
    final visible = _filter == null ? places : places.where((p) => p.category == _filter).toList();

    if (visible.isEmpty) {
      return SaEmptyState(
        title: places.isEmpty ? 'Nothing found nearby' : 'No ${_filter!.label.toLowerCase()} nearby',
        body: places.isEmpty
            ? 'No mapped safety locations within 5 km of your current position.'
            : 'Try another category, or clear the filter to see everything nearby.',
        ctaLabel: _filter == null ? 'Refresh' : 'Clear filter',
        onCtaTap: _filter == null ? _load : () => setState(() => _filter = null),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenMarginPhone,
        AppSpacing.space3,
        AppSpacing.screenMarginPhone,
        AppSpacing.space6,
      ),
      itemCount: visible.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.space3),
      itemBuilder: (context, index) => _PlaceCard(
        place: visible[index],
        onCall: () => _call(visible[index].phone!),
        onNavigate: () => _navigate(visible[index]),
      ),
    );
  }
}

sealed class _NearbyState {
  const _NearbyState();
}

class _NearbyLoading extends _NearbyState {
  const _NearbyLoading();
}

class _NearbyLoaded extends _NearbyState {
  const _NearbyLoaded(this.places);
  final List<NearbyPlace> places;
}

class _NearbyNoLocation extends _NearbyState {
  const _NearbyNoLocation(this.failure);
  final LocationUnavailable failure;
}

class _NearbyError extends _NearbyState {
  const _NearbyError({required this.title, required this.body});
  final String title;
  final String body;
}

class _CategoryFilterBar extends StatelessWidget {
  const _CategoryFilterBar({required this.selected, required this.onChanged});

  final NearbyPlaceCategory? selected;
  final ValueChanged<NearbyPlaceCategory?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
        children: [
          _Chip(label: 'All', isSelected: selected == null, onTap: () => onChanged(null)),
          for (final category in NearbyPlaceCategory.values)
            _Chip(
              label: category.label,
              isSelected: selected == category,
              onTap: () => onChanged(selected == category ? null : category),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.isSelected, required this.onTap});

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

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place, required this.onCall, required this.onNavigate});

  final NearbyPlace place;
  final VoidCallback onCall;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final accent = switch (place.category) {
      NearbyPlaceCategory.police => AppColors.violet500,
      NearbyPlaceCategory.hospital => AppColors.coral500,
      NearbyPlaceCategory.fireStation => AppColors.warning500,
      _ => AppColors.info500,
    };

    return SaCard(
      semanticsLabel: '${place.name}, ${place.category.label}, ${place.distanceLabel} away',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(child: SaIcon(SaIconGlyph.mapPin, size: 20, color: accent)),
              ),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      style: AppTypography.labelL.copyWith(color: onSurface),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${place.category.label} · ${place.distanceLabel}',
                      style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.6)),
                    ),
                    if (place.address != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        place.address!,
                        style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.5)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space3),
          Row(
            children: [
              Expanded(
                child: SaButton(
                  label: 'Directions',
                  onPressed: onNavigate,
                  variant: SaButtonVariant.secondary,
                  size: SaButtonSize.sm,
                ),
              ),
              // Only rendered when OSM actually has a phone number for this
              // place — never a dead Call button.
              if (place.phone != null) ...[
                const SizedBox(width: AppSpacing.space2),
                Expanded(
                  child: SaButton(label: 'Call', onPressed: onCall, size: SaButtonSize.sm),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _NearbyLoadingList extends StatelessWidget {
  const _NearbyLoadingList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.screenMarginPhone),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.space3),
      itemBuilder: (_, __) => const SaLoadingShimmer(
        child: SizedBox(height: 132, width: double.infinity),
      ),
    );
  }
}
