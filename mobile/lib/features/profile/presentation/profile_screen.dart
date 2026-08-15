import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/components/buttons/sa_button.dart';
import '../../../shared/components/cards/sa_card.dart';
import '../../../shared/components/cards/sa_contact_card.dart';
import '../../../shared/components/cards/sa_stat_card.dart';
import '../../../shared/components/feedback/sa_empty_state.dart';
import '../../../shared/components/feedback/sa_loading_shimmer.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/components/inputs/sa_text_field.dart';
import '../../../shared/components/navigation/sa_bottom_nav_bar.dart';
import '../../../shared/components/overlays/sa_bottom_sheet.dart';
import '../../../shared/components/overlays/sa_toast.dart';
import '../../auth/data/auth_providers.dart';
import '../../contacts/data/contacts_providers.dart';
import '../../devices/data/device_providers.dart';
import '../data/profile_providers.dart';
import '../domain/models/user_profile.dart';
import 'widgets/profile_data_privacy_section.dart';
import 'widgets/profile_preferences_section.dart';
import 'widgets/profile_security_section.dart';

Future<void> _editName(BuildContext context, WidgetRef ref, String currentName) async {
  final newName = await showSaBottomSheet<String>(context, builder: (context) => _EditNameSheet(initialName: currentName));
  if (newName == null || newName.trim().isEmpty || !context.mounted) return;
  try {
    await ref.read(profileRepositoryProvider).updateProfile(name: newName.trim());
    ref.invalidate(userProfileProvider);
  } catch (_) {
    if (context.mounted) {
      showSaToast(context, message: "Couldn't update your name. Check your connection and try again.", type: SaToastType.error);
    }
  }
}

class _EditNameSheet extends StatefulWidget {
  const _EditNameSheet({required this.initialName});

  final String initialName;

  @override
  State<_EditNameSheet> createState() => _EditNameSheetState();
}

class _EditNameSheetState extends State<_EditNameSheet> {
  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit Name', style: AppTypography.headingM.copyWith(color: onSurface)),
          const SizedBox(height: AppSpacing.space4),
          SaTextField(label: 'Name', controller: _controller, semanticsLabel: 'Name', onChanged: (_) => setState(() {})),
          const SizedBox(height: AppSpacing.space5),
          SaButton(
            label: 'Save',
            fullWidth: true,
            onPressed: _controller.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(_controller.text.trim()),
          ),
        ],
      ),
    );
  }
}

