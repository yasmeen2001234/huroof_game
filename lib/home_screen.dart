import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import './game_models.dart';
import './game_providers.dart';
import './game_widgets.dart';
import 'debug_screen.dart';
import 'game_screens.dart';

// =============================================================================
// HomeScreen
// =============================================================================

class HomeScreen extends ConsumerStatefulWidget {
  HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _usernameCtrl = TextEditingController();
  final _roomCtrl     = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _roomCtrl.dispose();
    super.dispose();
  }

  Future<void> _createGame() async {
    final username = _usernameCtrl.text.trim();
    if (username.isEmpty) return _err('يرجى إدخال اسمك');
    setState(() => _loading = true);
    try {
      final service = ref.read(gameServiceProvider);
      final gameId  = await service.createGame(username);
      ref.read(sessionProvider.notifier).setSession(
        gameId: gameId, userId: service.currentUserId, username: username,
      );
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => GameRouter(gameId: gameId)),
        );
      }
    } catch (e) { _err('$e'); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _joinGame() async {
    final username = _usernameCtrl.text.trim();
    final code     = _roomCtrl.text.trim().toUpperCase();
    if (username.isEmpty) return _err('يرجى إدخال اسمك');
    if (code.isEmpty)     return _err('يرجى إدخال كود الغرفة');
    setState(() => _loading = true);
    try {
      final service = ref.read(gameServiceProvider);
      await service.joinGame(code, username);
      ref.read(sessionProvider.notifier).setSession(
        gameId: code, userId: service.currentUserId, username: username,
      );
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => GameRouter(gameId: code)),
        );
      }
    } catch (e) { _err('$e'); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  void _err(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, textDirection: TextDirection.rtl),
      backgroundColor: HuruufColors.downvote,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuruufColors.teal,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: Column(children: [
            Text('حروف',
                style: arabicStyle(fontSize: 72, color: Colors.white, weight: FontWeight.w900)
                    .copyWith(shadows: const [Shadow(color: Color(0x44000000), offset: Offset(3, 6), blurRadius: 12)]))
                .animate().fadeIn(duration: 600.ms).scale(begin: const Offset(0.5, 0.5)),
            const SizedBox(height: 6),
            Text('لعبة الكلمات العربية',
                textDirection: TextDirection.rtl,
                style: arabicStyle(fontSize: 18, color: Colors.white.withOpacity(0.8)))
                .animate().fadeIn(delay: 300.ms),
            const SizedBox(height: 36),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Transform.rotate(angle: (i - 1) * 0.12, child: const FaceDownCard()),
              ).animate().fadeIn(delay: Duration(milliseconds: 200 * i))),
            ),
            const SizedBox(height: 36),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
              ),
              child: Column(children: [
                _Field(controller: _usernameCtrl, hint: 'اسمك في اللعبة', icon: Icons.person_outline),
                const SizedBox(height: 14),
                _Field(controller: _roomCtrl, hint: 'كود الغرفة (للانضمام فقط)', icon: Icons.tag, ltr: true),
                const SizedBox(height: 6),
                Text('أو أنشئ غرفة جديدة بكود عشوائي',
                    textDirection: TextDirection.rtl, textAlign: TextAlign.center,
                    style: arabicStyle(fontSize: 12, color: Colors.white60)),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(child: _Btn(label: 'إنشاء غرفة 🎲', color: HuruufColors.cardBorder, onTap: _loading ? null : _createGame)),
                  const SizedBox(width: 12),
                  Expanded(child: _Btn(label: 'انضم', color: HuruufColors.gold.withOpacity(0.85), onTap: _loading ? null : _joinGame)),
                ]),
                if (_loading)
                  const Padding(padding: EdgeInsets.only(top: 16),
                    child: CircularProgressIndicator(color: Colors.white)),
              ]),
            ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.3),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DebugScreen())),
              icon: const Icon(Icons.bug_report, color: Colors.white38, size: 16),
              label: const Text('🛠 Debug: view all rooms', style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.hint, required this.icon, this.ltr = false});
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool ltr;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
    textAlign: TextAlign.center,
    style: arabicStyle(color: Colors.white, fontSize: 16),
    decoration: InputDecoration(
      hintText: hint, hintTextDirection: TextDirection.rtl,
      hintStyle: arabicStyle(color: Colors.white54, fontSize: 15),
      prefixIcon: Icon(icon, color: Colors.white70),
      filled: true, fillColor: Colors.white.withOpacity(0.12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withOpacity(0.2))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: HuruufColors.gold, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}

