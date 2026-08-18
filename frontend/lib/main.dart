import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models/report_record.dart';
import 'screens/report_detail_screen.dart';
import 'screens/report_history_screen.dart';
import 'services/audio_playback_service.dart';
import 'services/report_store.dart';
import 'services/voice_session_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ReportStore.init();
  runApp(const VoiceBsrsApp());
}

class VoiceBsrsApp extends StatelessWidget {
  const VoiceBsrsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '語音對話心理評估',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

enum AvatarState { idle, listening, thinking, speaking }

/// Rendered by _StickFigurePainter (eyebrows + mouth curve), but every
/// state currently resolves to [neutral] — see _HomeScreenState's
/// _currentExpression. Kept as its own type so a real trigger (e.g.
/// sentiment/semantic analysis of the reply) can drive it later without
/// touching the painter.
enum AvatarExpression { neutral, joy, anger, sorrow, happy }

enum ConversationMode { interview, qa }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isCallActive = false;
  bool _isConnecting = false;
  // Only shown once connecting has taken a while — Render's free tier can
  // take 30-50s to wake from idle, and popping this up immediately would
  // make every ordinary fast connect look like something's wrong.
  bool _showColdStartHint = false;
  Timer? _coldStartHintTimer;
  AvatarState _avatarState = AvatarState.idle;
  // Defaults to interview if the user never taps a mode button, so "開始
  // 問答" keeps working standalone like before.
  ConversationMode _selectedMode = ConversationMode.interview;
  // Set by _handleToolCall once generate_report fires; the call keeps
  // running until the model's closing remark actually finishes (see
  // onTurnComplete below) so it isn't cut off mid-sentence.
  ReportRecord? _pendingReport;
  final _playback = AudioPlaybackService();
  late final _voiceSession = VoiceSessionService(
    onAudioChunk: (data, mimeType) {
      _playback.enqueueChunk(data, mimeType);
      _setAvatarState(AvatarState.speaking);
    },
    onInterrupted: () {
      _playback.interrupt();
      _setAvatarState(AvatarState.listening);
    },
    onTurnComplete: () {
      _setAvatarState(AvatarState.listening);
      if (_pendingReport != null) {
        _finishInterview();
      }
    },
    onToolCall: (functionCalls) => _handleToolCall(functionCalls),
    // Safety net for any unexpected disconnect (server hung up, network
    // dropped, ...) — don't leave the user stuck on a call that looks live
    // but isn't.
    onDisconnected: () {
      if (_pendingReport != null) {
        // turn_complete was never going to arrive now — finish up the same
        // way, just without waiting on playback that's never coming.
        _finishInterview();
      } else {
        _handleUnexpectedDisconnect();
      }
    },
    // Local mic-amplitude heuristic only (see VoiceSessionService) — guard
    // against the authoritative server states (speaking/idle) so a noisy
    // reading can't override them; true barge-in still goes through
    // onInterrupted above.
    onUserPaused: () {
      if (_avatarState == AvatarState.listening) {
        _setAvatarState(AvatarState.thinking);
      }
    },
    onUserSpeaking: () {
      if (_avatarState == AvatarState.thinking) {
        _setAvatarState(AvatarState.listening);
      }
    },
  );

  // Cycling through 喜/怒/哀/樂 by rule (e.g. one per speaking turn) was
  // tried and pulled back out — without knowing what's actually being said,
  // the expression shown has no real relationship to it, which read as
  // wrong more often than it read as lively. Stays neutral until there's a
  // real signal (e.g. semantic/sentiment analysis of the reply) to drive it.
  AvatarExpression get _currentExpression => AvatarExpression.neutral;

  void _setAvatarState(AvatarState state) {
    if (_avatarState == state) return;
    setState(() {
      _avatarState = state;
    });
  }

  @override
  void dispose() {
    _coldStartHintTimer?.cancel();
    _voiceSession.dispose();
    _playback.stop();
    super.dispose();
  }

