import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../shared/components/cards/sa_contact_card.dart';
import '../../../shared/components/cards/sa_device_card.dart';
import '../../../shared/components/cards/sa_incident_card.dart';
import '../../../shared/components/feedback/sa_empty_state.dart';
import '../../../shared/components/feedback/sa_loading_shimmer.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/components/inputs/sa_search_bar.dart';
import '../../contacts/data/contacts_providers.dart';
import '../../contacts/domain/models/contact.dart';
import '../../devices/data/device_providers.dart';
import '../../devices/domain/models/device_detail.dart';
import '../../reports/data/reports_providers.dart';
import '../../reports/domain/models/report_summary.dart';
import '../domain/models/search_result.dart';

/// Unified search across incidents, contacts, and devices. Reads straight
/// from each feature's own shared provider (the same one Reports, Settings,
/// and Devices use) rather than a separate copy of the data, so results
/// here always match what those screens show. Filters client-side as the
/// user types, debounced by 250ms.
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

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _handleQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value.trim());
    });
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
  });

  final List<ReportSummary> incidents;
  final List<Contact> contacts;
  final List<DeviceDetail> devices;
  final String query;
  final SearchCategory category;

  bool _matches(String haystack) => query.isEmpty || haystack.toLowerCase().contains(query.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    // With no query and no category filter, prompt rather than dumping the
    // entire index — picking a specific category is still a valid way to
    // browse it with an empty query.
    if (query.isEmpty && category == SearchCategory.all) {
      return const SaEmptyState(
        title: 'Search SafeHer',
        body: 'Find past incidents, emergency contacts, and paired devices.',
      );
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

    if (matchedIncidents.isEmpty && matchedContacts.isEmpty && matchedDevices.isEmpty) {
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
        ],
      ],
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
