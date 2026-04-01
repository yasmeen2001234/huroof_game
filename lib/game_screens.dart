import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import './game_models.dart';
import './game_providers.dart';
import './game_widgets.dart';

// =============================================================================
// LobbyScreen
// =============================================================================

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key, required this.gameId, this.onLeave});
  final String gameId;
  final VoidCallback? onLeave;

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  bool _showSettings = false;

  @override
  Widget build(BuildContext context) {
    final playersAsync = ref.watch(playersStreamProvider(widget.gameId));
    final service = ref.watch(gameServiceProvider);
    final isHost = ref.watch(isHostProvider(widget.gameId));
    final phaseDuration = ref.watch(phaseDurationProvider(widget.gameId));

    return Scaffold(
      backgroundColor: HuruufColors.teal,
      body: SafeArea(
        child: Stack(children: [
          // ── Main content ──────────────────────────────────────────────
          Column(children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(children: [
                Text('حروف',
                    style: arabicStyle(
                            fontSize: 48,
                            color: Colors.white,
                            weight: FontWeight.w900)
                        .copyWith(shadows: const [
                      Shadow(
                          color: Color(0x44000000),
                          offset: Offset(2, 4),
                          blurRadius: 8)
                    ])),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: widget.gameId));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('تم نسخ رمز الغرفة',
                              style: arabicStyle(color: Colors.white)),
                          backgroundColor: HuruufColors.teal,
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.5), width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('كود الغرفة: ${widget.gameId}',
                            style: GoogleFonts.orbitron(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 3)),
                        const SizedBox(width: 8),
                        Icon(Icons.copy,
                            size: 16, color: Colors.white.withOpacity(0.8)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text('شارك الكود مع أصدقائك',
                    style: arabicStyle(
                        fontSize: 13, color: Colors.white.withOpacity(0.8))),
              ]),
            ),

            // Player avatars
            SizedBox(
              height: 150,
              child: playersAsync.when(
                data: (players) => ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: players.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Column(children: [
                      const FaceDownCard(),
                      const SizedBox(height: 3),
                      Text(players[i].username,
                          style: arabicStyle(
                              fontSize: 12,
                              color: Colors.white,
                              weight: FontWeight.w800)),
                    ]),
                  ).animate().fadeIn(delay: Duration(milliseconds: 100 * i)),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
              ),
            ),

            // Players list
            Expanded(
              child: Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: playersAsync.when(
                  data: (players) => ListView.separated(
                    padding: const EdgeInsets.all(14),
                    itemCount: players.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white38, height: 1),
                    itemBuilder: (_, i) {
                      final p = players[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.white.withOpacity(0.3),
                          child: Text(p.username[0].toUpperCase(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ),
                        title: Text(p.username,
                            textDirection: TextDirection.rtl,
                            style: arabicStyle(
                                fontSize: 15,
                                color: Colors.white,
                                weight: FontWeight.w800)),
                        trailing: p.isHost
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                    color: HuruufColors.gold.withOpacity(0.8),
                                    borderRadius: BorderRadius.circular(10)),
                                child: Text('قائد',
                                    style: arabicStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                        weight: FontWeight.w800)),
                              )
                            : null,
                      ).animate().fadeIn(delay: Duration(milliseconds: 80 * i));
                    },
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('$e')),
                ),
              ),
            ),

            // Start button (host only)
            if (isHost)
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 0, 40, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: playersAsync.maybeWhen(
                      data: (players) => players.length > 1
                          ? () => service.startNextRound(widget.gameId)
                          : null,
                      orElse: () => null,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HuruufColors.cardBorder,
                      foregroundColor: HuruufColors.cream,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 6,
                      disabledBackgroundColor: Colors.grey.shade400,
                    ),
                    child: playersAsync.maybeWhen(
                      data: (players) => players.length <= 1
                          ? Text('انتظر المزيد من اللاعبين',
                              style: arabicStyle(
                                  fontSize: 18,
                                  color: Colors.white70,
                                  weight: FontWeight.w900))
                          : Text('ابدأ اللعبة! 🎮',
                              style: arabicStyle(
                                  fontSize: 22,
                                  color: HuruufColors.cream,
                                  weight: FontWeight.w900)),
                      orElse: () => Text('ابدأ اللعبة! 🎮',
                          style: arabicStyle(
                              fontSize: 22,
                              color: HuruufColors.cream,
                              weight: FontWeight.w900)),
                    ),
                  ),
                ),
              ),
          ]),

          // Tap outside to close — MUST be before the panel in the Stack
          // so the panel renders on top and receives taps first
          if (_showSettings)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showSettings = false),
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),

          // Settings gear button (top-right) — always on top
          Positioned(
            top: 8,
            right: 12,
            child: IconButton(
              icon: AnimatedRotation(
                turns: _showSettings ? 0.125 : 0,
                duration: const Duration(milliseconds: 300),
                child: const Icon(Icons.settings_rounded,
                    color: Colors.white, size: 28),
              ),
              onPressed: () => setState(() => _showSettings = !_showSettings),
            ),
          ),

          // Settings panel — last in Stack = topmost, receives taps before GestureDetector
          if (_showSettings)
            Positioned(
              top: 48,
              right: 12,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 240,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: HuruufColors.cardBorder,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x55000000),
                          blurRadius: 16,
                          offset: Offset(0, 6))
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('الإعدادات',
                          textDirection: TextDirection.rtl,
                          style: arabicStyle(
                              fontSize: 16,
                              color: HuruufColors.cream,
                              weight: FontWeight.w900)),
                      const Divider(color: Colors.white24, height: 20),
                      Text('وقت التصويت',
                          textDirection: TextDirection.rtl,
                          style:
                              arabicStyle(fontSize: 13, color: Colors.white70)),
                      const SizedBox(height: 8),
                      if (isHost) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: DropdownButton<int>(
                            value: phaseDuration,
                            isExpanded: true,
                            dropdownColor: HuruufColors.cardBorder,
                            underline: const SizedBox(),
                            icon: const Icon(Icons.expand_more,
                                color: Colors.white70),
                            items: const [
                              DropdownMenuItem(
                                  value: 15,
                                  child: Text('15 ثانية',
                                      textDirection: TextDirection.rtl,
                                      style: TextStyle(color: Colors.white))),
                              DropdownMenuItem(
                                  value: 30,
                                  child: Text('30 ثانية',
                                      textDirection: TextDirection.rtl,
                                      style: TextStyle(color: Colors.white))),
                              DropdownMenuItem(
                                  value: 60,
                                  child: Text('60 ثانية',
                                      textDirection: TextDirection.rtl,
                                      style: TextStyle(color: Colors.white))),
                              DropdownMenuItem(
                                  value: 90,
                                  child: Text('90 ثانية',
                                      textDirection: TextDirection.rtl,
                                      style: TextStyle(color: Colors.white))),
                            ],
                            onChanged: (v) {
                              if (v != null)
                                service.updatePhaseDuration(widget.gameId, v);
                            },
                          ),
                        ),
                      ] else ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('$phaseDuration ثانية',
                              textDirection: TextDirection.rtl,
                              style: arabicStyle(
                                  fontSize: 14, color: Colors.white70)),
                        ),
                      ],
                      const Divider(color: Colors.white24, height: 20),
                      if (widget.onLeave != null)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              setState(() => _showSettings = false);
                              widget.onLeave!();
                            },
                            icon: const Icon(Icons.exit_to_app, size: 18),
                            label: Text('مغادرة الغرفة',
                                textDirection: TextDirection.rtl,
                                style: arabicStyle(
                                    fontSize: 14,
                                    color: Colors.white,
                                    weight: FontWeight.w800)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: HuruufColors.downvote,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

// =============================================================================
// TypingScreen
// =============================================================================

class TypingScreen extends ConsumerStatefulWidget {
  const TypingScreen({super.key, required this.gameId, required this.round});
  final String gameId;
  final RoundModel round;

  @override
  ConsumerState<TypingScreen> createState() => _TypingScreenState();
}

class _TypingScreenState extends ConsumerState<TypingScreen> {
  final _ctrl = TextEditingController();
  bool _submitted = false;
  bool _advancing = false;
  Timer? _draftSaveTimer;

  @override
  void initState() {
    super.initState();
    // Listen for changes and save draft with debounce
    _ctrl.addListener(_onTyping);
  }

  void _onTyping() {
    // Cancel previous timer
    _draftSaveTimer?.cancel();
    // Debounce: save draft 500ms after user stops typing
    _draftSaveTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && !_submitted) {
        final draft = _ctrl.text;
        ref.read(gameServiceProvider).saveDraftAnswer(
              widget.gameId,
              widget.round.id,
              draft,
            );
      }
    });
  }

  @override
  void didUpdateWidget(TypingScreen old) {
    super.didUpdateWidget(old);
    if (old.round.id != widget.round.id) {
      _ctrl.clear();
      _submitted = false;
      _advancing = false;
      _draftSaveTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    _ctrl.removeListener(_onTyping);
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitted) return;
    final answer = _ctrl.text.trim();
    if (answer.isEmpty) return;
    setState(() => _submitted = true);
    // Capture timer at exact moment of submission for speed bonus
    final timeLeft = ref.read(timerProvider(widget.gameId));
    await ref
        .read(gameServiceProvider)
        .submitAnswer(widget.gameId, widget.round.id, answer, timeLeft);
  }

  void _checkAllSubmitted(RoundModel round, List<PlayerModel> players) async {
    if (round.id != widget.round.id) return;
    if (round.state != RoundState.typing) return;
    if (_advancing) return;
    final active = players.where((p) => !p.isEliminated).length;
    if (active > 0 && round.submissions.length >= active) {
      _advancing = true;
      final isHost = await ref.read(gameServiceProvider).isHost(widget.gameId);
      if (isHost && mounted) {
        // Eliminate anyone who didn't submit before we advance
        await ref
            .read(gameServiceProvider)
            .eliminateNonSubmitters(widget.gameId, round.id);
        await ref
            .read(gameServiceProvider)
            .advanceRoundState(widget.gameId, round.id, RoundState.voting);
      }
    }
  }

  Future<void> _checkAllEliminated() async {
    if (_advancing) return;
    final allEliminated = await ref
        .read(gameServiceProvider)
        .areAllPlayersEliminated(widget.gameId);
    if (allEliminated && mounted) {
      _advancing = true;
      final isHost = await ref.read(gameServiceProvider).isHost(widget.gameId);
      if (isHost) {
        // Skip remaining phases and go to results
        await ref.read(gameServiceProvider).advanceRoundState(
            widget.gameId, widget.round.id, RoundState.results);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final timer = ref.watch(timerProvider(widget.gameId));
    final isEliminated = ref.watch(isEliminatedProvider(widget.gameId));

    // Safe to call ref.listen in build — Riverpod deduplicates per build cycle
    ref.listen(currentRoundProvider(widget.gameId), (_, next) {
      next.whenData((round) {
        if (round == null || !mounted) return;
        final players = ref
                .read(playersStreamProvider(widget.gameId))
                .whenOrNull(data: (p) => p) ??
            [];
        _checkAllSubmitted(round, players);
        // Also check if all players are eliminated
        _checkAllEliminated();
      });
    });

    // Watch players stream to detect when all are eliminated
    ref.watch(playersStreamProvider(widget.gameId));

    return Scaffold(
      backgroundColor: HuruufColors.teal,
      body: SafeArea(
        child: Column(children: [
          PhaseHeader(
              state: RoundState.typing, roundNumber: widget.round.roundNumber),
          if (isEliminated) ...[
            const Spacer(),
            _SpectatorBanner(),
            const Spacer(),
          ] else ...[
            const SizedBox(height: 20),
            SandWatchTimer(
                secondsRemaining: timer,
                totalSeconds: ref.watch(phaseDurationProvider(widget.gameId))),
            const SizedBox(height: 20),
            VintageCard(
              category: widget.round.category,
              letter: widget.round.letter,
              answerController: _ctrl,
              readOnly: _submitted,
            ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
            const SizedBox(height: 24),
            if (!_submitted)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HuruufColors.cardBorder,
                      foregroundColor: HuruufColors.cream,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('إرسال ✅',
                        style: arabicStyle(
                            fontSize: 20,
                            color: HuruufColors.cream,
                            weight: FontWeight.w900)),
                  ),
                ),
              )
            else
              _WaitingChip(label: 'تم الإرسال! انتظر الآخرين...'),
          ],
        ]),
      ),
    );
  }
}

