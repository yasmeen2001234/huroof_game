import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import './game_models.dart';
import './game_service.dart';

// ── Service ───────────────────────────────────────────────────────────────────

final gameServiceProvider = Provider<GameService>((ref) => GameService());

// ── Session ───────────────────────────────────────────────────────────────────

class SessionState {
  final String? gameId;
  final String? userId;
  final String? username;
  const SessionState({this.gameId, this.userId, this.username});
  SessionState copyWith({String? gameId, String? userId, String? username}) =>
      SessionState(
        gameId: gameId ?? this.gameId,
        userId: userId ?? this.userId,
        username: username ?? this.username,
      );
}

class SessionNotifier extends StateNotifier<SessionState> {
  SessionNotifier() : super(const SessionState());
  void setSession(
          {required String gameId,
          required String userId,
          required String username}) =>
      state =
          state.copyWith(gameId: gameId, userId: userId, username: username);
  void clear() => state = const SessionState();
}

final sessionProvider = StateNotifierProvider<SessionNotifier, SessionState>(
    (ref) => SessionNotifier());

// ── Firestore streams ─────────────────────────────────────────────────────────

final gameStreamProvider = StreamProvider.family<GameModel, String>(
    (ref, gameId) => ref.watch(gameServiceProvider).watchGame(gameId));

final playersStreamProvider = StreamProvider.family<List<PlayerModel>, String>(
    (ref, gameId) => ref.watch(gameServiceProvider).watchPlayers(gameId));

final currentRoundProvider = StreamProvider.family<RoundModel?, String>(
    (ref, gameId) => ref.watch(gameServiceProvider).watchCurrentRound(gameId));

// ── Timer ─────────────────────────────────────────────────────────────────────
// NOT autoDispose — keeps ticking across rebuilds within the same game session.

class TimerNotifier extends StateNotifier<int> {
  TimerNotifier() : super(30);
  Timer? _timer;
  String? _activePhaseKey; // tracks which phase the timer is for

  void startPhase(String phaseKey, int seconds) {
    if (_activePhaseKey == phaseKey) return;
    _activePhaseKey = phaseKey;
    _timer?.cancel();
    state = seconds.clamp(0, 999);
    if (state <= 0) return;
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

// Use family keyed by gameId — one timer per game, persists across rebuilds
final timerProvider = StateNotifierProvider.family<TimerNotifier, int, String>(
    (ref, gameId) => TimerNotifier());

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
    if (round.state == RoundState.waiting) return;

    // Cancel any pending timer when results phase hit or new round detected
    if (round.state == RoundState.results) {
      _phaseTimer?.cancel();
      _lastPhaseKey = null;
      return;
    }

    final phaseKey = '${round.id}:${round.state.name}';

    // Sync the UI timer for all clients
    _syncTimer(round, phaseKey);

    if (_lastPhaseKey == phaseKey) {
      // Same phase update — check early advance for uniqueness
      await _checkEarlyAdvance(round);
      return;
    }

    // New phase detected
    _lastPhaseKey = phaseKey;
    _phaseTimer?.cancel();

    final amHost = await _ref.read(gameServiceProvider).isHost(_gameId);
    if (!amHost) return;

    // Calculate remaining seconds from server timestamp
    final secs = _remainingSecs(round);

    if (secs <= 0) {
      await _advance(round);
    } else {
      _phaseTimer = Timer(Duration(seconds: secs), () => _advance(round));
    }
  }

  int _remainingSecs(RoundModel round) {
    // Read phaseDuration from live game stream
    final duration = _ref
            .read(gameStreamProvider(_gameId))
            .whenOrNull(data: (g) => g.phaseDuration) ??
        30;
    if (round.phaseStartedAt == null) return duration;
    final elapsed = DateTime.now().difference(round.phaseStartedAt!);
    return (duration - elapsed.inSeconds).clamp(0, duration);
  }

  void _syncTimer(RoundModel round, String phaseKey) {
    final secs = _remainingSecs(round);
    _ref.read(timerProvider(_gameId).notifier).startPhase(phaseKey, secs);
  }

  Future<void> _checkEarlyAdvance(RoundModel round) async {
    final amHost = await _ref.read(gameServiceProvider).isHost(_gameId);
    if (!amHost) return;
    final players =
        _ref.read(playersStreamProvider(_gameId)).whenOrNull(data: (p) => p) ??
            [];
    final active = players.where((p) => !p.isEliminated).length;

    // If all players are eliminated, end the game immediately
    if (active == 0) {
      _phaseTimer?.cancel();
      await _ref
          .read(gameServiceProvider)
          .advanceRoundState(_gameId, round.id, RoundState.results);
      return;
    }

    if (round.state == RoundState.uniqueness) {
      if (active > 0 && round.readyPlayerIds.length >= active) {
        _phaseTimer?.cancel();
        await _advance(round);
      }
    } else if (round.state == RoundState.voting) {
      if (active > 0 && round.skipVoters.length >= active) {
        _phaseTimer?.cancel();
        await _advance(round);
      }
    }
  }

