import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../shared/components/cards/sa_card.dart';
import '../../../shared/components/cards/sa_contact_card.dart';
import '../../../shared/components/cards/sa_device_card.dart';
import '../../../shared/components/cards/sa_incident_card.dart';
import '../../../shared/components/feedback/sa_empty_state.dart';
import '../../../shared/components/feedback/sa_loading_shimmer.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/components/inputs/sa_search_bar.dart';
import '../../../shared/components/overlays/sa_toast.dart';
import '../../contacts/data/contacts_providers.dart';
import '../../contacts/domain/models/contact.dart';
import '../../devices/data/device_providers.dart';
import '../../devices/domain/models/device_detail.dart';
import '../../reports/data/reports_providers.dart';
import '../../reports/domain/models/report_summary.dart';
import '../domain/models/search_result.dart';
import '../domain/models/searchable_setting.dart';

/// Unified search across incidents, contacts, devices, and settings. Reads
/// straight from each feature's own shared provider (the same one Reports,
/// Settings, and Devices use) rather than a separate copy of the data, so
/// results here always match what those screens show. Filters client-side
/// as the user types, debounced by 250ms.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  SearchCategory _category = SearchCategory.all;

  /// Session-only — there's no persisted search-history store yet,  so this
  /// intentionally doesn't survive an app restart rather than pretending to
  /// with a fake always-empty "history".
  final List<String> _recentSearches = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _handleQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final trimmed = value.trim();
      setState(() => _query = trimmed);
      // Recorded once the query settles (debounce fired), not on every
      // keystroke — this also sidesteps needing a real IME "submit" event
      // to fire, so it works identically for a tap-to-select recent term.
      if (trimmed.isNotEmpty) _commitSearch(trimmed);
    });
  }

  void _commitSearch(String trimmed) {
    setState(() {
      _recentSearches.remove(trimmed);
      _recentSearches.insert(0, trimmed);
      if (_recentSearches.length > 5) _recentSearches.removeLast();
    });
  }

  void _selectRecent(String value) {
    _controller.text = value;
    setState(() => _query = value);
  }

  void _handleMicTap() {
    // No speech-recognition engine is wired up in this build — flagging
    // that honestly rather than showing a full "Listening..." overlay
    // that can't actually transcribe anything.
    showSaToast(context, message: "Voice search isn't available in this build yet.");
  }

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(reportsListProvider);
    final contactsAsync = ref.watch(contactsNotifierProvider);
    final devicesAsync = ref.watch(devicesProvider);

    final error = reportsAsync.error ?? contactsAsync.error ?? devicesAsync.error;
    final hasAllData = reportsAsync.hasValue && contactsAsync.hasValue && devicesAsync.hasValue;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenMarginPhone,
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
                    child: SaSearchBar(
                      controller: _controller,
                      autofocus: true,
                      hintText: 'Search incidents, contacts, devices',
                      onChanged: _handleQueryChanged,
                      onMicTap: _handleMicTap,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.space3),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
              child: Row(
                children: [
                  for (final category in SearchCategory.values) ...[
                    _CategoryChip(
                      label: category.label,
                      selected: _category == category,
                      onTap: () => setState(() => _category = category),
                    ),
                    if (category != SearchCategory.values.last) const SizedBox(width: AppSpacing.space2),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.space3),
            Expanded(
              child: error != null
                  ? SaEmptyState(
                      title: "Couldn't load search",
                      body: 'Check your connection and try again.',
                      ctaLabel: 'Retry',
                      onCtaTap: () {
                        ref.invalidate(reportsListProvider);
                        ref.invalidate(contactsNotifierProvider);
                        ref.invalidate(devicesProvider);
                      },
                    )
                  : !hasAllData
                  ? const _SearchLoading()
                  : _SearchResults(
                      incidents: reportsAsync.requireValue,
                      contacts: contactsAsync.requireValue,
                      devices: devicesAsync.requireValue,
                      query: _query,
                      category: _category,
                      recentSearches: _recentSearches,
                      onRecentTap: _selectRecent,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on SearchCategory {
  String get label => switch (this) {
    SearchCategory.all => 'All',
    SearchCategory.incidents => 'Incidents',
    SearchCategory.contacts => 'Contacts',
    SearchCategory.devices => 'Devices',
    SearchCategory.settings => 'Settings',
  };
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space2),
          decoration: BoxDecoration(
            color: selected ? AppColors.violet500 : saColors.surfaceElevated,
            borderRadius: AppRadius.fullRadius,
            border: Border.all(color: selected ? AppColors.violet500 : saColors.glassBorder),
          ),
          child: Text(
            label,
            style: AppTypography.labelM.copyWith(color: selected ? Colors.white : onSurface.withValues(alpha: 0.7)),
          ),
        ),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.incidents,
    required this.contacts,
    required this.devices,
    required this.query,
    required this.category,
    required this.recentSearches,
    required this.onRecentTap,
  });

  final List<ReportSummary> incidents;
  final List<Contact> contacts;
  final List<DeviceDetail> devices;
  final String query;
  final SearchCategory category;
  final List<String> recentSearches;
  final ValueChanged<String> onRecentTap;

  bool _matches(String haystack) => query.isEmpty || haystack.toLowerCase().contains(query.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    if (query.isEmpty && category == SearchCategory.all) {
      return _SearchEmptyState(recentSearches: recentSearches, onRecentTap: onRecentTap);
    }

    final matchedIncidents = category == SearchCategory.all || category == SearchCategory.incidents
        ? incidents.where((i) => _matches('${i.type} ${i.summarySnippet}')).toList()
        : <ReportSummary>[];
    final matchedContacts = category == SearchCategory.all || category == SearchCategory.contacts
        ? contacts.where((c) => _matches('${c.name} ${c.relationship}')).toList()
        : <Contact>[];
    final matchedDevices = category == SearchCategory.all || category == SearchCategory.devices
        ? devices.where((d) => _matches(d.name)).toList()
        : <DeviceDetail>[];
    final matchedSettings = category == SearchCategory.all || category == SearchCategory.settings
        ? searchableSettings.where((s) => _matches('${s.label} ${s.description}')).toList()
        : <SearchableSetting>[];

    if (matchedIncidents.isEmpty && matchedContacts.isEmpty && matchedDevices.isEmpty && matchedSettings.isEmpty) {
      return SaEmptyState(
        title: 'No results',
        body: query.isEmpty ? 'Nothing in this category yet.' : 'Nothing matched "$query". Try a different term.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenMarginPhone,
        0,
        AppSpacing.screenMarginPhone,
        AppSpacing.space6,
      ),
      children: [
        if (matchedIncidents.isNotEmpty) ...[
          Text('Incidents', style: AppTypography.headingS.copyWith(color: onSurface)),
          const SizedBox(height: AppSpacing.space2),
          for (final incident in matchedIncidents) ...[
            SaIncidentCard(
              date: incident.date,
              type: incident.type,
              level: incident.level,
              summarySnippet: incident.summarySnippet,
              onTap: () => context.go('/reports/${incident.id}'),
            ),
            const SizedBox(height: AppSpacing.space3),
          ],
          const SizedBox(height: AppSpacing.space3),
        ],
        if (matchedContacts.isNotEmpty) ...[
          Text('Contacts', style: AppTypography.headingS.copyWith(color: onSurface)),
          const SizedBox(height: AppSpacing.space2),
          for (final contact in matchedContacts) ...[
            SaContactCard(
              name: contact.name,
              relationship: contact.relationship,
              priority: contact.priority,
              confirmed: contact.confirmed,
              onTap: () => context.go('/settings/contacts'),
            ),
            const SizedBox(height: AppSpacing.space3),
          ],
          const SizedBox(height: AppSpacing.space3),
        ],
        if (matchedDevices.isNotEmpty) ...[
          Text('Devices', style: AppTypography.headingS.copyWith(color: onSurface)),
          const SizedBox(height: AppSpacing.space2),
          for (final device in matchedDevices) ...[
            SizedBox(
              width: double.infinity,
              child: SaDeviceCard(
                name: device.name,
                batteryPercent: device.batteryPercent,
                signalStrength: device.signalStrength,
                isOnline: device.isOnline,
                width: double.infinity,
                onTap: () => context.go('/devices/${device.id}'),
              ),
            ),
            const SizedBox(height: AppSpacing.space3),
          ],
          const SizedBox(height: AppSpacing.space3),
        ],
        if (matchedSettings.isNotEmpty) ...[
          Text('Settings', style: AppTypography.headingS.copyWith(color: onSurface)),
          const SizedBox(height: AppSpacing.space2),
          for (final setting in matchedSettings) ...[
            SaCard(
              semanticsLabel: setting.label,
              onTap: () => context.go(setting.route),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(setting.label, style: AppTypography.bodyL.copyWith(color: onSurface)),
                        Text(
                          setting.description,
                          style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.5)),
                        ),
                      ],
                    ),
                  ),
                  SaIcon(SaIconGlyph.chevronRight, size: 18, color: onSurface.withValues(alpha: 0.4)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.space3),
          ],
        ],
      ],
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({required this.recentSearches, required this.onRecentTap});

  final List<String> recentSearches;
  final ValueChanged<String> onRecentTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone, vertical: AppSpacing.space4),
      children: [
        if (recentSearches.isNotEmpty) ...[
          Text('Recent Searches', style: AppTypography.headingS.copyWith(color: onSurface)),
          const SizedBox(height: AppSpacing.space3),
          Wrap(
            spacing: AppSpacing.space2,
            runSpacing: AppSpacing.space2,
            children: [
              for (final term in recentSearches) _RecentSearchChip(term: term, onTap: () => onRecentTap(term)),
            ],
          ),
          const SizedBox(height: AppSpacing.space6),
        ],
        Text('Quick Access', style: AppTypography.headingS.copyWith(color: onSurface)),
        const SizedBox(height: AppSpacing.space3),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: AppSpacing.space3,
          crossAxisSpacing: AppSpacing.space3,
          childAspectRatio: 1.6,
          children: [
            _QuickAccessCard(
              icon: SaIconGlyph.monitorPulse,
              label: 'Reports',
              onTap: () => context.go('/reports'),
            ),
            _QuickAccessCard(
              icon: SaIconGlyph.profile,
              label: 'Contacts',
              onTap: () => context.go('/settings/contacts'),
            ),
            _QuickAccessCard(icon: SaIconGlyph.ring, label: 'Devices', onTap: () => context.go('/devices')),
            _QuickAccessCard(icon: SaIconGlyph.shield, label: 'Settings', onTap: () => context.go('/settings')),
          ],
        ),
      ],
    );
  }
}

