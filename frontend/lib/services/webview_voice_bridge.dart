import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:record/record.dart';

/// Replaces [VoiceSessionService] + [AudioPlaybackService]: mic capture,
/// echo-cancelled playback, and the WebSocket link to the backend all run
/// inside a hidden WebView (assets/voice_webview/index.html) instead of via
/// native plugins, because the browser's own audio pipeline is what
/// actually gives its echoCancellation a reference signal — see
/// prototypes/webview-audio-poc/ for the standalone validation of this.
///
/// [buildHiddenWebView] must stay mounted in the widget tree for the
/// lifetime of the call UI (its JS state — the WebSocket, audio contexts —
/// doesn't survive the page being recreated), sized near-zero since it has
/// no visible UI of its own.
class WebviewVoiceBridge {
  WebviewVoiceBridge({
    this.onSpeaking,
    this.onInterrupted,
    this.onTurnComplete,
    this.onToolCall,
    this.onUserPaused,
    this.onUserSpeaking,
    this.onDisconnected,
  });

  /// Fires once per AI turn, the moment its first audio chunk starts
  /// playing — drives the "speaking" avatar state (mirrors what
  /// VoiceSessionService's onAudioChunk used to trigger on every chunk).
  final void Function()? onSpeaking;
  final void Function()? onInterrupted;
  final void Function()? onTurnComplete;
  final void Function(List<dynamic> functionCalls)? onToolCall;
  final void Function()? onUserPaused;
  final void Function()? onUserSpeaking;
  final void Function()? onDisconnected;

  InAppWebViewController? _controller;
  final Completer<void> _pageReady = Completer<void>();
  Completer<void>? _startCompleter;
  Completer<void>? _idleCompleter;

  Widget buildHiddenWebView() {
    return SizedBox(
      width: 1,
      height: 1,
      child: InAppWebView(
        initialFile: 'assets/voice_webview/index.html',
        initialSettings: InAppWebViewSettings(
          mediaPlaybackRequiresUserGesture: false,
        ),
        onWebViewCreated: (controller) {
          _controller = controller;
          controller.addJavaScriptHandler(
            handlerName: 'onEvent',
            callback: _handleEvent,
          );
        },
        onLoadStop: (controller, url) {
          if (!_pageReady.isCompleted) _pageReady.complete();
        },
        onPermissionRequest: (controller, request) async {
          return PermissionResponse(
            resources: request.resources,
            action: PermissionResponseAction.GRANT,
          );
        },
      ),
    );
  }

  dynamic _handleEvent(List<dynamic> arguments) {
    if (arguments.isEmpty) return null;
    final event = arguments[0];
    if (event is! Map) return null;

    switch (event['type']) {
      case 'connected':
        _startCompleter?.complete();
        _startCompleter = null;
      case 'connect_error':
        _startCompleter?.completeError(
          StateError(event['message']?.toString() ?? '無法開始通話'),
        );
        _startCompleter = null;
      case 'playback_idle':
        _idleCompleter?.complete();
        _idleCompleter = null;
      case 'disconnected':
        onDisconnected?.call();
      case 'interrupted':
        onInterrupted?.call();
      case 'turn_complete':
        onTurnComplete?.call();
      case 'speaking':
        onSpeaking?.call();
      case 'tool_call':
        final functionCalls = event['functionCalls'];
        if (functionCalls is List) onToolCall?.call(functionCalls);
      case 'user_speaking':
        onUserSpeaking?.call();
      case 'user_paused':
        onUserPaused?.call();
    }
    return null;
  }

  /// [mode] selects which backend system-prompt config to use for this
  /// session — `'interview'` (default) or `'qa'`. Throws if mic permission
  /// is denied or the connection fails.
  Future<void> start({String mode = 'interview'}) async {
    // The WebView's onPermissionRequest (below) only grants the in-page JS
    // getUserMedia call — it does not itself trigger Android's OS-level
    // RECORD_AUDIO runtime permission dialog for the app process. Without
    // this, Chromium fails with "Unable to select communication device!"
    // even though the WebView-side permission was granted. Reuses the
    // `record` plugin purely for its permission-request side effect (no
    // actual recording happens through it) since its Android/iOS native
    // code is already known to build cleanly in this project.
    final permissionProbe = AudioRecorder();
    final hasPermission = await permissionProbe.hasPermission();
    await permissionProbe.dispose();
    if (!hasPermission) {
      throw StateError('麥克風權限被拒絕');
    }
    await _pageReady.future;
    _startCompleter = Completer<void>();
    await _controller!.evaluateJavascript(source: "startCall('$mode');");
    await _startCompleter!.future;
  }

  Future<void> stop() async {
    await _controller?.evaluateJavascript(source: 'endCall();');
  }

  /// Waits for any already-queued audio (e.g. a closing remark whose
  /// messages have all arrived per turn_complete, but whose playback is
  /// still catching up) to actually finish playing.
  Future<void> waitUntilIdle() async {
    final alreadyIdle = await _controller?.evaluateJavascript(
      source: 'isPlaybackIdle();',
    );
    if (alreadyIdle == true) return;
    _idleCompleter = Completer<void>();
    await _idleCompleter!.future;
  }
}
