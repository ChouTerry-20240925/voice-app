import 'package:flutter/material.dart';

void main() {
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

enum AvatarState { idle, listening, speaking }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isCallActive = false;
  final AvatarState _avatarState = AvatarState.idle;

  void _toggleCall() {
    setState(() {
      _isCallActive = !_isCallActive;
    });
  }

  void _selectInterviewMode() {}

  void _selectQaMode() {}

  void _openReportHistory() {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Center(child: _AvatarView(state: _avatarState)),
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
                          onPressed: _selectInterviewMode,
                        ),
                        const SizedBox(height: 24),
                        _ModeButton(
                          icon: Icons.chat_bubble_outline,
                          label: '專業問答模式',
                          onPressed: _selectQaMode,
                        ),
                        const Spacer(),
                        _ModeButton(
                          icon: Icons.description_outlined,
                          label: '報表輸出',
                          onPressed: _openReportHistory,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: SizedBox(
                width: 200,
                height: 64,
                child: ElevatedButton(
                  onPressed: _toggleCall,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isCallActive ? Colors.redAccent : Colors.teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(32),
                    ),
                  ),
                  child: Text(
                    _isCallActive ? '結束通話' : '開始問答',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarView extends StatelessWidget {
  const _AvatarView({required this.state});

  final AvatarState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.primaryContainer,
      ),
      child: Icon(
        Icons.person,
        size: 120,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IconButton.filledTonal(
          onPressed: onPressed,
          icon: Icon(icon),
        ),
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
