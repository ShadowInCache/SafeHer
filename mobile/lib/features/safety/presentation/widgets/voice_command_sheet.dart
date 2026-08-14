import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/voice/voice_command.dart';
import '../../../../core/voice/voice_command_service.dart';
import '../../../../shared/components/buttons/sa_button.dart';
import '../../../../shared/components/icons/sa_icon.dart';

/// Listens for one spoken command and hands the match back to the caller.
///
/// The sheet never performs the action itself — it returns the recognised
/// [VoiceCommand] so the caller applies the same confirmation rules as any
/// other entry point (SOS still opens a countdown; cancelling still meets the
/// PIN gate). Speech is matched on-device and the transcript is discarded
/// when this sheet closes.
class VoiceCommandSheet extends ConsumerStatefulWidget {
  const VoiceCommandSheet({super.key, this.service});

  /// Injectable for tests — production uses a real recogniser.
  final VoiceCommandService? service;

  @override
  ConsumerState<VoiceCommandSheet> createState() => _VoiceCommandSheetState();
}

class _VoiceCommandSheetState extends ConsumerState<VoiceCommandSheet> {
  late final VoiceCommandService _service = widget.service ?? VoiceCommandService();

  _VoiceState _state = const _VoiceIdle();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
  }

  @override
  void dispose() {
    _service.stop();
    super.dispose();
  }

  Future<void> _listen() async {
    setState(() => _state = const _VoiceListening());
    final result = await _service.listenOnce();
    if (!mounted) return;

    if (result.isUnavailable) {
      setState(() => _state = const _VoiceUnavailable());
      return;
    }
    if (result.command != null) {
      Navigator.of(context).pop(result.command);
      return;
    }
    setState(() => _state = _VoiceNoMatch(result.transcript));
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenMarginPhone,
        vertical: AppSpacing.space5,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.violet500.withValues(
                  alpha: _state is _VoiceListening ? 0.22 : 0.1,
                ),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: SaIcon(SaIconGlyph.mic, size: 32, color: AppColors.violet500),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space4),
          Text(
            switch (_state) {
              _VoiceListening() => 'Listening…',
              _VoiceUnavailable() => 'Microphone unavailable',
              _VoiceNoMatch() => "Didn't catch a command",
              _VoiceIdle() => 'Ready',
            },
            style: AppTypography.headingS.copyWith(color: onSurface),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            switch (_state) {
              _VoiceListening() => 'Say something like "start SOS" or "find help nearby".',
              _VoiceUnavailable() =>
                'Grant microphone access in system settings to use voice commands.',
              _VoiceNoMatch(:final transcript) => transcript == null || transcript.isEmpty
                  ? 'Nothing was heard. Try again, a little closer to the mic.'
                  : 'Heard "$transcript", which isn\'t one of the commands.',
              _VoiceIdle() => '',
            },
            style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.65)),
            textAlign: TextAlign.center,
          ),
          if (_state is _VoiceNoMatch) ...[
            const SizedBox(height: AppSpacing.space4),
            for (final command in VoiceCommand.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  command.spokenExample,
                  style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.5)),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.space5),
          if (_state is! _VoiceListening)
            SaButton(label: 'Try again', onPressed: _listen, fullWidth: true),
          const SizedBox(height: AppSpacing.space2),
          SaButton(
            label: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            variant: SaButtonVariant.secondary,
            fullWidth: true,
          ),
        ],
      ),
    );
  }
}

sealed class _VoiceState {
  const _VoiceState();
}

class _VoiceIdle extends _VoiceState {
  const _VoiceIdle();
}

class _VoiceListening extends _VoiceState {
  const _VoiceListening();
}

class _VoiceUnavailable extends _VoiceState {
  const _VoiceUnavailable();
}

class _VoiceNoMatch extends _VoiceState {
  const _VoiceNoMatch(this.transcript);
  final String? transcript;
}