class _RecentSearchChip extends StatelessWidget {
  const _RecentSearchChip({required this.term, required this.onTap});

  final String term;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: true,
      label: 'Recent search: $term',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space2),
          decoration: BoxDecoration(
            color: saColors.surfaceElevated,
            borderRadius: AppRadius.fullRadius,
            border: Border.all(color: saColors.glassBorder),
          ),
          child: Text(term, style: AppTypography.labelM.copyWith(color: onSurface.withValues(alpha: 0.8))),
        ),
      ),
    );
  }
}

class _QuickAccessCard extends StatelessWidget {
  const _QuickAccessCard({required this.icon, required this.label, required this.onTap});

  final SaIconGlyph icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SaCard(
      onTap: onTap,
      semanticsLabel: label,
      useBlur: false,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SaIcon(icon, size: 24, color: AppColors.violet500),
          const SizedBox(height: AppSpacing.space2),
          Text(label, style: AppTypography.bodyL.copyWith(color: onSurface)),
        ],
      ),
    );
  }
}

class _SearchLoading extends StatelessWidget {
  const _SearchLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
      children: [
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.space3),
            child: SaLoadingShimmer(
              child: Container(height: 76, decoration: BoxDecoration(borderRadius: AppRadius.lgRadius, color: Colors.white)),
            ),
          ),
      ],
    );
  }
}
