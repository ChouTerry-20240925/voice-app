import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:voice_bsrs_app/main.dart';

// The `record` plugin talks to platform code over this MethodChannel. There
// is no real platform implementation available in widget tests, so it must
// be mocked, otherwise AudioRecorder's constructor fires an unawaited
// platform call that throws MissingPluginException as an uncaught async
// error unrelated to whatever the test is doing.
const _recordChannel = MethodChannel('com.llfbandit.record/messages');

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_recordChannel, (call) async {
      switch (call.method) {
        case 'hasPermission':
          return false; // simulate the user denying mic permission
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_recordChannel, null);
  });

  testWidgets('HomeScreen shows start button by default', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const VoiceBsrsApp());

    expect(find.text('開始問答'), findsOneWidget);
    expect(find.text('結束通話'), findsNothing);
  });

  testWidgets(
    'HomeScreen shows an error and stays idle when mic permission is denied',
    (WidgetTester tester) async {
      await tester.pumpWidget(const VoiceBsrsApp());

      await tester.tap(find.text('開始問答'));
      await tester.pump(); // let the failing start() call complete
      await tester.pump(); // let the SnackBar animate in

      expect(find.text('開始問答'), findsOneWidget);
      expect(find.text('結束通話'), findsNothing);
      expect(find.textContaining('無法開始通話'), findsOneWidget);
    },
  );

  testWidgets('HomeScreen shows the three mode buttons', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const VoiceBsrsApp());

    expect(find.byIcon(Icons.psychology_alt_outlined), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
  });
}
