import 'dart:async';
import 'dart:convert';
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
class VoiceSessionService {
  VoiceSessionService({
    this.onAudioChunk,
    this.onInterrupted,
    this.onTurnComplete,
    this.onToolCall,
  });

  final void Function(Uint8List data, String mimeType)? onAudioChunk;
  final void Function()? onInterrupted;
  final void Function()? onTurnComplete;
  final void Function(List<dynamic> functionCalls)? onToolCall;

  final AudioRecorder _recorder = AudioRecorder();
  WebSocketChannel? _channel;
  StreamSubscription<Uint8List>? _audioSub;
  StreamSubscription? _channelSub;

  Future<void> start() async {
    if (!await _recorder.hasPermission()) {
      throw StateError('麥克風權限被拒絕');
    }

    _channel = WebSocketChannel.connect(Uri.parse(kBackendWsUrl));
    _channelSub = _channel!.stream.listen(
      _handleIncomingMessage,
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

    _audioSub = audioStream.listen((chunk) {
      _channel?.sink.add(jsonEncode({
        'type': 'audio',
        'data': base64Encode(chunk),
        'mimeType': 'audio/pcm;rate=16000',
      }));
    });
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
    await _audioSub?.cancel();
    _audioSub = null;
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