  Future<void> _advance(RoundModel round) async {
    if (!mounted) return;
    final service = _ref.read(gameServiceProvider);

    if (round.state == RoundState.typing) {
      // Auto-submit any saved drafts before eliminating non-submitters
      await service.autoSubmitDrafts(_gameId, round.id);

      // Eliminate players who never submitted before time ran out
      await service.eliminateNonSubmitters(_gameId, round.id);

      // Check if all players are eliminated after typing
      final allEliminated = await service.areAllPlayersEliminated(_gameId);
      if (allEliminated) {
        await service.advanceRoundState(_gameId, round.id, RoundState.results);
        return;
      }
    }

    if (round.state == RoundState.voting) {
      await service.settleVotingScores(_gameId, round.id);

      // If all active players agreed to skip voting, go to uniqueness phase
      final activePlayers = await service.getActivePlayers(_gameId);
      if (round.skipVoters.length >= activePlayers) {
        await service.advanceRoundState(
            _gameId, round.id, RoundState.uniqueness);
        return;
      }

      // If no active players remain, go to result
      if (activePlayers == 0) {
        await service.advanceRoundState(_gameId, round.id, RoundState.results);
        return;
      }
    }

    if (round.state == RoundState.uniqueness) {
      await service.settleUniquenessScores(_gameId, round.id);

      // Check if all players are eliminated after uniqueness
      final allEliminated = await service.areAllPlayersEliminated(_gameId);
      if (allEliminated) {
        await service.advanceRoundState(_gameId, round.id, RoundState.results);
        return;
      }
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

final selfPlayerProvider = Provider.family<PlayerModel?, String>((ref, gameId) {
  final session = ref.watch(sessionProvider);
  return ref.watch(playersStreamProvider(gameId)).whenOrNull(
        data: (players) => players
            .cast<PlayerModel?>()
            .firstWhere((p) => p?.id == session.userId, orElse: () => null),
      );
});

final isEliminatedProvider = Provider.family<bool, String>((ref, gameId) =>
    ref.watch(selfPlayerProvider(gameId))?.isEliminated ?? false);

final leaderboardProvider =
    Provider.family<List<PlayerModel>, String>((ref, gameId) {
  return ref.watch(playersStreamProvider(gameId)).whenOrNull(
            data: (players) =>
                [...players]..sort((a, b) => b.score.compareTo(a.score)),
          ) ??
      [];
});

final myVoteProvider =
    Provider.family<String?, ({String gameId, String targetPlayerId})>(
        (ref, args) {
  final session = ref.watch(sessionProvider);
  return ref.watch(currentRoundProvider(args.gameId)).whenOrNull(
    data: (round) {
      if (round == null) return null;
      final sub = round.submissions.cast<PlayerSubmission?>().firstWhere(
          (s) => s?.playerId == args.targetPlayerId,
          orElse: () => null);
      return sub?.votes[session.userId ?? ''];
    },
  );
});

final hasMarkedReadyProvider = Provider.family<bool, String>((ref, gameId) {
  final session = ref.watch(sessionProvider);
  return ref.watch(currentRoundProvider(gameId)).whenOrNull(
            data: (round) =>
                round?.readyPlayerIds.contains(session.userId ?? '') ?? false,
          ) ??
      false;
});

final myUniquePicksProvider =
    Provider.family<List<String>, String>((ref, gameId) {
  final session = ref.watch(sessionProvider);
  return ref.watch(currentRoundProvider(gameId)).whenOrNull(
            data: (round) => round?.myPicks(session.userId ?? '') ?? [],
          ) ??
      [];
});

/// Whether the current user is the host of [gameId].
/// Derived from the game stream — no async needed.
final isHostProvider = Provider.family<bool, String>((ref, gameId) {
  final session = ref.watch(sessionProvider);
  return ref.watch(gameStreamProvider(gameId)).whenOrNull(
            data: (game) => game.hostId == session.userId,
          ) ??
      false;
});

/// Current phase duration setting (15/30/60/90s)
final phaseDurationProvider = Provider.family<int, String>((ref, gameId) {
  return ref.watch(gameStreamProvider(gameId)).whenOrNull(
            data: (game) => game.phaseDuration,
          ) ??
      30;
});