  Future<void> _toggleCall() async {
    if (_isCallActive) {
      await _voiceSession.stop();
      await _playback.stop();
      setState(() {
        _isCallActive = false;
        _avatarState = AvatarState.idle;
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _showColdStartHint = false;
    });
    // Render's free tier can take 30-50s to wake from idle — only mention
    // that once the connection has actually taken a while, so a normal
    // fast connect never shows it.
    _coldStartHintTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _showColdStartHint = true);
    });

    try {
      // Start the mic/WebSocket session before opening the player: if mic
      // permission is denied or the connection fails, there's no point
      // spinning up playback for audio that will never arrive.
      await _voiceSession.start(
        mode: _selectedMode == ConversationMode.qa ? 'qa' : 'interview',
      );
      await _playback.start();
      _coldStartHintTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _isCallActive = true;
        // The model greets first, but audio hasn't arrived yet — this
        // flips to speaking the moment the first chunk comes in.
        _avatarState = AvatarState.listening;
      });
    } catch (e) {
      // _avatarState never left idle if we get here — start() failed
      // before the success branch's setState ran.
      _coldStartHintTimer?.cancel();
      await _voiceSession.stop();
      await _playback.stop();
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _showColdStartHint = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('無法開始通話：$e')),
      );
    }
  }

  Future<void> _handleUnexpectedDisconnect() async {
    if (!_isCallActive) return;
    await _voiceSession.stop();
    await _playback.stop();
    if (!mounted) return;
    setState(() {
      _isCallActive = false;
      _avatarState = AvatarState.idle;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('連線中斷，請重新開始通話')),
    );
  }

  Future<void> _handleToolCall(List<dynamic> functionCalls) async {
    final call = functionCalls
        .whereType<Map>()
        .cast<Map<dynamic, dynamic>>()
        .where((c) => c['name'] == 'generate_report')
        .firstOrNull;
    final args = call?['args'];
    if (args is! Map) return;

    final reportContent = args['report_content'];
    final totalScore = args['total_score'];
    final resultAnalysis = args['result_analysis'];
    if (reportContent is! String ||
        totalScore is! num ||
        resultAnalysis is! String) {
      return;
    }

    final record = ReportRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      reportContent: reportContent,
      totalScore: totalScore.toInt(),
      resultAnalysis: resultAnalysis,
    );
    // Persist right away so the report survives even if something goes
    // wrong later in the call-teardown/dialog flow below.
    await ReportStore.save(record);

    // Don't end the call yet — per the system prompt, Gemini still says a
    // closing line after calling generate_report. onTurnComplete finishes
    // things once that's actually done playing.
    _pendingReport = record;
  }

  Future<void> _finishInterview() async {
    final record = _pendingReport;
    if (record == null) return;
    _pendingReport = null;

    // Audio for the closing remark may still be queued/playing even though
    // every message for it has already arrived — wait for it to actually
    // finish rather than cutting it off.
    await _playback.waitUntilIdle();

    await _voiceSession.stop();
    await _playback.stop();
    if (!mounted) return;
    setState(() {
      _isCallActive = false;
      _avatarState = AvatarState.idle;
    });

    // No local persistence yet (that's Phase 4 Step 4 / hive) — this
    // in-memory record is the only copy, so the dialog only offers the one
    // way forward rather than a dismiss that would silently lose it.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('對話已完成'),
        content: const Text('已產生本次對話的報表。'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('查看報表詳情'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReportDetailScreen(record: record)),
    );
  }

  void _selectInterviewMode() {
    setState(() {
      _selectedMode = ConversationMode.interview;
    });
  }

  void _selectQaMode() {
    setState(() {
      _selectedMode = ConversationMode.qa;
    });
  }

  void _openReportHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ReportHistoryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Center(
                    child: _AvatarView(
                      state: _avatarState,
                      expression: _currentExpression,
                    ),
                  ),
                  Positioned(
                    right: 16,
                    top: 0,
                    bottom: 0,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ModeButton(
                          icon: Icons.psychology_alt_outlined,
                          label: '訪談模式',
                          selected: _selectedMode == ConversationMode.interview,
                          onPressed: _selectInterviewMode,
                        ),
                        const SizedBox(height: 24),
                        _ModeButton(
                          icon: Icons.chat_bubble_outline,
                          label: '專業問答模式',
                          selected: _selectedMode == ConversationMode.qa,
                          onPressed: _selectQaMode,
                        ),
                        const Spacer(),
                        _ModeButton(
                          icon: Icons.description_outlined,
                          label: '報表輸出',
                          selected: false,
                          onPressed: _openReportHistory,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  if (_isConnecting && _showColdStartHint)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        '後端可能正在喚醒中，請稍候（最長約 50 秒）',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ),
                  SizedBox(
                    width: 200,
                    height: 64,
                    child: ElevatedButton(
                      onPressed: _isConnecting ? null : _toggleCall,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isCallActive
                            ? Colors.redAccent
                            : Colors.teal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(32),
                        ),
                      ),
                      child: _isConnecting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _isCallActive ? '結束通話' : '開始問答',
                              style: const TextStyle(fontSize: 18),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarView extends StatefulWidget {
  const _AvatarView({required this.state, required this.expression});

  final AvatarState state;
  final AvatarExpression expression;

  @override
  State<_AvatarView> createState() => _AvatarViewState();
}

class _AvatarViewState extends State<_AvatarView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _durationFor(widget.state),
  );
  late final _curve = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);

  static Duration _durationFor(AvatarState state) => switch (state) {
        AvatarState.idle => const Duration(milliseconds: 1800),
        AvatarState.listening => const Duration(milliseconds: 1100),
        AvatarState.thinking => const Duration(milliseconds: 1000),
        AvatarState.speaking => const Duration(milliseconds: 320),
      };

  @override
  void initState() {
    super.initState();
    _syncAnimation(widget.state);
  }

  @override
  void didUpdateWidget(covariant _AvatarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _syncAnimation(widget.state);
    }
  }

  // Idle stays perfectly still. Listening/speaking loop a back-and-forth
  // gesture (faster while speaking, to read as "talking" rather than "idly
  // swaying"). Thinking instead sweeps 0→1 one-way on repeat, so the dot
  // indicator it drives pulses in one direction instead of ping-ponging.
  void _syncAnimation(AvatarState state) {
    _controller.duration = _durationFor(state);
    switch (state) {
      case AvatarState.idle:
        _controller.stop();
        _controller.value = 0;
      case AvatarState.thinking:
        _controller.repeat();
      case AvatarState.listening:
      case AvatarState.speaking:
        _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (widget.state) {
      AvatarState.idle => (
          colorScheme.primaryContainer,
          colorScheme.onPrimaryContainer,
        ),
      AvatarState.listening => (
          colorScheme.tertiaryContainer,
          colorScheme.onTertiaryContainer,
        ),
      AvatarState.thinking => (
          colorScheme.surfaceContainerHighest,
          colorScheme.onSurfaceVariant,
        ),
      AvatarState.speaking => (
          colorScheme.secondaryContainer,
          colorScheme.onSecondaryContainer,
        ),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 220,
      height: 220,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, _) {
          return CustomPaint(
            size: const Size(220, 220),
            painter: _StickFigurePainter(
              state: widget.state,
              expression: widget.expression,
              t: _curve.value,
              color: fg,
            ),
          );
        },
      ),
    );
  }
}

