import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// Which document to show. The asset and the version travel together so a
/// screen can never display one while reporting the other.
enum LegalDocument {
  terms('Terms & Conditions', 'assets/legal/terms.md', AppConfig.termsVersion),
  privacy('Privacy Policy', 'assets/legal/privacy.md', AppConfig.privacyVersion);

  const LegalDocument(this.title, this.asset, this.version);

  final String title;
  final String asset;
  final String version;
}

/// Shows a bundled legal document.
///
/// **Bundled rather than fetched**, for the same reason the models are: this
/// has to be readable before an account exists — which is before there is a
/// session, and possibly with no network at all. A consent screen that cannot
/// show what is being consented to is not a consent screen.
///
/// Rendered as plain text rather than parsed markdown. A markdown package
/// would be a dependency added for formatting on two screens, and the
/// documents are written to read acceptably either way; the `#` and `**` that
/// survive are a fair trade for not shipping a renderer. The headings are
/// given weight below so the structure is still legible.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({required this.document, this.load, super.key});

  final LegalDocument document;

  /// How to fetch the document's text. Defaults to the asset bundle.
  ///
  /// Injectable because `rootBundle` does real file I/O, and a widget test
  /// runs under fake async where real I/O never completes -- the future simply
  /// hangs until the test times out. Passing a loader keeps this screen
  /// testable, and makes the failure branch below reachable by a test at all,
  /// which it otherwise would not be.
  final Future<String> Function(String asset)? load;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(
        title: Text(document.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.space2),
            child: Text(
              'Version ${document.version}',
              style: AppTypography.bodyS.copyWith(
                color: onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: (load ?? rootBundle.loadString)(document.asset),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              // A missing asset is a build fault, not something to hide: the
              // user is being asked to agree to this, so saying "it did not
              // load" is the only honest option.
              return _Message(
                text: 'This document could not be loaded. Please update the '
                    'app, or read it at the link in Settings.',
                onSurface: onSurface,
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.space4),
                child: SelectableText.rich(
                  TextSpan(children: _spans(snapshot.data!, onSurface)),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Gives markdown headings and bold runs enough weight to stay readable
  /// without pulling in a renderer.
  List<TextSpan> _spans(String source, Color onSurface) {
    final body = AppTypography.bodyM.copyWith(color: onSurface, height: 1.5);
    final heading = AppTypography.bodyM.copyWith(
      color: onSurface,
      fontWeight: FontWeight.w700,
      height: 1.8,
    );

    return [
      for (final line in source.split('\n'))
        if (line.trimLeft().startsWith('#'))
          TextSpan(
            text: '${line.replaceAll(RegExp(r'^\s*#+\s*'), '')}\n',
            style: heading,
          )
        else
          TextSpan(text: '${line.replaceAll('**', '')}\n', style: body),
    ];
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.onSurface});

  final String text;
  final Color onSurface;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space6),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AppTypography.bodyM.copyWith(
              color: onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      );
}
