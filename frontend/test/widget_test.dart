import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:voice_bsrs_app/main.dart';

void main() {
  testWidgets('HomeScreen shows start button and toggles to end call', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const VoiceBsrsApp());

    expect(find.text('開始問答'), findsOneWidget);
    expect(find.text('結束通話'), findsNothing);

    await tester.tap(find.text('開始問答'));
    await tester.pump();

    expect(find.text('開始問答'), findsNothing);
    expect(find.text('結束通話'), findsOneWidget);
  });

  testWidgets('HomeScreen shows the three mode buttons', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const VoiceBsrsApp());

    expect(find.byIcon(Icons.psychology_alt_outlined), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
  });
}