class _Btn extends StatelessWidget {
  const _Btn({required this.label, required this.color, this.onTap});
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color, foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 4,
      ),
      child: Text(label, style: arabicStyle(fontSize: 16, weight: FontWeight.w900), textDirection: TextDirection.rtl),
    ),
  );
}

// =============================================================================
// GameRouter
// =============================================================================

class GameRouter extends ConsumerStatefulWidget {
  const GameRouter({super.key, required this.gameId});
  final String gameId;

  @override
  ConsumerState<GameRouter> createState() => _GameRouterState();
}

class _GameRouterState extends ConsumerState<GameRouter> {
  StreamSubscription? _presenceSub;
  bool _roomGone  = false;
  bool _leftClean = false;

  @override
  void initState() {
    super.initState();
    _presenceSub = ref.read(gameServiceProvider).watchPresence(
      widget.gameId, _onRoomEmpty,
    );
  }

  @override
  void dispose() {
    _presenceSub?.cancel();
    // KEY FIX: leaveGame() is called on EVERY dispose —
    // navigation away, hot reload, back button, screen replacement.
    // This removes our RTDB node immediately so the server knows we left.
    if (!_leftClean) {
      ref.read(gameServiceProvider).leaveGame(widget.gameId);
    }
    super.dispose();
  }

  // User taps the Leave button explicitly
  Future<void> _leaveExplicitly() async {
    if (_leftClean) return;
    _leftClean = true;
    await ref.read(gameServiceProvider).leaveGame(widget.gameId);
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => HomeScreen()), (_) => false,
      );
    }
  }

  void _onRoomEmpty() async {
    if (_roomGone || _leftClean) return;
    _roomGone  = true;
    _leftClean = true;
    await ref.read(gameServiceProvider).deleteGame(widget.gameId);
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => HomeScreen()), (_) => false,
      );
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('انتهت الغرفة', textDirection: TextDirection.rtl,
            style: arabicStyle(color: Colors.white)),
        backgroundColor: HuruufColors.downvote,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(phaseOrchestratorProvider(widget.gameId));

    final gameAsync  = ref.watch(gameStreamProvider(widget.gameId));
    final roundAsync = ref.watch(currentRoundProvider(widget.gameId));

    return PopScope(
      canPop: false,
      onPopInvoked: (_) => _leaveExplicitly(),
      child: gameAsync.when(
        loading: () => _bg(const CircularProgressIndicator(color: Colors.white)),
        error:   (e, _) => _bg(Text('خطأ: $e', style: const TextStyle(color: Colors.white))),
        data: (game) {
          if (game.currentState == RoundState.waiting) {
            return LobbyScreen(gameId: widget.gameId, onLeave: _leaveExplicitly);
          }
          return roundAsync.when(
            loading: () => _bg(const CircularProgressIndicator(color: Colors.white)),
            error:   (e, _) => _bg(Text('خطأ: $e', style: const TextStyle(color: Colors.white))),
            data: (round) {
              if (round == null) return LobbyScreen(gameId: widget.gameId, onLeave: _leaveExplicitly);
              switch (game.currentState) {
                case RoundState.typing:     return TypingScreen(gameId: widget.gameId, round: round);
                case RoundState.voting:     return VotingScreen(gameId: widget.gameId, round: round);
                case RoundState.uniqueness: return UniquenessScreen(gameId: widget.gameId, round: round);
                case RoundState.results:    return ResultsScreen(gameId: widget.gameId, round: round);
                default:                    return LobbyScreen(gameId: widget.gameId, onLeave: _leaveExplicitly);
              }
            },
          );
        },
      ),
    );
  }

  Widget _bg(Widget child) => Scaffold(
    backgroundColor: HuruufColors.teal,
    body: Center(child: child),
  );
}