// =============================================================================
// VotingScreen — horizontal cards, changeable votes
// =============================================================================

class VotingScreen extends ConsumerWidget {
  const VotingScreen({super.key, required this.gameId, required this.round});
  final String gameId;
  final RoundModel round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final timer = ref.watch(timerProvider(gameId));
    final isEliminated = ref.watch(isEliminatedProvider(gameId));
    final service = ref.watch(gameServiceProvider);
    final players =
        ref.watch(playersStreamProvider(gameId)).whenOrNull(data: (p) => p) ??
            [];
    final activeCount = players.where((p) => !p.isEliminated).length;

    return Scaffold(
      backgroundColor: HuruufColors.teal,
      body: SafeArea(
        child: Column(children: [
          PhaseHeader(state: RoundState.voting, roundNumber: round.roundNumber),
          if (isEliminated)
            Expanded(child: _SpectatorBanner())
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: SandWatchTimer(
                  secondsRemaining: timer,
                  totalSeconds: ref.watch(phaseDurationProvider(gameId))),
            ),

            // Horizontal scroll with fixed-width cards and 16px gap
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                itemCount: round.submissions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemBuilder: (_, i) {
                  final sub = round.submissions[i];
                  final isSelf = sub.playerId == session.userId;
                  final myVote = ref.watch(myVoteProvider((
                    gameId: gameId,
                    targetPlayerId: sub.playerId,
                  )));

                  return SizedBox(
                    width: 230,
                    child: _VotingCard(
                      submission: sub,
                      category: round.category,
                      letter: round.letter,
                      isSelf: isSelf,
                      myVote: myVote,
                      onUpvote: isSelf
                          ? null
                          : () => service.castVote(
                              gameId, round.id, sub.playerId, 'up'),
                      onDownvote: isSelf
                          ? null
                          : () => service.castVote(
                              gameId, round.id, sub.playerId, 'down'),
                    )
                        .animate()
                        .fadeIn(delay: Duration(milliseconds: 120 * i))
                        .slideX(begin: 0.2),
                  );
                },
              ),
            ),

            // Skip button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: round.skipVoters.contains(session.userId ?? '')
                          ? null
                          : () => service.markSkip(gameId, round.id),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            round.skipVoters.contains(session.userId ?? '')
                                ? Colors.grey.shade400
                                : HuruufColors.cardBorder,
                        foregroundColor: HuruufColors.cream,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        round.skipVoters.contains(session.userId ?? '')
                            ? 'تم التخطي'
                            : 'تخطي',
                        style: arabicStyle(
                            fontSize: 18,
                            color: HuruufColors.cream,
                            weight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'تخطى ${round.skipVoters.length} من $activeCount',
                    style: arabicStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.8),
                        weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _VotingCard extends StatelessWidget {
  const _VotingCard({
    required this.submission,
    required this.category,
    required this.letter,
    required this.isSelf,
    required this.myVote,
    this.onUpvote,
    this.onDownvote,
  });

  final PlayerSubmission submission;
  final TaskCategory category;
  final String letter;
  final bool isSelf;
  final String? myVote; // null | 'up' | 'down'
  final VoidCallback? onUpvote;
  final VoidCallback? onDownvote;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(isSelf ? 0.35 : 0.18),
        borderRadius: BorderRadius.circular(16),
        border: isSelf ? Border.all(color: HuruufColors.gold, width: 2) : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Username + speed bonus badge
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: Colors.white.withOpacity(0.3),
              child: Text(submission.username[0].toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                submission.username + (isSelf ? ' (أنت)' : ''),
                textDirection: TextDirection.rtl,
                overflow: TextOverflow.ellipsis,
                style: arabicStyle(
                    fontSize: 13, color: Colors.white, weight: FontWeight.w800),
              ),
            ),
            // Speed bonus badge — only show if they earned any bonus
            if (submission.bonusPoints > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: HuruufColors.gold,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('+${submission.bonusPoints} ⚡',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ]),
          const SizedBox(height: 10),

          VintageCard(
            category: category,
            letter: letter,
            answer: submission.answer,
            readOnly: true,
          ),
          const SizedBox(height: 10),

          // Changeable vote buttons
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _VoteBtn(
              icon: Icons.arrow_upward_rounded,
              count: submission.upvotes,
              color: HuruufColors.upvote,
              active: myVote == 'up',
              disabled: isSelf,
              onTap: onUpvote,
            ),
            const SizedBox(width: 16),
            _VoteBtn(
              icon: Icons.arrow_downward_rounded,
              count: submission.downvotes,
              color: HuruufColors.downvote,
              active: myVote == 'down',
              disabled: isSelf,
              onTap: onDownvote,
            ),
          ]),

          if (isSelf)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('لا يمكنك التصويت على إجابتك',
                  style: arabicStyle(fontSize: 11, color: Colors.white54),
                  textDirection: TextDirection.rtl),
            ),
        ],
      ),
    );
  }
}

