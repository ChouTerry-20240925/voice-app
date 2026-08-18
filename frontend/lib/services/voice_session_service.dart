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
/// is handed to [onInterrupted]. `turn_complete`/`tool_call` are not
/// handled yet — that's Phase 4.
class VoiceSessionService {
  VoiceSessionService({this.onAudioChunk, this.onInterrupted});

  final Future<void> Function(Uint8List data, String mimeType)? onAudioChunk;
  final Future<void> Function()? onInterrupted;

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
      // Pause delivery of the next message until this one (including
      // handing its audio off to the player) is fully processed, so
      // concurrent chunks never race on the native audio track.
      (raw) {
        _channelSub?.pause(_handleIncomingMessage(raw));
      },
      onError: (_) {},
    );

    final audioStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
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

  Future<void> _handleIncomingMessage(dynamic raw) async {
    if (raw is! String) return;
    final message = jsonDecode(raw);
    if (message is! Map) return;

    switch (message['type']) {
      case 'audio':
        final data = message['data'];
        final mimeType = message['mimeType'];
        if (data is! String || mimeType is! String) return;
        await onAudioChunk?.call(base64Decode(data), mimeType);
      case 'interrupted':
        await onInterrupted?.call();
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
