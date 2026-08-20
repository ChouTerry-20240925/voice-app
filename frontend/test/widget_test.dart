import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:voice_bsrs_app/main.dart';
import 'package:voice_bsrs_app/services/webview_voice_bridge.dart';

/// [WebviewVoiceBridge] talks to a real WebView platform (getUserMedia,
/// WebSocket, JS bridge) that doesn't exist in a plain `flutter test` run —
/// unlike a MethodChannel, there's no simple mock hook for it (see
/// InAppWebViewPlatform.instance). HomeScreen accepts an injected bridge
/// (see `voiceBridge` param) specifically so these tests can swap in this
/// fake instead of needing the real WebView machinery.
class _FakeVoiceBridge extends WebviewVoiceBridge {
  _FakeVoiceBridge({this.startError});

  /// If set, start() throws this instead of succeeding — simulates mic
  /// permission denied / connection failure.
  final Object? startError;

  @override
  Widget buildHiddenWebView() => const SizedBox.shrink();

  @override
  Future<void> start({String mode = 'interview'}) async {
    if (startError != null) throw startError!;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> waitUntilIdle() async {}
}

void main() {
  testWidgets('HomeScreen shows start button by default', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(voiceBridge: _FakeVoiceBridge())),
    );

    expect(find.text('開始問答'), findsOneWidget);
    expect(find.text('結束通話'), findsNothing);
  });

  testWidgets(
    'HomeScreen shows an error and stays idle when mic permission is denied',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            voiceBridge: _FakeVoiceBridge(
              startError: StateError('麥克風權限被拒絕'),
            ),
          ),
        ),
      );

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
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(voiceBridge: _FakeVoiceBridge())),
    );

    expect(find.byIcon(Icons.psychology_alt_outlined), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
  });
}