class _VoteBtn extends StatelessWidget {
  const _VoteBtn({
    required this.icon,
    required this.count,
    required this.color,
    required this.active,
    required this.disabled,
    this.onTap,
  });
  final IconData icon;
  final int count;
  final Color color;
  final bool active;
  final bool disabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = disabled ? Colors.grey.shade400 : color;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: disabled ? null : onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: active ? c : c.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: c, width: active ? 0 : 2),
              boxShadow: active
                  ? [
                      BoxShadow(
                          color: c.withOpacity(0.5),
                          blurRadius: 8,
                          spreadRadius: 1)
                    ]
                  : [],
            ),
            child: Icon(icon, color: active ? Colors.white : c, size: 22),
          ),
        ),
        const SizedBox(height: 4),
        Text(count.toString(),
            style:
                TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }
}

// =============================================================================
// UniquenessScreen — horizontal scroll, "التالي" for all, all-ready advance
// =============================================================================

class UniquenessScreen extends ConsumerStatefulWidget {
  const UniquenessScreen(
      {super.key, required this.gameId, required this.round});
  final String gameId;
  final RoundModel round;

  @override
  ConsumerState<UniquenessScreen> createState() => _UniquenessScreenState();
}

class _UniquenessScreenState extends ConsumerState<UniquenessScreen> {
  Future<void> _markReady() async {
    await ref
        .read(gameServiceProvider)
        .markReady(widget.gameId, widget.round.id);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final timer = ref.watch(timerProvider(widget.gameId));
    final isEliminated = ref.watch(isEliminatedProvider(widget.gameId));
    final hasReady = ref.watch(hasMarkedReadyProvider(widget.gameId));
    final myPicks = ref.watch(myUniquePicksProvider(widget.gameId));
    final service = ref.watch(gameServiceProvider);

    final validSubs =
        widget.round.submissions.where((s) => !s.isEliminated).toList();

    return Scaffold(
      backgroundColor: HuruufColors.teal,
      body: SafeArea(
        child: Column(children: [
          PhaseHeader(
              state: RoundState.uniqueness,
              roundNumber: widget.round.roundNumber),
          if (isEliminated)
            Expanded(child: _SpectatorBanner())
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: SandWatchTimer(
                  secondsRemaining: timer,
                  totalSeconds:
                      ref.watch(phaseDurationProvider(widget.gameId))),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text('اختر الكلمات الغير مكررة',
                  textDirection: TextDirection.rtl,
                  style: arabicStyle(
                      fontSize: 18,
                      color: Colors.white,
                      weight: FontWeight.w900)),
            ),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                itemCount: validSubs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemBuilder: (_, i) {
                  final sub = validSubs[i];
                  final isSelf = sub.playerId == session.userId;

                  // Did I pick this card?
                  final iMyPicked = myPicks.contains(sub.playerId);

                  // Total number of players who voted this card
                  final totalVotes =
                      widget.round.uniqueVoteCountFor(sub.playerId);

                  return SizedBox(
                    width: 230,
                    child: _UniqueCard(
                      submission: sub,
                      category: widget.round.category,
                      letter: widget.round.letter,
                      isSelf: isSelf,
                      iMyPicked: iMyPicked,
                      totalVotes: totalVotes,
                      onTap: iMyPicked
                          ? () => service.removeUniqueVote(
                              widget.gameId, widget.round.id, sub.playerId)
                          : () => service.voteUniqueWord(
                              widget.gameId, widget.round.id, sub.playerId),
                    )
                        .animate()
                        .fadeIn(delay: Duration(milliseconds: 100 * i))
                        .slideX(begin: 0.2),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 8, 40, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: hasReady ? null : _markReady,
                  icon: Icon(hasReady
                      ? Icons.check_circle_rounded
                      : Icons.arrow_forward_rounded),
                  label: Text(
                    hasReady ? 'في انتظار الآخرين...' : 'التالي ←',
                    style: arabicStyle(
                        fontSize: 20,
                        color: Colors.white,
                        weight: FontWeight.w900),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasReady
                        ? Colors.white.withOpacity(0.2)
                        : const Color(0xFF9B59B6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: hasReady ? 0 : 4,
                  ),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _UniqueCard extends StatelessWidget {
  const _UniqueCard({
    required this.submission,
    required this.category,
    required this.letter,
    required this.isSelf,
    required this.iMyPicked, // did I vote this card?
    required this.totalVotes, // how many players total voted this card
    this.onTap,
  });

  final PlayerSubmission submission;
  final TaskCategory category;
  final String letter;
  final bool isSelf;
  final bool iMyPicked;
  final int totalVotes;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: iMyPicked
              ? [
                  BoxShadow(
                      color: HuruufColors.gold.withOpacity(0.5),
                      blurRadius: 16,
                      spreadRadius: 2)
                ]
              : [],
        ),
        child: Stack(children: [
          VintageCard(
            category: category,
            letter: letter,
            answer: submission.answer,
            readOnly: true,
          ),

          // MY vote highlight — only shown to me (the voter)
          if (iMyPicked)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: HuruufColors.gold.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: HuruufColors.gold, width: 3),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.star_rounded,
                        color: HuruufColors.gold, size: 44),
                    const SizedBox(height: 4),
                    Text('اضغط للإلغاء',
                        textDirection: TextDirection.rtl,
                        style: arabicStyle(
                            fontSize: 11,
                            color: HuruufColors.gold,
                            weight: FontWeight.w800)),
                  ],
                ),
              ),
            ),

          // Total vote count badge (top-right) — visible to everyone
          if (totalVotes > 0)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: HuruufColors.gold,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded,
                        color: Colors.white, size: 12),
                    const SizedBox(width: 2),
                    Text('$totalVotes',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),

          // Username + self badge
          Positioned(
            bottom: 6,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(submission.username,
                    textAlign: TextAlign.center,
                    style: arabicStyle(
                        fontSize: 11,
                        color: HuruufColors.cardBorder,
                        weight: FontWeight.w800)),
                if (isSelf) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: HuruufColors.gold.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('أنت',
                        style: arabicStyle(
                            fontSize: 9,
                            color: Colors.white,
                            weight: FontWeight.w900)),
                  ),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// =============================================================================
// ResultsScreen
// =============================================================================

class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key, required this.gameId, required this.round});
  final String gameId;
  final RoundModel round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaderboard = ref.watch(leaderboardProvider(gameId));
    final service = ref.watch(gameServiceProvider);

