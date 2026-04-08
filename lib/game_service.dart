import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import './game_models.dart';

String _generateRoomCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  final rand = Random.secure();
  return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
}

class GameService {
  GameService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseDatabase? database,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _rtdb = database ?? FirebaseDatabase.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final FirebaseDatabase _rtdb;

  String get currentUserId => _auth.currentUser?.uid ?? '';

  // ── Auth ─────────────────────────────────────────────────────────────────

  Future<String> _ensureSignedIn(String username) async {
    if (_auth.currentUser != null) {
      await _auth.currentUser!.updateDisplayName(username);
      return _auth.currentUser!.uid;
    }
    final cred = await _auth.signInAnonymously();
    await cred.user?.updateDisplayName(username);
    return cred.user!.uid;
  }

  Future<void> cleanupStaleHostGame() async {
    try {
      await _auth.signOut();
    } catch (_) {}
  }

  // ── Firestore refs ────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _games =>
      _db.collection('games');
  CollectionReference<Map<String, dynamic>> _players(String gid) =>
      _games.doc(gid).collection('players');
  CollectionReference<Map<String, dynamic>> _rounds(String gid) =>
      _games.doc(gid).collection('rounds');

  // ── RTDB refs are defined inside the presence section below ─────────────

  // ── Create ────────────────────────────────────────────────────────────────

  Future<String> createGame(String username) async {
    final uid = await _ensureSignedIn(username);

    String code = _generateRoomCode();
    while ((await _games.doc(code).get()).exists) {
      code = _generateRoomCode();
    }

    final batch = _db.batch();
    batch.set(
        _games.doc(code),
        GameModel(
          id: code,
          hostId: uid,
          currentState: RoundState.waiting,
          totalRounds: 100,
          createdAt: DateTime.now(),
        ).toMap());
    batch.set(
        _players(code).doc(uid),
        PlayerModel(
          id: uid,
          username: username,
          isHost: true,
          joinedAt: DateTime.now(),
        ).toMap());
    await batch.commit();

    await _registerPresence(code, uid);
    return code;
  }

  // ── Join ──────────────────────────────────────────────────────────────────

  Future<void> joinGame(String gameId, String username) async {
    final uid = await _ensureSignedIn(username);
    final code = gameId.trim().toUpperCase();

    final doc = await _games.doc(code).get();
    if (!doc.exists) throw Exception('الغرفة غير موجودة: $code');

    await _players(code).doc(uid).set(PlayerModel(
          id: uid,
          username: username,
          joinedAt: DateTime.now(),
        ).toMap());

    await _registerPresence(code, uid);
  }

  // ── RTDB presence ─────────────────────────────────────────────────────────
  //
  // Structure:
  //   /presence/{gameId}/players/{uid} = true   ← each player's node
  //   /presence/{gameId}/dead          = true   ← written by last player onDisconnect
  //
  // Every player schedules TWO onDisconnect operations:
  //   1. Remove their own player node
  //   2. Set /presence/{gameId}/dead = true
  //
  // Why this works for the last player:
  //   When the last tab closes, Firebase server executes BOTH operations.
  //   The `dead` flag appears. All other clients are gone, but the server
  //   wrote it — and when ANY new client joins later they'll see it.
  //   More importantly: the Firestore game doc gets cleaned up via
  //   the watchPresence onChildRemoved for non-last players,
  //   and via the watchDead listener for the last player.

  DatabaseReference _playerRef(String gameId, String uid) =>
      _rtdb.ref('presence/$gameId/players/$uid');
  DatabaseReference _gameRef(String gameId) =>
      _rtdb.ref('presence/$gameId/players');
  DatabaseReference _deadRef(String gameId) =>
      _rtdb.ref('presence/$gameId/dead');

