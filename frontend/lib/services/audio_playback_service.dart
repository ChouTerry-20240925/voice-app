import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';

/// Slice size used when feeding the player, so a barge-in interruption
/// never has to wait out more than one slice's worth of already-queued
/// audio (see [enqueueChunk]).
const _sliceDurationMs = 100;

/// How far ahead of real playback time we allow ourselves to queue audio
/// with the native player. Small enough to keep barge-in responsive, large
/// enough to give the native buffer a cushion against feed timing jitter.
const _maxLookahead = Duration(milliseconds: 300);

/// Streams raw PCM16 mono audio chunks (as forwarded by the backend from
/// Gemini Live) to the device speaker via flutter_sound.
///
/// The sample rate is read from each chunk's mimeType (e.g.
/// "audio/pcm;rate=24000") and the underlying player stream is (re)started
/// whenever it changes, since it isn't known until the first chunk arrives.
///
/// Chunks arrive over the network far faster than they play out. To keep
/// barge-in ([interrupt]) responsive, chunks are queued and fed to the
/// player on an internal chain, capped to [_maxLookahead] ahead of real
/// playback time via wall-clock bookkeeping, not a fixed per-slice delay.
///
/// [interrupt] is scheduled on that same chain rather than calling the
/// player directly: player calls and our own `_sampleRate` bookkeeping are
/// not safe to touch concurrently from two independent async flows — a
/// stop racing a stream restart can leave `_sampleRate` pointing at a
/// stream that was never actually (re)started, silently killing playback
/// for the rest of the call. Going through the chain keeps every player
/// interaction and state mutation in one strict order while still letting
/// the caller (the WebSocket message loop) fire-and-forget.
class AudioPlaybackService {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _isOpen = false;
  int? _sampleRate;
  int _generation = 0;
  Future<void> _chain = Future.value();

  // Wall-clock time the current player stream started, and how much audio
  // (by duration) has been fed to it since then. Reset together whenever
  // the stream (re)starts.
  DateTime? _playbackAnchor;
  Duration _queuedDuration = Duration.zero;

  Future<void> start() async {
    await _player.openPlayer();
    _isOpen = true;
    _sampleRate = null;
    _generation++;
    _chain = Future.value();
  }

  /// Queues [pcmBytes] to be fed to the player in order. Returns
  /// immediately — the caller (the WebSocket message loop) must never be
  /// blocked waiting for audio to actually finish playing, or it won't
  /// notice a barge-in interruption until whatever's currently pacing out
  /// is done.
  void enqueueChunk(Uint8List pcmBytes, String mimeType) {
    if (!_isOpen) return;
    final generation = _generation;
    _chain = _chain.then((_) async {
      try {
        await _feedSliced(generation, pcmBytes, mimeType);
      } catch (_) {
        // Player was likely stopped/closed concurrently; drop this chunk
        // rather than poisoning the rest of the chain.
      }
    });
  }

  /// Discards whatever is currently queued/playing, for barge-in: the
  /// model's response was interrupted, but more audio for the next turn
  /// will still arrive. Non-blocking, like [enqueueChunk].
  void interrupt() {
    if (!_isOpen) return;
    // Bumping this immediately (not inside the chained closure) means any
    // chunks already queued ahead of this point get dropped by
    // _feedSliced()'s generation check the moment their turn comes up,
    // without waiting for this stop to reach the front of the chain.
    _generation++;
    final generation = _generation;
    _chain = _chain.then((_) async {
      if (!_isOpen) return;
      try {
        await _player.stopPlayer();
      } catch (_) {
        // Ignore: about to reset _sampleRate regardless so the next chunk
        // retries starting the stream from scratch.
      }
      if (generation == _generation) {
        _sampleRate = null;
      }
    });
  }

  Future<void> _feedSliced(
    int generation,
    Uint8List pcmBytes,
    String mimeType,
  ) async {
    if (!_isOpen || generation != _generation) return;

    final sampleRate = _parseSampleRate(mimeType);
    if (_sampleRate != sampleRate) {
      await _player.startPlayerFromStream(
        codec: Codec.pcm16,
        interleaved: true,
        numChannels: 1,
        sampleRate: sampleRate,
        bufferSize: 8192,
      );
      // Only recorded once startPlayerFromStream has actually succeeded —
      // setting it beforehand would, if that call throws, leave later
      // chunks believing the stream is already running when it never
      // started, silently dropping them for the rest of the call.
      _sampleRate = sampleRate;
      _playbackAnchor = DateTime.now();
      _queuedDuration = Duration.zero;
    }

    // PCM16 mono: 2 bytes/sample.
    final bytesPerSlice = (sampleRate * 2 * _sliceDurationMs) ~/ 1000;
    var offset = 0;
    while (offset < pcmBytes.length) {
      if (!_isOpen || generation != _generation) return;

      final lookahead =
          _queuedDuration - DateTime.now().difference(_playbackAnchor!);
      if (lookahead > _maxLookahead) {
        await Future.delayed(lookahead - _maxLookahead);
        if (!_isOpen || generation != _generation) return;
      }

      final end = (offset + bytesPerSlice < pcmBytes.length)
          ? offset + bytesPerSlice
          : pcmBytes.length;
      final slice = pcmBytes.sublist(offset, end);
      await _player.feedUint8FromStream(slice);

      final sliceSamples = slice.length ~/ 2;
      _queuedDuration += Duration(
        microseconds: (sliceSamples * 1000000) ~/ sampleRate,
      );
      offset = end;
    }
  }

  /// Waits until audio queued so far has actually finished playing out —
  /// not just been fed to the player, which [enqueueChunk] returns well
  /// before. Callers that need to know "is the model truly done talking"
  /// (e.g. before ending the call once a report is ready) should await
  /// this rather than assuming the chain future alone means playback caught
  /// up.
  Future<void> waitUntilIdle() async {
    await _chain;
    final anchor = _playbackAnchor;
    if (anchor == null) return;
    final remaining = _queuedDuration - DateTime.now().difference(anchor);
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }
  }

  Future<void> stop() async {
    if (!_isOpen) return;
    _isOpen = false;
    _generation++;
    final future = _chain.then((_) async {
      try {
        await _player.stopPlayer();
        await _player.closePlayer();
      } catch (_) {
        // Already tearing down; nothing more to do.
      }
    });
    _chain = future;
    await future;
    _sampleRate = null;
  }

  int _parseSampleRate(String mimeType) {
    final match = RegExp(r'rate=(\d+)').firstMatch(mimeType);
    return match != null ? int.parse(match.group(1)!) : 24000;
  }
}
