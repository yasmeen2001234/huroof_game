import 'package:cloud_firestore/cloud_firestore.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum RoundState { waiting, typing, voting, uniqueness, results }

enum TaskCategory { plant, animal, object }

extension TaskCategoryX on TaskCategory {
  String get arabicLabel {
    switch (this) {
      case TaskCategory.plant:
        return 'نبات';
      case TaskCategory.animal:
        return 'حيوان';
      case TaskCategory.object:
        return 'جماد';
    }
  }

  String get emoji {
    switch (this) {
      case TaskCategory.plant:
        return '🌱';
      case TaskCategory.animal:
        return '🦁';
      case TaskCategory.object:
        return '🪨';
    }
  }
}

// ---------------------------------------------------------------------------
// PlayerModel
// ---------------------------------------------------------------------------

class PlayerModel {
  final String id;
  final String username;
  final int score;
  final bool isEliminated;
  final bool isHost;
  final bool isOnline;
  final DateTime joinedAt;

  PlayerModel({
    required this.id,
    required this.username,
    this.score = 0,
    this.isEliminated = false,
    this.isHost = false,
    this.isOnline = true,
    required this.joinedAt,
  });

  factory PlayerModel.fromMap(Map<String, dynamic> map, String docId) {
    return PlayerModel(
      id: docId,
      username: map['username'] as String? ?? 'Unknown',
      score: map['score'] as int? ?? 0,
      isEliminated: map['isEliminated'] as bool? ?? false,
      isHost: map['isHost'] as bool? ?? false,
      isOnline: map['isOnline'] as bool? ?? true,
      joinedAt: (map['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'username': username,
        'score': score,
        'isEliminated': isEliminated,
        'isHost': isHost,
        'isOnline': isOnline,
        'joinedAt': Timestamp.fromDate(joinedAt),
      };
}

// ---------------------------------------------------------------------------
// PlayerSubmission
// ---------------------------------------------------------------------------

class PlayerSubmission {
  final String playerId;
  final String username;
  final String answer;

  /// voterId -> 'up' | 'down'   — overwritable so players can change vote
  final Map<String, String> votes;
  final DateTime submittedAt;

  PlayerSubmission({
    required this.playerId,
    required this.username,
    required this.answer,
    Map<String, String>? votes,
    required this.submittedAt,
  }) : votes = votes ?? {};

  int get upvotes => votes.values.where((v) => v == 'up').length;
  int get downvotes => votes.values.where((v) => v == 'down').length;
  bool get isEliminated => votes.isNotEmpty && downvotes > upvotes;

  factory PlayerSubmission.fromMap(Map<String, dynamic> map) {
    return PlayerSubmission(
      playerId: map['playerId'] as String,
      username: map['username'] as String? ?? '',
      answer: map['answer'] as String? ?? '',
      votes: Map<String, String>.from(map['votes'] as Map? ?? {}),
      submittedAt:
          (map['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'playerId': playerId,
        'username': username,
        'answer': answer,
        'votes': votes,
        'submittedAt': Timestamp.fromDate(submittedAt),
      };

  PlayerSubmission copyWith({Map<String, String>? votes}) => PlayerSubmission(
        playerId: playerId,
        username: username,
        answer: answer,
        votes: votes ?? this.votes,
        submittedAt: submittedAt,
      );
}

// ---------------------------------------------------------------------------
// RoundModel
// ---------------------------------------------------------------------------

class RoundModel {
  final String id;
  final int roundNumber;
  final TaskCategory category;
  final String letter;
  final RoundState state;
  final DateTime? phaseStartedAt;
  final List<PlayerSubmission> submissions;

  /// Map<voterId, List<targetPlayerId>>
  /// Each voter can pick multiple cards independently.
  final Map<String, List<String>> uniqueVotes;

  /// Players who pressed "التالي" in the uniqueness phase
  final List<String> readyPlayerIds;

  RoundModel({
    required this.id,
    required this.roundNumber,
    required this.category,
    required this.letter,
    required this.state,
    this.phaseStartedAt,
    List<PlayerSubmission>? submissions,
    Map<String, List<String>>? uniqueVotes,
    List<String>? readyPlayerIds,
  })  : submissions = submissions ?? [],
        uniqueVotes = uniqueVotes ?? {},
        readyPlayerIds = readyPlayerIds ?? [];

  /// How many voters picked a given targetPlayerId
  int uniqueVoteCountFor(String targetPlayerId) => uniqueVotes.values
      .where((picks) => picks.contains(targetPlayerId))
      .length;

  /// Did a specific voter pick a specific target?
  bool hasMyVoteFor(String voterId, String targetPlayerId) =>
      uniqueVotes[voterId]?.contains(targetPlayerId) ?? false;

  /// All targetPlayerIds picked by a specific voter
  List<String> myPicks(String voterId) =>
      List<String>.from(uniqueVotes[voterId] ?? []);

  /// Answers that appear exactly once across all submissions
  List<PlayerSubmission> get uniqueSubmissions {
    final freq = <String, int>{};
    for (final s in submissions) {
      final key = s.answer.trim().toLowerCase();
      freq[key] = (freq[key] ?? 0) + 1;
    }
    return submissions
        .where((s) => freq[s.answer.trim().toLowerCase()] == 1)
        .toList();
  }

  factory RoundModel.fromMap(Map<String, dynamic> map, String docId) {
    return RoundModel(
      id: docId,
      roundNumber: map['roundNumber'] as int? ?? 1,
      category: TaskCategory.values.firstWhere(
        (c) => c.name == map['category'],
        orElse: () => TaskCategory.plant,
      ),
      letter: map['letter'] as String? ?? 'أ',
      state: RoundState.values.firstWhere(
        (s) => s.name == map['state'],
        orElse: () => RoundState.waiting,
      ),
      phaseStartedAt: (map['phaseStartedAt'] as Timestamp?)?.toDate(),
      submissions: (map['submissions'] as List<dynamic>? ?? [])
          .map((s) => PlayerSubmission.fromMap(s as Map<String, dynamic>))
          .toList(),
      uniqueVotes: (map['uniqueVotes'] as Map? ?? {}).map(
          (k, v) => MapEntry(k as String, List<String>.from(v as List? ?? []))),
      readyPlayerIds: List<String>.from(map['readyPlayerIds'] as List? ?? []),
    );
  }

  Map<String, dynamic> toMap() => {
        'roundNumber': roundNumber,
        'category': category.name,
        'letter': letter,
        'state': state.name,
        'phaseStartedAt': phaseStartedAt != null
            ? Timestamp.fromDate(phaseStartedAt!)
            : FieldValue.serverTimestamp(),
        'submissions': submissions.map((s) => s.toMap()).toList(),
        'uniqueVotes': uniqueVotes,
        'readyPlayerIds': readyPlayerIds,
      };
}

// ---------------------------------------------------------------------------
// GameModel
// ---------------------------------------------------------------------------

class GameModel {
  final String id;
  final String hostId;
  final RoundState currentState;
  final int totalRounds;
  final int currentRound;
  final DateTime createdAt;
  final bool isActive;
  final int phaseDuration; // seconds per phase: 15, 30, 60, 90

  GameModel({
    required this.id,
    required this.hostId,
    required this.currentState,
    this.totalRounds = 5,
    this.currentRound = 0,
    required this.createdAt,
    this.isActive = true,
    this.phaseDuration = 30,
  });

  factory GameModel.fromMap(Map<String, dynamic> map, String docId) {
    return GameModel(
      id: docId,
      hostId: map['hostId'] as String? ?? '',
      currentState: RoundState.values.firstWhere(
        (s) => s.name == map['currentState'],
        orElse: () => RoundState.waiting,
      ),
      totalRounds: map['totalRounds'] as int? ?? 5,
      currentRound: map['currentRound'] as int? ?? 0,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isActive: map['isActive'] as bool? ?? true,
      phaseDuration: map['phaseDuration'] as int? ?? 30,
    );
  }

  Map<String, dynamic> toMap() => {
        'hostId': hostId,
        'currentState': currentState.name,
        'totalRounds': totalRounds,
        'currentRound': currentRound,
        'createdAt': Timestamp.fromDate(createdAt),
        'isActive': isActive,
        'phaseDuration': phaseDuration,
      };
}

// ---------------------------------------------------------------------------
// Arabic letters
// ---------------------------------------------------------------------------

const List<String> arabicLetters = [
  'أ',
  'ب',
  'ت',
  'ث',
  'ج',
  'ح',
  'خ',
  'د',
  'ذ',
  'ر',
  'ز',
  'س',
  'ش',
  'ص',
  'ض',
  'ط',
  'ظ',
  'ع',
  'غ',
  'ف',
  'ق',
  'ك',
  'ل',
  'م',
  'ن',
  'ه',
  'و',
  'ي',
];