  Future<void> _registerPresence(String gameId, String uid) async {
    final playerRef = _playerRef(gameId, uid);
    final deadRef = _deadRef(gameId);

    // Clear any stale dead flag first
    await deadRef.remove();

    // Write our presence
    await playerRef.set(true);

    // When WE disconnect:
    //   1. Remove our node (fires onChildRemoved on other clients)
    //   2. Write dead=true (server-side, no client needed to observe)
    await playerRef.onDisconnect().remove();
    await deadRef.onDisconnect().set(true);
  }

  Future<void> leaveGame(String gameId) async {
    final uid = currentUserId;
    if (uid.isEmpty || gameId.isEmpty) return;

    try {
      await _playerRef(gameId, uid).onDisconnect().cancel();
      await _deadRef(gameId).onDisconnect().cancel();
      await _playerRef(gameId, uid).remove();
    } catch (_) {}

    try {
      await _players(gameId).doc(uid).delete();
    } catch (_) {}

    try {
      final remaining = await _players(gameId).get();
      if (remaining.docs.isEmpty) {
        await deleteGame(gameId);
      }
    } catch (_) {}
  }

  // ── Watch RTDB — two listeners ────────────────────────────────────────────
  //
  // Listener A — onChildRemoved on /presence/{gameId}/players:
  //   Fires on OTHER clients when a player's tab closes.
  //   Deletes that player's Firestore doc and checks if room is empty.
  //
  // Listener B — onValue on /presence/{gameId}/dead:
  //   Fires when the LAST player closes their tab (server writes dead=true).
  //   At this point no other clients exist, but the NEXT time anyone
  //   opens the app and tries to join this game, or if any client was
  //   briefly open, they clean it up.
  //   More crucially: if there are 2 players, player A leaves cleanly,
  //   player B is the last one — when B closes the tab, dead=true is set.
  //   Player A already left so their listener is gone. But the Firestore
  //   doc is cleaned up by leaveGame() when A left (empty check).
  //   So dead flag is mainly the safety net.

  List<StreamSubscription> watchPresence(
    String gameId,
    VoidCallback onEmpty,
  ) {
    final subs = <StreamSubscription>[];

    // Listener A: individual disconnects (non-last players)
    subs.add(_gameRef(gameId).onChildRemoved.listen((event) async {
      final uid = event.snapshot.key;
      if (uid == null) return;

      try {
        await _players(gameId).doc(uid).delete();
      } catch (_) {}

      try {
        final remaining = await _players(gameId).get();
        if (remaining.docs.isEmpty) onEmpty();
      } catch (_) {}
    }));

    // Listener B: dead flag (last player hard disconnect)
    subs.add(_deadRef(gameId).onValue.listen((event) async {
      if (event.snapshot.value == true) {
        // Last player disconnected — clean up everything
        try {
          await deleteGame(gameId);
        } catch (_) {}
        onEmpty();
      }
    }));

    return subs;
  }

  // Watch for the game document itself being deleted (room gone)
  StreamSubscription<DocumentSnapshot> watchGameDeleted(
    String gameId,
    VoidCallback onDeleted,
  ) {
    return _games.doc(gameId).snapshots().listen((snap) {
      if (!snap.exists) onDeleted();
    });
  }

  // ── Delete entire game ────────────────────────────────────────────────────

  Future<void> deleteGame(String gameId) async {
    try {
      final players = await _players(gameId).get();
      final rounds = await _rounds(gameId).get();
      final batch = _db.batch();
      for (final d in players.docs) {
        batch.delete(d.reference);
      }
      for (final d in rounds.docs) {
        batch.delete(d.reference);
      }
      batch.delete(_games.doc(gameId));
      await batch.commit();
    } catch (_) {}
    try {
      await _gameRef(gameId).remove();
    } catch (_) {}
  }

  // ── Round management ──────────────────────────────────────────────────────

