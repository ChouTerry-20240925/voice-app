import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';

/// Streams raw PCM16 mono audio chunks (as forwarded by the backend from
/// Gemini Live) to the device speaker via flutter_sound.
///
/// The sample rate is read from each chunk's mimeType (e.g.
/// "audio/pcm;rate=24000") and the underlying player stream is (re)started
/// whenever it changes, since it isn't known until the first chunk arrives.
class AudioPlaybackService {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _isOpen = false;
  int? _sampleRate;

  Future<void> start() async {
    await _player.openPlayer();
    _isOpen = true;
    _sampleRate = null;
  }

  Future<void> playChunk(Uint8List pcmBytes, String mimeType) async {
    if (!_isOpen) return;

    final sampleRate = _parseSampleRate(mimeType);
    if (_sampleRate != sampleRate) {
      _sampleRate = sampleRate;
      await _player.startPlayerFromStream(
        codec: Codec.pcm16,
        interleaved: true,
        numChannels: 1,
        sampleRate: sampleRate,
        bufferSize: 8192,
      );
    }

    await _player.feedUint8FromStream(pcmBytes);
  }

  /// Stops and discards whatever is currently queued/playing without
  /// closing the player session, for barge-in: the model's response was
  /// interrupted, but more audio for the next turn will still arrive.
  Future<void> stopCurrentPlayback() async {
    if (!_isOpen) return;
    await _player.stopPlayer();
    // Forces the next playChunk() to call startPlayerFromStream() again,
    // since stopPlayer() tears down the underlying playback stream.
    _sampleRate = null;
  }

  Future<void> stop() async {
    if (!_isOpen) return;
    _isOpen = false;
    _sampleRate = null;
    await _player.stopPlayer();
    await _player.closePlayer();
  }

  int _parseSampleRate(String mimeType) {
    final match = RegExp(r'rate=(\d+)').firstMatch(mimeType);
    return match != null ? int.parse(match.group(1)!) : 24000;
  }
}