    return Scaffold(
      backgroundColor: HuruufColors.teal,
      body: SafeArea(
        child: Column(children: [
          PhaseHeader(
              state: RoundState.results, roundNumber: round.roundNumber),
          const SizedBox(height: 20),
          Text('🏆 نتائج الجولة',
              style: arabicStyle(
                  fontSize: 26, color: Colors.white, weight: FontWeight.w900)),
          const SizedBox(height: 14),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: leaderboard.length,
              itemBuilder: (_, i) =>
                  _LeaderRow(rank: i + 1, player: leaderboard[i])
                      .animate()
                      .fadeIn(delay: Duration(milliseconds: 100 * i))
                      .slideX(begin: -0.2),
            ),
          ),
          if (ref.watch(isHostProvider(gameId)))
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 0, 40, 20),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    service.startNextRound(gameId);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HuruufColors.cardBorder,
                    foregroundColor: HuruufColors.cream,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('الجولة التالية ⏭️',
                      style: arabicStyle(
                          fontSize: 20,
                          color: HuruufColors.cream,
                          weight: FontWeight.w900)),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({required this.rank, required this.player});
  final int rank;
  final PlayerModel player;

  @override
  Widget build(BuildContext context) {
    final medals = {1: '🥇', 2: '🥈', 3: '🥉'};
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: rank == 1
            ? HuruufColors.gold.withOpacity(0.25)
            : Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        border:
            rank == 1 ? Border.all(color: HuruufColors.gold, width: 2) : null,
      ),
      child: Row(children: [
        Text(medals[rank] ?? '$rank.', style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(player.username,
                textDirection: TextDirection.rtl,
                style: arabicStyle(
                    fontSize: 16,
                    color: Colors.white,
                    weight: FontWeight.w900)),
            if (player.isEliminated)
              Text('مُقصى',
                  style:
                      arabicStyle(fontSize: 12, color: HuruufColors.downvote),
                  textDirection: TextDirection.rtl),
          ]),
        ),
        ScoreChip(score: player.score),
      ]),
    );
  }
}

// =============================================================================
// Shared helpers
// =============================================================================

class _WaitingChip extends StatelessWidget {
  const _WaitingChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(30)),
      child: Text(label,
          textDirection: TextDirection.rtl,
          style: arabicStyle(
              fontSize: 15, color: Colors.white, weight: FontWeight.w800)),
    )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(duration: 1200.ms, color: Colors.white38);
  }
}

class _SpectatorBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('👀', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 14),
          Text('أنت في وضع المشاهد',
              style: arabicStyle(
                  fontSize: 22, color: Colors.white, weight: FontWeight.w900),
              textDirection: TextDirection.rtl),
          const SizedBox(height: 6),
          Text('تم إقصاؤك هذه الجولة',
              style: arabicStyle(fontSize: 15, color: Colors.white70),
              textDirection: TextDirection.rtl),
        ]),
      );
}