  Future<void> startNextRound(String gameId) async {
    try {
      final gameDoc = await _games.doc(gameId).get();
      if (!gameDoc.exists) {
        return;
      }
      final game = GameModel.fromMap(gameDoc.data()!, gameDoc.id);
      final newNum = game.currentRound + 1;

      // Check if we've reached the maximum rounds
      if (newNum > game.totalRounds) {
        return; // Game over, don't start another round
      }

      final roundId = 'round_$newNum';

      // Read previous round to avoid repeating same category or letter
      String? prevCategory;
      String? prevLetter;
      if (game.currentRound > 0) {
        try {
          final prevDoc =
              await _rounds(gameId).doc('round_${game.currentRound}').get();
          if (prevDoc.exists) {
            prevCategory = prevDoc.data()?['category'] as String?;
            prevLetter = prevDoc.data()?['letter'] as String?;
          }
        } catch (_) {}
      }

      // Pick category — exclude previous round's category, then pick randomly from rest
      final availableCategories =
          TaskCategory.values.where((c) => c.name != prevCategory).toList();
      availableCategories.shuffle();
      final category = availableCategories.first;

      // Pick letter — exclude previous round's letter, then pick randomly from rest
      final availableLetters =
          arabicLetters.where((l) => l != prevLetter).toList();
      availableLetters.shuffle();
      final letter = availableLetters.first;

      // Reset isEliminated for ALL players — everyone plays each new round
      final playersSnap = await _players(gameId).get();
      final batch = _db.batch();
      for (final doc in playersSnap.docs) {
        batch.update(doc.reference, {'isEliminated': false});
      }

      batch.set(_rounds(gameId).doc(roundId), {
        'roundNumber': newNum,
        'category': category.name,
        'letter': letter,
        'state': RoundState.typing.name,
        'phaseStartedAt': FieldValue.serverTimestamp(),
        'submissions': [],
        'uniqueVotes': {},
        'readyPlayerIds': [],
        'skipVoters': [],
      });
      batch.update(_games.doc(gameId), {
        'currentState': RoundState.typing.name,
        'currentRound': newNum,
      });
      await batch.commit();
    } catch (e, st) {
      print('Error in startNextRound: $e\n$st');
    }
  }

