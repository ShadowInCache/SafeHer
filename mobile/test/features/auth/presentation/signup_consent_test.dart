import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/config/app_config.dart';
import 'package:safeher_app/features/legal/presentation/legal_document_screen.dart';

/// Consent has to be an act, not a consequence.
///
/// The sign-up screen used to say "By continuing you agree to our Terms of
/// Service and Privacy Policy" over two links whose handler raised a toast
/// saying *"coming soon"*. There was nothing to read, nothing to tick, and no
/// column to record an acceptance in — while the app went on to ask for
/// location, microphone, camera and the phone numbers of the people she would
/// call for help.
///
/// Asset reads use plain `test`, never `testWidgets`: a widget test runs under
/// fake async, where `rootBundle`'s real file I/O never completes and the test
/// hangs until it times out. The rendering tests inject a loader instead, so
/// nothing in this file waits on the disk inside a pumped frame.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the documents the app claims to have shown', () {
    test('every document maps to an asset and a version', () {
      for (final document in LegalDocument.values) {
        expect(document.asset, startsWith('assets/legal/'), reason: document.name);
        expect(document.version, isNotEmpty, reason: document.name);
        expect(document.title, isNotEmpty, reason: document.name);
      }
    });

    test('the versions match what registration reports as accepted', () {
      // If these drift, the app shows one document and tells the server it
      // accepted another — and the stored consent becomes a record of what we
      // served rather than what she saw.
      expect(LegalDocument.terms.version, AppConfig.termsVersion);
      expect(LegalDocument.privacy.version, AppConfig.privacyVersion);
    });

    test('both are bundled, readable, and declare themselves unreviewed',
        () async {
      // Bundled rather than fetched: this is read *before* an account exists,
      // so there is no session and possibly no network.
      //
      // The placeholder warning is part of the contract. These were written by
      // engineers to describe what the software does; letting them quietly
      // become something that reads like legal cover would be its own false
      // claim, on the screen where a woman is agreeing to hand over her
      // location and her contacts.
      for (final document in LegalDocument.values) {
        final contents = await rootBundle.loadString(document.asset);
        expect(contents, isNotEmpty, reason: document.asset);
        expect(
          contents.toUpperCase(),
          contains('PLACEHOLDER'),
          reason: '${document.asset} must say plainly that it is not reviewed',
        );
      }
    });
  });

  group('rendering', () {
    Future<String> fake(String asset) async => '# Heading\n\nSome **body** text.';

    testWidgets('the document and its version are both shown', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: LegalDocumentScreen(document: LegalDocument.terms, load: fake),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Terms & Conditions'), findsOneWidget);
      expect(
        find.text('Version ${AppConfig.termsVersion}'),
        findsOneWidget,
        reason: 'the version is what makes the acceptance meaningful',
      );
    });

    testWidgets('the text is rendered and selectable', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: LegalDocumentScreen(document: LegalDocument.privacy, load: fake),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('a document that will not load says so', (tester) async {
      // Reachable only because the loader is injectable. The user is being
      // asked to agree to this, so "it did not load" is the only honest
      // outcome — silently showing an empty page would invite agreement to
      // nothing at all.
      await tester.pumpWidget(MaterialApp(
        home: LegalDocumentScreen(
          document: LegalDocument.terms,
          load: (_) async => throw Exception('missing asset'),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('could not be loaded'), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
    });
  });
}
