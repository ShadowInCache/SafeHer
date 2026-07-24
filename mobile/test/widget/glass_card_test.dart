import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/app/shared/widgets/glass_card.dart';

void main() {
  testWidgets('GlassCard renders child and handles tap', (
    WidgetTester tester,
  ) async {
    var tapped = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GlassCard(
            onTap: () {
              tapped++;
            },
            child: const Text('Safe zone'),
          ),
        ),
      ),
    );

    expect(find.text('Safe zone'), findsOneWidget);

    await tester.tap(find.text('Safe zone'));
    await tester.pump();

    expect(tapped, 1);
  });
}
