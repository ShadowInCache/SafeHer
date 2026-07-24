import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/app/shared/widgets/offline_banner.dart';

void main() {
  testWidgets('OfflineBanner shows status copy when offline', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: OfflineBanner(offline: true))),
    );

    expect(
      find.text('Offline mode: data is being cached securely'),
      findsOneWidget,
    );
  });
}
