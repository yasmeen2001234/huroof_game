import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import './game_models.dart';
import './game_service.dart';

// ── Service ───────────────────────────────────────────────────────────────────

final gameServiceProvider =
    Provider<GameService>((ref) => GameService());

// ── Session ───────────────────────────────────────────────────────────────────

class SessionState {
  final String? gameId;
  final String? userId;
  final String? username;

  const SessionState({this.gameId, this.userId, this.username});

  SessionState copyWith({
    String? gameId,
    String? userId,
    String? username,
  }) =>
      SessionState(
        gameId: gameId ?? this.gameId,
        userId: userId ?? this.userId,
        username: username ?? this.username,
      );
}

class SessionNotifier extends StateNotifier<SessionState> {
  SessionNotifier() : super(const SessionState());

  void setSession({
    required String gameId,
    required String userId,
    required String username,
  }) =>
      state = state.copyWith(
          gameId: gameId, userId: userId, username: username);

  void clear() => state = const SessionState();
}

final sessionProvider =
    StateNotifierProvider<SessionNotifier, SessionState>(
        (ref) => SessionNotifier());

// ── Firestore streams ─────────────────────────────────────────────────────────

final gameStreamProvider = StreamProvider.family<GameModel, String>(
    (ref, gameId) =>
        ref.watch(gameServiceProvider).watchGame(gameId));

final playersStreamProvider =
    StreamProvider.family<List<PlayerModel>, String>((ref, gameId) =>
        ref.watch(gameServiceProvider).watchPlayers(gameId));

final currentRoundProvider =
    StreamProvider.family<RoundModel?, String>((ref, gameId) =>
        ref.watch(gameServiceProvider).watchCurrentRound(gameId));

// ── Timer ─────────────────────────────────────────────────────────────────────

class TimerNotifier extends StateNotifier<int> {
  TimerNotifier() : super(30);
  Timer? _timer;

