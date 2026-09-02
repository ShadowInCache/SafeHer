import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/buttons/sa_button.dart';
import '../../../../shared/components/icons/sa_icon.dart';
import '../../../../shared/components/overlays/sa_bottom_sheet.dart';
import '../../data/glasses_pairing_controller.dart';

/// Pairs the SafeHer camera by network address.
///
/// Not BLE. The glasses stream video over WiFi, so what has to be stored is an
/// address, not a peripheral id — which is why this is a separate flow from
/// `showBlePairingSheet` rather than another branch inside it.
Future<void> showGlassesPairingSheet(BuildContext context) {
  return showSaBottomSheet<void>(
    context,
    builder: (ctx) => const GlassesPairingSheetContent(),
  );
}

/// Public so widget tests can pump it directly instead of driving a modal.
class GlassesPairingSheetContent extends ConsumerStatefulWidget {
  const GlassesPairingSheetContent({super.key});

  @override
  ConsumerState<GlassesPairingSheetContent> createState() =>
      _GlassesPairingSheetContentState();
}

class _GlassesPairingSheetContentState
    extends ConsumerState<GlassesPairingSheetContent> {
  late final TextEditingController _host;

  @override
  void initState() {
    super.initState();
    final saved = ref.read(glassesPairingProvider).host;
    _host = TextEditingController(
      text: saved.isEmpty ? GlassesPairing.defaultHost : saved,
    );
  }

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    final paired =
        await ref.read(glassesPairingProvider.notifier).pair(_host.text);
    if (paired && mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(glassesPairingProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Connect your camera',
              style: AppTypography.headingL.copyWith(color: onSurface)),
        ),
        const SizedBox(height: AppSpacing.space2),
        Text(
          'Your SafeHer glasses send video to this phone over WiFi. Put both on '
          'the same network, then connect.',
          style:
              AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: AppSpacing.space5),

        TextField(
          controller: _host,
          enabled: !state.isTesting,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _pair(),
          style: AppTypography.bodyM.copyWith(color: onSurface),
          decoration: InputDecoration(
            labelText: 'Camera address',
            helperText: 'Usually ${GlassesPairing.defaultHost}',
            helperMaxLines: 2,
            border: OutlineInputBorder(borderRadius: AppRadius.lgRadius),
            prefixIcon: const Padding(
              padding: EdgeInsets.all(AppSpacing.space3),
              child: SaIcon(SaIconGlyph.glasses, size: 18),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space4),

        if (state.error != null) ...[
          _Banner(
            colour: AppColors.warning500,
            icon: SaIconGlyph.close,
            title: state.error!,
            // Every likely cause, because the user cannot see which one it is
            // and the address itself is rarely the problem.
            detail: 'Check the camera is switched on, that this phone is on the '
                'same WiFi, and that the address is right.',
          ),
          const SizedBox(height: AppSpacing.space4),
        ],

        if (state.stage == GlassesPairingStage.reachable && state.isPaired) ...[
          _Banner(
            colour: AppColors.success500,
            icon: SaIconGlyph.check,
            title: 'Connected to ${state.host}',
            detail: [
              if (state.firmware != null) 'Firmware ${state.firmware}',
              if (state.battery != null) 'Battery ${state.battery}%',
            ].join('  ·  '),
          ),
          const SizedBox(height: AppSpacing.space4),
        ],

        SaButton(
          label: state.isTesting ? 'Connecting…' : 'Connect',
          onPressed: state.isTesting ? null : _pair,
          isLoading: state.isTesting,
          fullWidth: true,
        ),

        if (state.isPaired) ...[
          const SizedBox(height: AppSpacing.space2),
          TextButton(
            onPressed: state.isTesting
                ? null
                : () async {
                    await ref.read(glassesPairingProvider.notifier).unpair();
                    if (context.mounted) Navigator.of(context).maybePop();
                  },
            child: Text('Forget this camera',
                style: AppTypography.labelL
                    .copyWith(color: onSurface.withValues(alpha: 0.7))),
          ),
        ],

        const SizedBox(height: AppSpacing.space3),
        // Said plainly, because it is the reason someone would agree to this.
        Text(
          'Video is scanned on this phone and never uploaded. Only the result — '
          'whether a weapon was seen — is sent.',
          style: AppTypography.bodyS
              .copyWith(color: onSurface.withValues(alpha: 0.6)),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.colour,
    required this.icon,
    required this.title,
    this.detail,
  });

  final Color colour;
  final SaIconGlyph icon;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.space3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.10),
        borderRadius: AppRadius.lgRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaIcon(icon, size: 18, color: colour),
          const SizedBox(width: AppSpacing.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTypography.labelM.copyWith(color: onSurface)),
                if (detail != null && detail!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.space1),
                  Text(detail!,
                      style: AppTypography.bodyS
                          .copyWith(color: onSurface.withValues(alpha: 0.7))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
