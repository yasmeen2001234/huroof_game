import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import './game_models.dart';

// ── Random room code generator (Among Us style: 6 uppercase letters) ─────────

String _generateRoomCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; // no I/O to avoid confusion
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

  // ── Refs ──────────────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _games =>
      _db.collection('games');
  CollectionReference<Map<String, dynamic>> _players(String gid) =>
      _games.doc(gid).collection('players');
  CollectionReference<Map<String, dynamic>> _rounds(String gid) =>
      _games.doc(gid).collection('rounds');

  // RTDB: one node per player per game
  DatabaseReference _playerPresenceRef(String gameId, String uid) =>
      _rtdb.ref('presence/$gameId/$uid');

  // RTDB: the whole game's presence bucket
  DatabaseReference _gamePresenceRef(String gameId) =>
      _rtdb.ref('presence/$gameId');

  // ── Startup: sign out stale session ──────────────────────────────────────

  Future<void> cleanupStaleHostGame() async {
    try { await _auth.signOut(); } catch (_) {}
  }

  // ── Create game — auto-generates room code ────────────────────────────────

  Future<String> createGame(String username) async {
    final uid = await _ensureSignedIn(username);

    // Generate a unique code (retry if collision)
    String code = _generateRoomCode();
    while ((await _games.doc(code).get()).exists) {
      code = _generateRoomCode();
    }

    await _games.doc(code).set(GameModel(
      id: code,
      hostId: uid,
      currentState: RoundState.waiting,
      totalRounds: 5,
      createdAt: DateTime.now(),
    ).toMap());

    await _players(code).doc(uid).set(PlayerModel(
      id: uid,
      username: username,
      isHost: true,
      joinedAt: DateTime.now(),
    ).toMap());

    // Register RTDB presence for this player
    await _registerPresence(code, uid);

    return code;
  }

  // ── Join game ─────────────────────────────────────────────────────────────

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

    // Register RTDB presence for this player
    await _registerPresence(code, uid);
  }

  // ── RTDB presence per player ──────────────────────────────────────────────
  //
  // Each player writes their own node: /presence/{gameId}/{uid} = true
  // onDisconnect removes their node.
  // A separate listener watches /presence/{gameId} — when it becomes
  // empty (all players gone), the Firestore game is deleted.
  //
  // This works for ANY disconnect: host, guest, crash, tab close, etc.

  Future<void> _registerPresence(String gameId, String uid) async {
    final ref = _playerPresenceRef(gameId, uid);

    // Mark self as present
    await ref.set(true);

    // Server will remove this node when WebSocket drops
    await ref.onDisconnect().remove();
  }

  // ── Watch game presence — called by ALL clients ───────────────────────────
  // Returns a subscription. Cancel it in dispose().
  // Fires onEmpty when /presence/{gameId} has no children left.

  StreamSubscription<DatabaseEvent> watchPresence(
    String gameId,
    VoidCallback onEmpty,
  ) {
    return _gamePresenceRef(gameId).onValue.listen((event) {
      final data = event.snapshot.value;
      // null or empty map = no players connected → delete the game
      if (data == null) {
        onEmpty();
        return;
      }
      if (data is Map && data.isEmpty) {
        onEmpty();
      }
    });
  }

  // ── Delete game ───────────────────────────────────────────────────────────

  Future<void> deleteGame(String gameId) async {
    try {
      final players = await _players(gameId).get();
      final rounds  = await _rounds(gameId).get();
      final batch   = _db.batch();
      for (final d in players.docs) batch.delete(d.reference);
      for (final d in rounds.docs)  batch.delete(d.reference);
      batch.delete(_games.doc(gameId));
      await batch.commit();
    } catch (_) {}
    try { await _gamePresenceRef(gameId).remove(); } catch (_) {}
  }

  // ── Remove self from presence (clean leave) ───────────────────────────────

  Future<void> leaveGame(String gameId) async {
    try {
      final uid = currentUserId;
      await _playerPresenceRef(gameId, uid).onDisconnect().cancel();
      await _playerPresenceRef(gameId, uid).remove();
    } catch (_) {}
  }

  // ── Round management ──────────────────────────────────────────────────────

  Future<void> startNextRound(String gameId) async {
    final gameDoc = await _games.doc(gameId).get();
    final game    = GameModel.fromMap(gameDoc.data()!, gameDoc.id);
    final newNum  = game.currentRound + 1;
    final roundId = 'round_$newNum';
    final category =
        TaskCategory.values[Random().nextInt(TaskCategory.values.length)];
    final letter = arabicLetters[Random().nextInt(arabicLetters.length)];

    final batch = _db.batch();
    batch.set(_rounds(gameId).doc(roundId), {
      'roundNumber': newNum,
      'category': category.name,
      'letter': letter,
      'state': RoundState.typing.name,
      'phaseStartedAt': FieldValue.serverTimestamp(),
      'submissions': [],
      'uniquePlayerIds': [],
      'readyPlayerIds': [],
    });
    batch.update(_games.doc(gameId), {
      'currentState': RoundState.typing.name,
      'currentRound': newNum,
    });
    await batch.commit();
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
      String gameId, String roundId, String answer) async {
    final uid       = currentUserId;
    final playerDoc = await _players(gameId).doc(uid).get();
    final player    = PlayerModel.fromMap(playerDoc.data()!, playerDoc.id);
    final roundDoc  = await _rounds(gameId).doc(roundId).get();
    final round     = RoundModel.fromMap(roundDoc.data()!, roundDoc.id);
    if (round.submissions.any((s) => s.playerId == uid)) return;
    await _rounds(gameId).doc(roundId).update({
      'submissions': FieldValue.arrayUnion([
        PlayerSubmission(
          playerId: uid,
          username: player.username,
          answer: answer.trim(),
          submittedAt: DateTime.now(),
        ).toMap(),
      ]),
    });
  }

  Future<void> castVote(String gameId, String roundId,
      String targetPlayerId, String voteType) async {
    assert(voteType == 'up' || voteType == 'down');
    final voterId = currentUserId;
    if (voterId == targetPlayerId) throw Exception('لا يمكنك التصويت على إجابتك');
    final roundDoc = await _rounds(gameId).doc(roundId).get();
    final round    = RoundModel.fromMap(roundDoc.data()!, roundDoc.id);
    final updated  = round.submissions.map((s) {
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

  Future<void> selectUniqueWord(
      String gameId, String roundId, String targetPlayerId) async {
    await _rounds(gameId).doc(roundId).update({
      'uniquePlayerIds': FieldValue.arrayUnion([targetPlayerId]),
    });
  }

  Future<void> markReady(String gameId, String roundId) async {
    await _rounds(gameId).doc(roundId).update({
      'readyPlayerIds': FieldValue.arrayUnion([currentUserId]),
    });
  }

  // ── Score settling ────────────────────────────────────────────────────────

  Future<void> settleVotingScores(String gameId, String roundId) async {
    final doc   = await _rounds(gameId).doc(roundId).get();
    final round = RoundModel.fromMap(doc.data()!, roundId);
    final batch = _db.batch();
    for (final sub in round.submissions) {
      final ref = _players(gameId).doc(sub.playerId);
      if (sub.isEliminated) {
        batch.update(ref, {'isEliminated': true});
      } else if (sub.upvotes > 0) {
        batch.update(ref, {'score': FieldValue.increment(5)});
      }
    }
    await batch.commit();
  }

  Future<void> settleUniquenessScores(String gameId, String roundId) async {
    final doc   = await _rounds(gameId).doc(roundId).get();
    final round = RoundModel.fromMap(doc.data()!, roundId);
    final batch = _db.batch();
    final allUnique = {
      ...round.uniqueSubmissions.map((s) => s.playerId),
      ...round.uniquePlayerIds,
    };
    for (final pid in allUnique) {
      batch.update(_players(gameId).doc(pid), {'score': FieldValue.increment(5)});
    }
    await batch.commit();
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  Stream<GameModel> watchGame(String gameId) => _games
      .doc(gameId).snapshots()
      .map((s) => GameModel.fromMap(s.data()!, s.id));

  Stream<List<PlayerModel>> watchPlayers(String gameId) =>
      _players(gameId).orderBy('score', descending: true).snapshots()
      .map((s) => s.docs.map((d) => PlayerModel.fromMap(d.data(), d.id)).toList());

  Stream<RoundModel?> watchCurrentRound(String gameId) =>
      _games.doc(gameId).snapshots().asyncExpand((snap) {
        final data = snap.data();
        if (data == null) return Stream.value(null);
        final cur = data['currentRound'] as int? ?? 0;
        if (cur == 0) return Stream.value(null);
        return _rounds(gameId).doc('round_$cur').snapshots()
            .map((s) => s.exists ? RoundModel.fromMap(s.data()!, s.id) : null);
      });

  Future<bool> isHost(String gameId) async {
    final doc = await _games.doc(gameId).get();
    return doc.data()?['hostId'] == currentUserId;
  }
}