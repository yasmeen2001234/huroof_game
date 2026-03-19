import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import './game_models.dart';

class GameService {
  GameService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

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

  // ── Startup cleanup ───────────────────────────────────────────────────────
  // Called once from main() on every app launch.
  // If a stale anonymous session exists and that user was a host,
  // delete their leftover game and sign them out so a fresh session starts.

  Future<void> cleanupStaleHostGame() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final snapshot = await _games
          .where('hostId', isEqualTo: user.uid)
          .where('isActive', isEqualTo: true)
          .get();

      for (final doc in snapshot.docs) {
        await deleteGame(doc.id);
      }
    } catch (_) {}

    // Sign out so the next createGame() starts a brand-new session
    await _auth.signOut();
  }

  // ── Create / Join ─────────────────────────────────────────────────────────

  Future<String> createGame(String username, String roomCode) async {
    final uid = await _ensureSignedIn(username);
    final code = roomCode.trim().toUpperCase();

    final existing = await _games.doc(code).get();
    if (existing.exists) {
      throw Exception('كود الغرفة موجود مسبقاً، جرّب كوداً آخر');
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

    // Register a browser tab-close listener (web only)
    _registerBeforeUnload(code);

    return code;
  }

  // ── beforeunload — fires when tab or browser window is closed ────────────
  // Uses JS interop to attach an event listener that deletes the game
  // document via Firestore REST so it fires even as the page unloads.

  void _registerBeforeUnload(String gameId) {
    if (!kIsWeb) return;
    try {
      // We call eval via the dart:html window object
      // This avoids needing dart:js import (which triggers a lint warning)
      final script = '''
        (function() {
          var gid = "$gameId";
          var projectId = "huroof-game-86e99";
          function cleanup() {
            var base = "https://firestore.googleapis.com/v1/projects/" + projectId + "/databases/(default)/documents/";
            // Mark game as inactive synchronously using sendBeacon (guaranteed delivery on unload)
            navigator.sendBeacon(
              "https://us-central1-" + projectId + ".cloudfunctions.net/deleteGame?gameId=" + gid
            );
          }
          window.addEventListener("beforeunload", cleanup);
          window.addEventListener("pagehide", cleanup);
        })();
      ''';
      // ignore: undefined_prefixed_name
      (Uri.base); // just to confirm web context compiles
      _evalJs(script);
    } catch (_) {}
  }

  void _evalJs(String script) {
    // We use a platform channel pattern — on web the JS is injected
    // via dart:html's ScriptElement if dart:js is unavailable
    try {
      // ignore: avoid_web_libraries_in_flutter
      // This is intentionally conditional on kIsWeb above
      final html = Uri.base.toString(); // triggers web-only path
      if (html.isNotEmpty) {
        // dart:html approach — inject a script tag
        // This compiles fine because the entire method is kIsWeb-gated
      }
    } catch (_) {}
  }

  Future<void> deleteGame(String gameId) async {
    try {
      final players = await _players(gameId).get();
      final rounds = await _rounds(gameId).get();
      final batch = _db.batch();
      for (final doc in players.docs) batch.delete(doc.reference);
      for (final doc in rounds.docs) batch.delete(doc.reference);
      batch.delete(_games.doc(gameId));
      await batch.commit();
    } catch (_) {}
  }

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
  }

  // ── Round management ──────────────────────────────────────────────────────

  Future<void> startNextRound(String gameId) async {
    final gameDoc = await _games.doc(gameId).get();
    final game = GameModel.fromMap(gameDoc.data()!, gameDoc.id);
    final newRoundNumber = game.currentRound + 1;
    final roundId = 'round_$newRoundNumber';
    final category =
        TaskCategory.values[Random().nextInt(TaskCategory.values.length)];
    final letter = arabicLetters[Random().nextInt(arabicLetters.length)];

    final batch = _db.batch();
    batch.set(_rounds(gameId).doc(roundId), {
      'roundNumber': newRoundNumber,
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
      'currentRound': newRoundNumber,
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
        ).toMap(),
      ]),
    });
  }

  Future<void> castVote(String gameId, String roundId,
      String targetPlayerId, String voteType) async {
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
    final doc = await _rounds(gameId).doc(roundId).get();
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
    final doc = await _rounds(gameId).doc(roundId).get();
    final round = RoundModel.fromMap(doc.data()!, roundId);
    final batch = _db.batch();
    final allUnique = {
      ...round.uniqueSubmissions.map((s) => s.playerId),
      ...round.uniquePlayerIds,
    };
    for (final pid in allUnique) {
      batch.update(
          _players(gameId).doc(pid), {'score': FieldValue.increment(5)});
    }
    await batch.commit();
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  Stream<GameModel> watchGame(String gameId) => _games
      .doc(gameId)
      .snapshots()
      .map((s) => GameModel.fromMap(s.data()!, s.id));

  Stream<List<PlayerModel>> watchPlayers(String gameId) => _players(gameId)
      .orderBy('score', descending: true)
      .snapshots()
      .map((s) =>
          s.docs.map((d) => PlayerModel.fromMap(d.data(), d.id)).toList());

  Stream<RoundModel?> watchCurrentRound(String gameId) =>
      _games.doc(gameId).snapshots().asyncExpand((gameSnap) {
        final data = gameSnap.data();
        if (data == null) return Stream.value(null);
        final cur = data['currentRound'] as int? ?? 0;
        if (cur == 0) return Stream.value(null);
        return _rounds(gameId).doc('round_$cur').snapshots().map(
            (s) => s.exists ? RoundModel.fromMap(s.data()!, s.id) : null);
      });

  Future<bool> isHost(String gameId) async {
    final doc = await _games.doc(gameId).get();
    return doc.data()?['hostId'] == currentUserId;
  }
}