/// Draws a simple stick figure whose pose reflects [state]: still for idle,
/// a hand cupped near the ear for listening, both hands gesturing outward
/// with an open/closing mouth for speaking. [t] oscillates 0→1→0 and drives
/// whichever motion the current state uses. [expression] (喜/怒/哀/樂 plus
/// neutral) drives the eyebrows and mouth curve — purely decorative, not
/// tied to any real detected sentiment.
class _StickFigurePainter extends CustomPainter {
  _StickFigurePainter({
    required this.state,
    required this.expression,
    required this.t,
    required this.color,
  });

  final AvatarState state;
  final AvatarExpression expression;
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    final head = Offset(cx, 62);
    const headRadius = 28.0;
    final shoulder = Offset(cx, 96);
    final hip = Offset(cx, 148);

    canvas.drawCircle(head, headRadius, linePaint);
    canvas.drawLine(shoulder, hip, linePaint);
    canvas.drawLine(hip, Offset(cx - 26, 198), linePaint);
    canvas.drawLine(hip, Offset(cx + 26, 198), linePaint);

    final (leftHand, rightHand) = _handPositions(shoulder);
    canvas.drawLine(shoulder, leftHand, linePaint);
    canvas.drawLine(shoulder, rightHand, linePaint);

    _paintEyes(canvas, head);
    _paintEyebrows(canvas, head);
    _paintMouth(canvas, head);
    if (state == AvatarState.thinking) {
      _paintThinkingDots(canvas, head, headRadius);
    }
  }

  void _paintEyes(Canvas canvas, Offset head) {
    final eyePaint = Paint()..color = color;
    canvas.drawCircle(head + const Offset(-10, -4), 2.5, eyePaint);
    canvas.drawCircle(head + const Offset(10, -4), 2.5, eyePaint);
  }

  /// Two short lines above the eyes. Angle encodes the emotion: a
  /// downward-pointing "V" (inner end low) reads as angry/furrowed; the
  /// opposite (inner end high) reads as sorrowful/concerned; raised outer
  /// ends read as bright/cheerful; flat is neutral.
  void _paintEyebrows(Canvas canvas, Offset head) {
    final browPaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final leftEye = head + const Offset(-10, -4);
    final rightEye = head + const Offset(10, -4);

    void drawPair(Offset leftInner, Offset leftOuter) {
      canvas.drawLine(leftEye + leftOuter, leftEye + leftInner, browPaint);
      // Mirror horizontally for the right brow.
      canvas.drawLine(
        rightEye + Offset(-leftOuter.dx, leftOuter.dy),
        rightEye + Offset(-leftInner.dx, leftInner.dy),
        browPaint,
      );
    }

    switch (expression) {
      case AvatarExpression.neutral:
        drawPair(const Offset(6, -8), const Offset(-6, -8));
      case AvatarExpression.anger:
        // Inner end low, outer end high — furrowed glare.
        drawPair(const Offset(6, -4), const Offset(-6, -12));
      case AvatarExpression.sorrow:
        // Inner end high, outer end low — concerned/pleading.
        drawPair(const Offset(6, -12), const Offset(-6, -4));
      case AvatarExpression.joy:
      case AvatarExpression.happy:
        // Outer end raised — bright, relaxed.
        drawPair(const Offset(6, -9), const Offset(-6, -13));
    }
  }

  (Offset, Offset) _handPositions(Offset shoulder) {
    switch (state) {
      case AvatarState.idle:
        // Relaxed at the sides, no motion.
        return (
          shoulder + const Offset(-28, 46),
          shoulder + const Offset(28, 46),
        );
      case AvatarState.listening:
        // Left arm relaxed; right hand cupped near the ear, gently bobbing.
        return (
          shoulder + const Offset(-28, 46),
          shoulder + Offset(26, -30 - 6 * t),
        );
      case AvatarState.thinking:
        // Left arm relaxed; right hand rests near the chin, still — the
        // dot indicator above the head is what signals "processing".
        return (
          shoulder + const Offset(-28, 46),
          shoulder + const Offset(24, -8),
        );
      case AvatarState.speaking:
        // Both hands swing outward and up together, like talking with
        // one's hands.
        return (
          shoulder + Offset(-30 - 10 * t, 44 - 34 * t),
          shoulder + Offset(30 + 10 * t, 44 - 34 * t),
        );
    }
  }

  // Positive bulges the middle of the closed-mouth curve downward, which
  // reads as a smile (corners relatively raised); negative reads as a
  // frown/press. See _paintMouth's use of it as a quadratic Bezier control
  // point offset.
  double get _mouthCurveOffset {
    switch (expression) {
      case AvatarExpression.neutral:
        return 0;
      case AvatarExpression.anger:
        return -2;
      case AvatarExpression.sorrow:
        return -6;
      case AvatarExpression.joy:
        return 7;
      case AvatarExpression.happy:
        return 4;
    }
  }

  void _paintMouth(Canvas canvas, Offset head) {
    final mouthCenter = head + const Offset(0, 10);

    if (state == AvatarState.speaking) {
      final openness = 2 + 12 * t;
      canvas.drawOval(
        Rect.fromCenter(center: mouthCenter, width: 16, height: openness),
        Paint()..color = color,
      );
      return;
    }

    final curve = _mouthCurveOffset;
    final path = Path()
      ..moveTo(mouthCenter.dx - 8, mouthCenter.dy)
      ..quadraticBezierTo(
        mouthCenter.dx,
        mouthCenter.dy + curve,
        mouthCenter.dx + 8,
        mouthCenter.dy,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  /// Three dots above the head, pulsing in sequence as [t] sweeps 0→1 on
  /// repeat — a lightweight "..." typing-indicator cue for "still thinking".
  void _paintThinkingDots(Canvas canvas, Offset head, double headRadius) {
    final dotPaint = Paint()..style = PaintingStyle.fill;
    final baseY = head.dy - headRadius - 22;

    for (var i = 0; i < 3; i++) {
      final phase = (t + i * 0.33) % 1.0;
      final glow = 0.5 + 0.5 * math.sin(2 * math.pi * phase);
      dotPaint.color = color.withValues(alpha: 0.25 + 0.65 * glow);
      canvas.drawCircle(Offset(head.dx - 16 + i * 16, baseY), 5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _StickFigurePainter oldDelegate) {
    return oldDelegate.state != state ||
        oldDelegate.expression != expression ||
        oldDelegate.t != t ||
        oldDelegate.color != color;
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        selected
            ? IconButton.filled(onPressed: onPressed, icon: Icon(icon))
            : IconButton.filledTonal(onPressed: onPressed, icon: Icon(icon)),
        const SizedBox(height: 4),
        SizedBox(
          width: 72,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }
}