/// Account overview — identity, headline stats, emergency contacts
/// preview, and entry points into Settings and sign-out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  void _handleTabSelected(BuildContext context, SaNavTab tab) {
    switch (tab) {
      case SaNavTab.home:
        context.go('/home');
      case SaNavTab.monitor:
        context.go('/monitor');
      case SaNavTab.dashboard:
        context.go('/dashboard');
      case SaNavTab.profile:
        return;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);

    return Scaffold(
      body: Stack(
        children: [
          profileAsync.when(
            data: (profile) => _ProfileContent(profile: profile),
            loading: () => const _ProfileLoading(),
            error: (error, stackTrace) => SafeArea(
              child: SaEmptyState(
                title: "Couldn't load your profile",
                body: 'Check your connection and try again.',
                ctaLabel: 'Retry',
                onCtaTap: () => ref.invalidate(userProfileProvider),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SaBottomNavBar(
              currentTab: SaNavTab.profile,
              onTabSelected: (tab) => _handleTabSelected(context, tab),
              onSosTap: () => context.go('/emergency'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileContent extends ConsumerWidget {
  const _ProfileContent({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final devicesAsync = ref.watch(devicesProvider);
    final contactsAsync = ref.watch(contactsNotifierProvider);
    final deviceCount = devicesAsync.valueOrNull?.length;
    final contactsPreview = contactsAsync.valueOrNull?.take(3).toList() ?? const [];

    return CustomScrollView(
      physics: const ClampingScrollPhysics(),
      slivers: [
        SliverPadding(padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone, vertical: AppSpacing.space5),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.violet500, width: 2)),
                  alignment: Alignment.center,
                  child: Text(
                    profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                    style: AppTypography.displayL.copyWith(color: onSurface),
                  ),
                ),
                const SizedBox(height: AppSpacing.space3),
                Semantics(
                  button: true,
                  label: 'Edit name',
                  child: GestureDetector(
                    onTap: () => _editName(context, ref, profile.name),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(profile.name, style: AppTypography.headingL.copyWith(color: onSurface)),
                        const SizedBox(width: AppSpacing.space2),
                        SaIcon(SaIconGlyph.chevronRight, size: 16, color: onSurface.withValues(alpha: 0.4)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.space1),
                Text(profile.email, style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.6))),
                const SizedBox(height: AppSpacing.space1),
                Text(
                  'Member since ${profile.memberSince}',
                  style: AppTypography.labelM.copyWith(color: onSurface.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: AppSpacing.space3,
              crossAxisSpacing: AppSpacing.space3,
              childAspectRatio: 0.75,
            ),
            delegate: SliverChildListDelegate([
              SaStatCard(value: profile.safetyScore != null ? '${profile.safetyScore}' : '—', label: 'Safety Score'),
              SaStatCard(value: profile.streakDays != null ? '${profile.streakDays}d' : '—', label: 'Safe Streak'),
              SaStatCard(value: deviceCount != null ? '$deviceCount' : '—', label: 'Devices'),
            ]),
          ),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space5)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Emergency Contacts',
                        style: AppTypography.headingM.copyWith(color: onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.space2),
                    Semantics(
                      button: true,
                      label: 'Manage emergency contacts',
                      child: GestureDetector(
                        onTap: () => context.go('/settings/contacts'),
                        child: Text(
                          'Manage',
                          style: AppTypography.labelL.copyWith(color: AppColors.violet500),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.space3),
                if (contactsPreview.isEmpty)
                  Text(
                    'No emergency contacts yet.',
                    style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.6)),
                  )
                else
                  for (final contact in contactsPreview) ...[
                    SaContactCard(
                      name: contact.name,
                      relationship: contact.relationship,
                      priority: contact.priority,
                      confirmed: contact.confirmed,
                      onTap: () => context.go('/settings/contacts'),
                    ),
                    const SizedBox(height: AppSpacing.space3),
                  ],
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space2)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
          sliver: SliverToBoxAdapter(child: ProfileSecuritySection(email: profile.email)),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space5)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
          sliver: const SliverToBoxAdapter(child: ProfilePreferencesSection()),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space5)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
          sliver: SliverToBoxAdapter(
            child: ProfileDataPrivacySection(
              userDataSummary:
                  '${profile.name} · ${profile.email}\n'
                  '${deviceCount ?? 0} paired device(s) · ${contactsPreview.length} emergency contact(s) shown\n'
                  'Member since ${profile.memberSince}.',
            ),
          ),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space5)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Account', style: AppTypography.headingM.copyWith(color: onSurface)),
                const SizedBox(height: AppSpacing.space3),
                SaCard(
                  onTap: () => context.go('/settings'),
                  semanticsLabel: 'Settings',
                  child: Row(
                    children: [
                      const SaIcon(SaIconGlyph.shield, size: 20, color: AppColors.violet500),
                      const SizedBox(width: AppSpacing.space3),
                      Expanded(
                        child: Text('Settings', style: AppTypography.bodyL.copyWith(color: onSurface)),
                      ),
                      SaIcon(SaIconGlyph.chevronRight, size: 18, color: onSurface.withValues(alpha: 0.4)),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.space4),
                SaButton(
                  label: 'Sign Out',
                  variant: SaButtonVariant.danger,
                  confirmRequired: true,
                  fullWidth: true,
                  onPressed: () async {
                    try {
                      await ref.read(authRepositoryProvider).signOut();
                    } catch (_) {
                      // Sign-out proceeds regardless — a failed server-side
                      // sign-out shouldn't trap the user in the app.
                    }
                    if (context.mounted) context.go('/auth/login');
                  },
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space16 + AppSpacing.space10)),
      ],
    );
  }
}

class _ProfileLoading extends StatelessWidget {
  const _ProfileLoading();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenMarginPhone),
        physics: const ClampingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: SaLoadingShimmer(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.space5),
            SaLoadingShimmer(
              child: Container(height: 90, decoration: BoxDecoration(borderRadius: AppRadius.xl2Radius, color: Colors.white)),
            ),
            const SizedBox(height: AppSpacing.space4),
            SaLoadingShimmer(
              child: Container(height: 150, decoration: BoxDecoration(borderRadius: AppRadius.xl2Radius, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
