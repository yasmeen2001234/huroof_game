import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import './game_widgets.dart';

class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  final _db = FirebaseFirestore.instance;
  bool _loading = true;
  String _error = '';

  // gameId -> list of player names
  Map<String, List<String>> _rooms = {};

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final gamesSnap = await _db.collection('games').get();
      final Map<String, List<String>> rooms = {};

      for (final gameDoc in gamesSnap.docs) {
        final gameId = gameDoc.id;
        final playersSnap = await _db
            .collection('games')
            .doc(gameId)
            .collection('players')
            .get();

        final names = playersSnap.docs
            .map((d) => d.data()['username'] as String? ?? '?')
            .toList();

        rooms[gameId] = names;
      }

      setState(() {
        _rooms = rooms;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _deleteRoom(String gameId) async {
    try {
      // Delete players
      final players =
          await _db.collection('games').doc(gameId).collection('players').get();
      // Delete rounds
      final rounds =
          await _db.collection('games').doc(gameId).collection('rounds').get();

      final batch = _db.batch();
      for (final d in players.docs) {
        batch.delete(d.reference);
      }
      for (final d in rounds.docs) {
        batch.delete(d.reference);
      }
      batch.delete(_db.collection('games').doc(gameId));
      await batch.commit();

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Deleted $gameId'), backgroundColor: Colors.green));
      _fetch();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _deleteAll() async {
    for (final gameId in _rooms.keys.toList()) {
      await _deleteRoom(gameId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        title: const Text('🛠 Debug — Room Inspector',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetch,
            tooltip: 'Refresh',
          ),
          if (_rooms.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
              label: const Text('Delete All',
                  style: TextStyle(color: Colors.redAccent)),
              onPressed: _deleteAll,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('❌ Error:\n$_error',
                      style: const TextStyle(color: Colors.redAccent)),
                ))
              : _rooms.isEmpty
                  ? const Center(
                      child: Text('✅ No rooms in database',
                          style: TextStyle(
                              color: Colors.greenAccent, fontSize: 18)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _rooms.length,
                      itemBuilder: (_, i) {
                        final gameId = _rooms.keys.elementAt(i);
                        final players = _rooms[gameId]!;
                        return Card(
                          color: const Color(0xFF16213E),
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(
                                  color: Color(0xFF4FC3BF), width: 1)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  const Text('🏠  ',
                                      style: TextStyle(fontSize: 18)),
                                  Text('Room: $gameId',
                                      style: GoogleFonts.orbitron(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 2)),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.redAccent),
                                    tooltip: 'Delete this room',
                                    onPressed: () => _deleteRoom(gameId),
                                  ),
                                ]),
                                const SizedBox(height: 8),
                                const Text('Players:',
                                    style: TextStyle(
                                        color: Color(0xFF4FC3BF),
                                        fontSize: 13)),
                                const SizedBox(height: 4),
                                if (players.isEmpty)
                                  const Text('  (no players)',
                                      style: TextStyle(
                                          color: Colors.white54, fontSize: 13))
                                else
                                  ...players.map((name) => Padding(
                                        padding: const EdgeInsets.only(
                                            left: 8, top: 2),
                                        child: Row(children: [
                                          const Text('👤  ',
                                              style: TextStyle(fontSize: 14)),
                                          Text(name,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14)),
                                        ]),
                                      )),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