  void startFrom(int seconds) {
    _timer?.cancel();
    state = seconds.clamp(0, 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _timer?.cancel();
        return;
      }
      if (state > 0) {
        state = state - 1;
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final timerProvider =
    StateNotifierProvider.autoDispose<TimerNotifier, int>(
        (ref) => TimerNotifier());

// ── Phase Orchestrator ────────────────────────────────────────────────────────

class PhaseOrchestrator extends StateNotifier<void> {
  PhaseOrchestrator(this._ref, this._gameId) : super(null) {
    _sub = _ref.listen<AsyncValue<RoundModel?>>(
      currentRoundProvider(_gameId),
      (_, next) => next.whenData(_onRound),
      fireImmediately: true,
    );
  }

  final Ref _ref;
  final String _gameId;
  late final ProviderSubscription _sub;
  Timer? _phaseTimer;
  String? _lastPhaseKey;

  void _onRound(RoundModel? round) async {
    if (round == null) return;
    if (round.state == RoundState.waiting ||
        round.state == RoundState.results) return;

    // Sync timer for all clients from server timestamp
    _syncTimer(round);

    final phaseKey = '${round.id}:${round.state.name}';

    if (_lastPhaseKey == phaseKey) {
      // Same phase — check if all-ready (uniqueness early advance)
      await _checkEarlyAdvance(round);
      return;
    }

    _lastPhaseKey = phaseKey;
    _phaseTimer?.cancel();

    final amHost =
        await _ref.read(gameServiceProvider).isHost(_gameId);
    if (!amHost) return; // only host advances state

    final elapsed = round.phaseStartedAt != null
        ? DateTime.now().difference(round.phaseStartedAt!)
        : Duration.zero;
    final remaining = const Duration(seconds: 30) - elapsed;
    final secs = remaining.inSeconds.clamp(0, 30);

    if (secs <= 0) {
      await _advance(round);
    } else {
      _phaseTimer =
          Timer(Duration(seconds: secs), () => _advance(round));
    }
  }

  void _syncTimer(RoundModel round) {
    final elapsed = round.phaseStartedAt != null
        ? DateTime.now().difference(round.phaseStartedAt!)
        : Duration.zero;
    final remaining = const Duration(seconds: 30) - elapsed;
    _ref
        .read(timerProvider.notifier)
        .startFrom(remaining.inSeconds.clamp(0, 30));
  }

  Future<void> _checkEarlyAdvance(RoundModel round) async {
    if (round.state != RoundState.uniqueness) return;
    final amHost =
        await _ref.read(gameServiceProvider).isHost(_gameId);
    if (!amHost) return;

    final players = _ref
            .read(playersStreamProvider(_gameId))
            .whenOrNull(data: (p) => p) ??
        [];
    final active = players.where((p) => !p.isEliminated).length;
    if (active > 0 && round.readyPlayerIds.length >= active) {
      _phaseTimer?.cancel();
      await _advance(round);
    }
  }

  Future<void> _advance(RoundModel round) async {
    if (!mounted) return;
    final service = _ref.read(gameServiceProvider);

    if (round.state == RoundState.voting) {
      await service.settleVotingScores(_gameId, round.id);
    }
    if (round.state == RoundState.uniqueness) {
      await service.settleUniquenessScores(_gameId, round.id);
    }

    final next = _next(round.state);
    if (next != null) {
      await service.advanceRoundState(_gameId, round.id, next);
    }
  }

  RoundState? _next(RoundState s) {
    switch (s) {
      case RoundState.typing:
        return RoundState.voting;
      case RoundState.voting:
        return RoundState.uniqueness;
      case RoundState.uniqueness:
        return RoundState.results;
      default:
        return null;
    }
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    _sub.close();
    super.dispose();
  }
}

final phaseOrchestratorProvider = StateNotifierProvider.autoDispose
    .family<PhaseOrchestrator, void, String>(
        (ref, gameId) => PhaseOrchestrator(ref, gameId));

// ── Derived providers ─────────────────────────────────────────────────────────

final selfPlayerProvider =
    Provider.family<PlayerModel?, String>((ref, gameId) {
  final session = ref.watch(sessionProvider);
  return ref.watch(playersStreamProvider(gameId)).whenOrNull(
        data: (players) => players.cast<PlayerModel?>().firstWhere(
              (p) => p?.id == session.userId,
              orElse: () => null,
            ),
      );
});

final isEliminatedProvider =
    Provider.family<bool, String>((ref, gameId) =>
        ref.watch(selfPlayerProvider(gameId))?.isEliminated ?? false);

final leaderboardProvider =
    Provider.family<List<PlayerModel>, String>((ref, gameId) {
  return ref.watch(playersStreamProvider(gameId)).whenOrNull(
        data: (players) =>
            [...players]..sort((a, b) => b.score.compareTo(a.score)),
      ) ??
      [];
});

/// The current user's vote for a given target: null | 'up' | 'down'
final myVoteProvider = Provider.family<String?,
    ({String gameId, String targetPlayerId})>((ref, args) {
  final session = ref.watch(sessionProvider);
  return ref.watch(currentRoundProvider(args.gameId)).whenOrNull(
    data: (round) {
      if (round == null) return null;
      final sub = round.submissions.cast<PlayerSubmission?>().firstWhere(
            (s) => s?.playerId == args.targetPlayerId,
            orElse: () => null,
          );
      return sub?.votes[session.userId ?? ''];
    },
  );
});

/// Whether the current user has pressed "التالي" this round
final hasMarkedReadyProvider =
    Provider.family<bool, String>((ref, gameId) {
  final session = ref.watch(sessionProvider);
  return ref.watch(currentRoundProvider(gameId)).whenOrNull(
        data: (round) =>
            round?.readyPlayerIds
                .contains(session.userId ?? '') ??
            false,
      ) ??
      false;
});