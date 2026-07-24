import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:safeher_app/app/shared/widgets/offline_banner.dart';
import 'package:safeher_app/app/shared/widgets/risk_gauge.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('smoke flow renders threat score and offline state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OfflineBanner(offline: true),
              SizedBox(height: 16),
              RiskGauge(score: 78),
            ],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle(const Duration(milliseconds: 900));

    expect(
      find.text('Offline mode: data is being cached securely'),
      findsOneWidget,
    );
    expect(find.text('78'), findsOneWidget);
    expect(find.text('Threat Score'), findsOneWidget);
  });
}
