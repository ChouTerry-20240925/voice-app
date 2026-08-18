import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const String kBackendWsUrl = 'wss://voice-bsrs-backend.onrender.com';

/// Opens a WebSocket connection to the backend proxy and streams
/// microphone audio to it as base64-encoded 16kHz PCM chunks.
///
/// Incoming `{"type":"audio",...}` messages are decoded and handed to
/// [onAudioChunk]; `{"type":"interrupted"}` (the model was barged in on)
/// is handed to [onInterrupted]; `{"type":"turn_complete"}` (the model
/// finished its turn) is handed to [onTurnComplete]; `{"type":"tool_call",
/// "functionCalls":[...]}` is handed to [onToolCall]. All callbacks must
/// return promptly (queue/signal and return) rather than waiting for audio
/// to actually finish playing — otherwise a slow 'audio' handler would
/// delay this listener from ever seeing the messages that follow it.
///
/// Separately, local mic amplitude (not anything from the backend) drives
/// [onUserPaused]/[onUserSpeaking]: a purely client-side heuristic — Gemini
/// itself never tells us when it starts "thinking" — used only to show a
/// thinking animation while waiting for the model's response.
class VoiceSessionService {
  VoiceSessionService({
    this.onAudioChunk,
    this.onInterrupted,
    this.onTurnComplete,
    this.onToolCall,
    this.onUserPaused,
    this.onUserSpeaking,
    this.onDisconnected,
  });

  final void Function(Uint8List data, String mimeType)? onAudioChunk;
  final void Function()? onInterrupted;
  final void Function()? onTurnComplete;
  final void Function(List<dynamic> functionCalls)? onToolCall;
  final void Function()? onUserPaused;
  final void Function()? onUserSpeaking;
  // Fires if the WebSocket closes on its own (server hung up, network
  // dropped, ...) rather than via our own stop() — a safety net so callers
  // waiting on a turn_complete that will now never arrive aren't left stuck.
  final void Function()? onDisconnected;

  // Two thresholds (not one) so ambient noise sitting right at the boundary
  // can't flip the state back and forth: crossing above _speechThresholdDb
  // enters "speaking", crossing below _silenceThresholdDb (a few dB lower)
  // confirms "silence" — readings in between change nothing. This is a peak
  // dBFS reading computed straight off the outgoing PCM16 chunks (see
  // _peakDbfsOf), not the `record` plugin's own amplitude API — that API
  // turned out not to report real levels while recording via startStream()
  // on at least one tested device, which silently kept this feature from
  // ever triggering. Amplitude and noise floor vary a lot by device, so
  // these thresholds may still need retuning.
  static const double _speechThresholdDb = -30.0;
  static const double _silenceThresholdDb = -40.0;
  // Close to the backend's own silenceDurationMs (1750ms, see
  // geminiLive.js) so the thinking animation roughly tracks when Gemini
  // itself decides the user's turn ended, rather than firing on every
  // ordinary mid-sentence pause.
  static const Duration _pauseDelay = Duration(milliseconds: 1500);

  final AudioRecorder _recorder = AudioRecorder();
  WebSocketChannel? _channel;
  StreamSubscription<Uint8List>? _audioSub;
  StreamSubscription? _channelSub;
  Timer? _pauseTimer;
  bool _userSpeaking = false;
  bool _stopping = false;

  /// [mode] selects which backend system-prompt config to use for this
  /// session — `'interview'` (default) or `'qa'`.
  Future<void> start({String mode = 'interview'}) async {
    if (!await _recorder.hasPermission()) {
      throw StateError('麥克風權限被拒絕');
    }

    final uri = Uri.parse(kBackendWsUrl).replace(
      queryParameters: {'mode': mode},
    );
    _stopping = false;
    _channel = WebSocketChannel.connect(uri);
    _channelSub = _channel!.stream.listen(
      _handleIncomingMessage,
      onDone: () {
        if (!_stopping) onDisconnected?.call();
      },
      onError: (_) {},
    );

    final audioStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        // Without this, the phone's own speaker output leaks back into
        // the mic and Gemini's VAD mistakes it for the user barging in,
        // causing the model to repeatedly self-interrupt mid-sentence.
        echoCancel: true,
        autoGain: true,
        noiseSuppress: true,
      ),
    );

    _userSpeaking = false;
    _audioSub = audioStream.listen((chunk) {
      _channel?.sink.add(jsonEncode({
        'type': 'audio',
        'data': base64Encode(chunk),
        'mimeType': 'audio/pcm;rate=16000',
      }));
      _handleAmplitude(_peakDbfsOf(chunk));
    });
  }

  /// Peak dBFS of a PCM16 mono chunk: 0 is full-scale, more negative is
  /// quieter. Silent input reads as [double.negativeInfinity]-ish, clamped
  /// to a sane floor.
  double _peakDbfsOf(Uint8List pcmBytes) {
    if (pcmBytes.length < 2) return -160.0;
    final samples = ByteData.sublistView(pcmBytes);
    var peak = 0;
    for (var i = 0; i + 1 < pcmBytes.length; i += 2) {
      final sample = samples.getInt16(i, Endian.little).abs();
      if (sample > peak) peak = sample;
    }
    if (peak == 0) return -160.0;
    return 20 * math.log(peak / 32768) / math.ln10;
  }

  void _handleAmplitude(double level) {
    if (level > _speechThresholdDb) {
      _pauseTimer?.cancel();
      _pauseTimer = null;
      if (!_userSpeaking) {
        _userSpeaking = true;
        onUserSpeaking?.call();
      }
      return;
    }

    if (level > _silenceThresholdDb) {
      // Dead zone between the two thresholds — don't start or reset the
      // pause countdown on a reading that isn't clearly one or the other.
      return;
    }

    if (_userSpeaking && _pauseTimer == null) {
      _pauseTimer = Timer(_pauseDelay, () {
        _pauseTimer = null;
        _userSpeaking = false;
        onUserPaused?.call();
      });
    }
  }

  void _handleIncomingMessage(dynamic raw) {
    if (raw is! String) return;
    final message = jsonDecode(raw);
    if (message is! Map) return;

    switch (message['type']) {
      case 'audio':
        final data = message['data'];
        final mimeType = message['mimeType'];
        if (data is! String || mimeType is! String) return;
        onAudioChunk?.call(base64Decode(data), mimeType);
      case 'interrupted':
        onInterrupted?.call();
      case 'turn_complete':
        onTurnComplete?.call();
      case 'tool_call':
        final functionCalls = message['functionCalls'];
        if (functionCalls is! List) return;
        onToolCall?.call(functionCalls);
    }
  }

  Future<void> stop() async {
    _stopping = true;
    await _audioSub?.cancel();
    _audioSub = null;
    _pauseTimer?.cancel();
    _pauseTimer = null;
    _userSpeaking = false;
    await _recorder.stop();

    await _channelSub?.cancel();
    _channelSub = null;
    await _channel?.sink.close();
    _channel = null;
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }
}
