import 'package:flutter/material.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../shared/components/charts/sa_waveform.dart';
import '../../../../shared/components/feedback/sa_empty_state.dart';
import '../../../../shared/components/icons/sa_icon.dart';
import '../../domain/models/evidence_item.dart';

/// Horizontal gallery of captured evidence — video/audio/photo tiles, each
/// opening a full player/viewer on tap. Real URLs render real media; empty
/// URLs (the mock fixture data, or a report whose upload hasn't finished)
/// show a clearly-labeled "not available yet" state instead of pretending
/// to play something that doesn't exist.
class ReportEvidenceGallery extends StatelessWidget {
  const ReportEvidenceGallery({required this.items, super.key});

  final List<EvidenceItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.space3),
        itemBuilder: (context, index) => _EvidenceTile(item: items[index]),
      ),
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  const _EvidenceTile({required this.item});

  final EvidenceItem item;

  void _open(BuildContext context) {
    switch (item.type) {
      case EvidenceType.video:
      case EvidenceType.audio:
        showModalBottomSheet<void>(
          context: context,
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          builder: (context) => _EvidencePlayerSheet(item: item),
        );
      case EvidenceType.photo:
        Navigator.of(context).push(
          PageRouteBuilder<void>(
            opaque: false,
            barrierColor: Colors.black87,
            pageBuilder: (context, animation, secondaryAnimation) => _PhotoViewer(item: item),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    final semanticLabel = switch (item.type) {
      EvidenceType.video => 'Video evidence, ${item.durationLabel ?? "unknown duration"}',
      EvidenceType.audio => 'Audio evidence',
      EvidenceType.photo => 'Photo evidence',
    };
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        onTap: () => _open(context),
        child: Container(
          width: 120,
          decoration: BoxDecoration(
            color: saColors.surfaceElevated,
            borderRadius: AppRadius.lgRadius,
            border: Border.all(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (item.type == EvidenceType.audio)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.space2),
                  child: SaWaveform(amplitudes: [0.2, 0.5, 0.8, 0.4, 0.6, 0.3, 0.7, 0.5, 0.2, 0.4]),
                )
              else
                SaIcon(
                  item.type == EvidenceType.video ? SaIconGlyph.camera : SaIconGlyph.eye,
                  size: 28,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              if (item.type == EvidenceType.video)
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.5)),
                  child: const Center(child: SaIcon(SaIconGlyph.play, color: Colors.white, size: 16)),
                ),
              if (item.durationLabel != null)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Text(
                    item.durationLabel!,
                    style: AppTypography.labelM.copyWith(color: Colors.white, shadows: const [Shadow(blurRadius: 4)]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EvidencePlayerSheet extends StatelessWidget {
  const _EvidencePlayerSheet({required this.item});

  final EvidenceItem item;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.type == EvidenceType.video ? 'Video evidence' : 'Audio evidence',
              style: AppTypography.headingM.copyWith(color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: AppSpacing.space4),
            if (item.url.isEmpty)
              const SaEmptyState(
                title: 'Evidence not available',
                body: 'This clip hasn\'t finished uploading, or is only available on the full backend.',
              )
            else
              // Real playback wires here once a genuine media URL exists —
              // chewie (video) is already a dependency for exactly this.
              Text(item.url, style: AppTypography.bodyS.copyWith(color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: AppSpacing.space4),
          ],
        ),
      ),
    );
  }
}

class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({required this.item});

  final EvidenceItem item;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Hero(
            tag: 'evidence-${item.id}',
            child: item.url.isEmpty
                ? const SaEmptyState(title: 'Photo not available', body: 'This image isn\'t available in this build.')
                : Image.network(item.url, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