  Future<void> advanceRoundState(
      String gameId, String roundId, RoundState newState) async {
    final batch = _db.batch();
    batch.update(_rounds(gameId).doc(roundId), {
      'state': newState.name,
      'phaseStartedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_games.doc(gameId), {'currentState': newState.name});
    await batch.commit();
  }

  // ── Player actions ────────────────────────────────────────────────────────

  Future<void> submitAnswer(
      String gameId, String roundId, String answer, int timeRemaining) async {
    final uid = currentUserId;
    final playerDoc = await _players(gameId).doc(uid).get();
    final player = PlayerModel.fromMap(playerDoc.data()!, playerDoc.id);
    final roundDoc = await _rounds(gameId).doc(roundId).get();
    final round = RoundModel.fromMap(roundDoc.data()!, roundDoc.id);
    if (round.submissions.any((s) => s.playerId == uid)) return;
    await _rounds(gameId).doc(roundId).update({
      'submissions': FieldValue.arrayUnion([
        PlayerSubmission(
          playerId: uid,
          username: player.username,
          answer: answer.trim(),
          submittedAt: DateTime.now(),
          timeRemaining: timeRemaining,
        ).toMap(),
      ]),
    });
  }

  Future<void> castVote(String gameId, String roundId, String targetPlayerId,
      String voteType) async {
    assert(voteType == 'up' || voteType == 'down');
    final voterId = currentUserId;
    if (voterId == targetPlayerId) {
      throw Exception('لا يمكنك التصويت على إجابتك');
    }
    final roundDoc = await _rounds(gameId).doc(roundId).get();
    final round = RoundModel.fromMap(roundDoc.data()!, roundDoc.id);
    final updated = round.submissions.map((s) {
      if (s.playerId == targetPlayerId) {
        final nv = Map<String, String>.from(s.votes)..[voterId] = voteType;
        return s.copyWith(votes: nv);
      }
      return s;
    }).toList();
    await _rounds(gameId).doc(roundId).update({
      'submissions': updated.map((s) => s.toMap()).toList(),
    });
  }

  /// Add targetPlayerId to this voter's picks list (multi-select).
  Future<void> voteUniqueWord(
      String gameId, String roundId, String targetPlayerId) async {
    final voterId = currentUserId;
    // Firestore arrayUnion on a nested list field
    await _rounds(gameId).doc(roundId).update({
      'uniqueVotes.$voterId': FieldValue.arrayUnion([targetPlayerId]),
    });
  }

  /// Remove targetPlayerId from this voter's picks list (deselect one).
  Future<void> removeUniqueVote(
      String gameId, String roundId, String targetPlayerId) async {
    final voterId = currentUserId;
    await _rounds(gameId).doc(roundId).update({
      'uniqueVotes.$voterId': FieldValue.arrayRemove([targetPlayerId]),
    });
  }

  Future<void> markReady(String gameId, String roundId) async {
    await _rounds(gameId).doc(roundId).update({
      'readyPlayerIds': FieldValue.arrayUnion([currentUserId]),
    });
  }

  Future<void> markSkip(String gameId, String roundId) async {
    await _rounds(gameId).doc(roundId).update({
      'skipVoters': FieldValue.arrayUnion([currentUserId]),
    });
  }

  // ── Score settling ────────────────────────────────────────────────────────

  Future<void> settleVotingScores(String gameId, String roundId) async {
    final doc = await _rounds(gameId).doc(roundId).get();
    final round = RoundModel.fromMap(doc.data()!, roundId);
    final batch = _db.batch();
    for (final sub in round.submissions) {
      final ref = _players(gameId).doc(sub.playerId);
      if (sub.isEliminated) {
        batch.update(ref, {'isEliminated': true});
      } else if (sub.upvotes > 0) {
        // +5 base + bonus for submitting quickly (timeRemaining ÷ 5)
        final total = 5 + sub.bonusPoints;
        batch.update(ref, {'score': FieldValue.increment(total)});
      } else if (sub.upvotes == 0 && sub.downvotes == 0) {
        // No votes received: automatic +5 points
        batch.update(ref, {'score': FieldValue.increment(5)});
      }
    }
    await batch.commit();
  }

  Future<void> settleUniquenessScores(String gameId, String roundId) async {
    final doc = await _rounds(gameId).doc(roundId).get();
    final round = RoundModel.fromMap(doc.data()!, roundId);
    final batch = _db.batch();

    // Count votes per targetPlayerId
    final voteCounts = <String, int>{};
    for (final picks in round.uniqueVotes.values) {
      for (final targetId in picks) {
        voteCounts[targetId] = (voteCounts[targetId] ?? 0) + 1;
      }
    }

    if (voteCounts.isNotEmpty) {
      // Find the highest vote count
      final maxVotes = voteCounts.values.reduce((a, b) => a > b ? a : b);

      // Only players whose word got the MOST votes get +5
      // (ties: all tied players get +5)
      for (final entry in voteCounts.entries) {
        if (entry.value == maxVotes) {
          batch.update(_players(gameId).doc(entry.key),
              {'score': FieldValue.increment(5)});
        }
      }
    }

    await batch.commit();
  }

  /// Eliminate players who didn't submit an answer before the timer ran out.
  Future<void> eliminateNonSubmitters(String gameId, String roundId) async {
    final roundDoc = await _rounds(gameId).doc(roundId).get();
    final round = RoundModel.fromMap(roundDoc.data()!, roundDoc.id);
    final playersDoc = await _players(gameId).get();

    final submittedIds = round.submissions.map((s) => s.playerId).toSet();
    final batch = _db.batch();

    for (final doc in playersDoc.docs) {
      final player = PlayerModel.fromMap(doc.data(), doc.id);
      // If not already eliminated AND didn't submit → eliminate
      if (!player.isEliminated && !submittedIds.contains(player.id)) {
        batch.update(doc.reference, {'isEliminated': true});
      }
    }

    await batch.commit();
  }

  /// Save draft answer as user types (without submitting)
  Future<void> saveDraftAnswer(
      String gameId, String roundId, String draft) async {
    final uid = currentUserId;
    if (uid.isEmpty) return;
    try {
      await _players(gameId).doc(uid).update({
        'draftAnswer': draft,
        'draftRoundId': roundId,
      });
    } catch (_) {}
  }

  /// Auto-submit drafts when timer expires in typing phase
  Future<void> autoSubmitDrafts(String gameId, String roundId) async {
    final playersSnap = await _players(gameId).get();
    final roundDoc = await _rounds(gameId).doc(roundId).get();
    if (!roundDoc.exists) return;
    final round = RoundModel.fromMap(roundDoc.data()!, roundDoc.id);
    final submittedIds = round.submissions.map((s) => s.playerId).toSet();

    final batch = _db.batch();
    for (final doc in playersSnap.docs) {
      final player = PlayerModel.fromMap(doc.data(), doc.id);
      if (player.draftAnswer != null &&
          player.draftRoundId == roundId &&
          player.draftAnswer!.trim().isNotEmpty &&
          !submittedIds.contains(player.id)) {
        batch.update(_rounds(gameId).doc(roundId), {
          'submissions': FieldValue.arrayUnion([
            PlayerSubmission(
              playerId: player.id,
              username: player.username,
              answer: player.draftAnswer!.trim(),
              submittedAt: DateTime.now(),
              timeRemaining: 0,
            ).toMap(),
          ]),
        });
      }
    }
    await batch.commit();
  }

  /// Check if all players are eliminated (including self)
  Future<bool> areAllPlayersEliminated(String gameId) async {
    try {
      final playersDoc = await _players(gameId).get();
      final activePlayers =
          playersDoc.docs.where((d) => !(d['isEliminated'] as bool)).length;
      return activePlayers == 0;
    } catch (_) {
      return false;
    }
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  Stream<GameModel> watchGame(String gameId) => _games
      .doc(gameId)
      .snapshots()
      .map((s) => GameModel.fromMap(s.data()!, s.id));

  Stream<List<PlayerModel>> watchPlayers(String gameId) =>
      _players(gameId).orderBy('score', descending: true).snapshots().map((s) =>
          s.docs.map((d) => PlayerModel.fromMap(d.data(), d.id)).toList());

  Stream<RoundModel?> watchCurrentRound(String gameId) {
    // switchMap: cancels previous inner stream when outer emits new value
    // asyncExpand does NOT cancel — causes stale round_1 to block round_2
    StreamSubscription? inner;
    late StreamController<RoundModel?> controller;

    controller = StreamController<RoundModel?>.broadcast(
      onCancel: () => inner?.cancel(),
    );

    _games.doc(gameId).snapshots().listen(
          (gameSnap) {
            final data = gameSnap.data();
            if (data == null) {
              controller.add(null);
              return;
            }
            final cur = data['currentRound'] as int? ?? 0;
            if (cur == 0) {
              controller.add(null);
              return;
            }

            // Cancel previous round listener before subscribing to new one
            inner?.cancel();

            inner = _rounds(gameId).doc('round_$cur').snapshots().listen(
              (roundSnap) {
                if (!controller.isClosed) {
                  controller.add(
                    roundSnap.exists
                        ? RoundModel.fromMap(roundSnap.data()!, roundSnap.id)
                        : null,
                  );
                }
              },
              onError: controller.addError,
            );
          },
          onError: controller.addError,
          onDone: () {
            inner?.cancel();
            controller.close();
          },
        );

    return controller.stream;
  }

  Future<void> updatePhaseDuration(String gameId, int seconds) async {
    await _games.doc(gameId).update({'phaseDuration': seconds});
  }

  /// Returns count of non-eliminated players. Used to skip uniqueness phase.
  Future<int> getActivePlayers(String gameId) async {
    final snap =
        await _players(gameId).where('isEliminated', isEqualTo: false).get();
    return snap.docs.length;
  }

  Future<bool> isHost(String gameId) async {
    final doc = await _games.doc(gameId).get();
    return doc.data()?['hostId'] == currentUserId;
  }
}
