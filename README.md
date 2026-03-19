# حروف — Huroof: Arabic Letter Card Game
## Flutter + Firebase Multiplayer Implementation

---

## 📁 Project Structure

```
huroof_game/
├── lib/
│   ├── main.dart                        # App entry point + Firebase init
│   ├── models/
│   │   └── game_models.dart             # All data models (Game, Player, Round, Submission)
│   ├── services/
│   │   ├── game_service.dart            # Firestore CRUD + real-time streams
│   │   └── round_orchestrator.dart      # Host-side auto-advance + uniqueness algorithm
│   ├── providers/
│   │   └── game_providers.dart          # Riverpod providers (streams, session, timer)
│   ├── screens/
│   │   ├── home_screen.dart             # Home/Join + GameRouter
│   │   └── game_screens.dart            # Lobby, Typing, Voting, Uniqueness, Results
│   └── widgets/
│       └── game_widgets.dart            # VintageCard, SandWatchTimer, VoteButtons, etc.
├── firestore.rules                      # Production-ready security rules
└── pubspec.yaml
```

---

## 🏗 Firestore Data Schema

```
games/{gameId}
  ├── hostId          : String
  ├── currentState    : String   ("waiting"|"typing"|"voting"|"uniqueness"|"results")
  ├── totalRounds     : int
  ├── currentRound    : int
  ├── createdAt       : Timestamp
  ├── isActive        : bool
  │
  ├── players/{playerId}             ← sub-collection
  │   ├── username      : String
  │   ├── score         : int
  │   ├── isEliminated  : bool
  │   ├── isHost        : bool
  │   ├── isOnline      : bool
  │   └── joinedAt      : Timestamp
  │
  └── rounds/{roundId}               ← sub-collection
      ├── roundNumber   : int
      ├── category      : String     ("plant"|"animal"|"object")
      ├── letter        : String     single Arabic letter
      ├── state         : String
      ├── phaseStartedAt: Timestamp  ← server timestamp for timer sync
      ├── uniquePlayerIds: [String]  ← community-voted unique answers
      └── submissions   : [          ← array of player submission maps
            {
              playerId     : String,
              username     : String,
              answer       : String,
              votes        : { voterId: "up"|"down" },
              submittedAt  : Timestamp
            }
          ]
```

---

## 🎮 Game Flow

```
┌─────────────────────────────────────────────────────────────┐
│  LOBBY (waiting)                                             │
│  • Players join with room code                               │
│  • Host presses "Start" → startNextRound()                  │
└──────────────────┬──────────────────────────────────────────┘
                   │ 30 s
                   ▼
┌─────────────────────────────────────────────────────────────┐
│  TYPING PHASE                                                │
│  • Card revealed: category + random Arabic letter            │
│  • Each player types their answer                            │
│  • SandWatchTimer counts down from 30 s                      │
│  • Eliminated players see Spectator view                     │
└──────────────────┬──────────────────────────────────────────┘
                   │ 30 s
                   ▼
┌─────────────────────────────────────────────────────────────┐
│  VOTING PHASE                                                │
│  • All answers revealed on vintage cards                     │
│  • Players upvote ▲ or downvote ▼ each other                │
│  • GUARD: cannot vote own answer (buttons disabled)          │
│  • GUARD: cannot vote twice for same player (buttons greyed) │
│  • settleVotingScores() → upvoted +5pts, downvoted ELIMINATED│
└──────────────────┬──────────────────────────────────────────┘
                   │ 30 s
                   ▼
┌─────────────────────────────────────────────────────────────┐
│  UNIQUENESS PHASE                                            │
│  • Surviving players' answers shown as a grid               │
│  • Tap a card to vote it as "unique / unrepeated"            │
│  • System also auto-computes truly unique answers            │
│  • settleUniquenessScores() → unique word owner +5pts        │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│  RESULTS                                                     │
│  • Leaderboard displayed                                     │
│  • Host starts next round                                    │
└─────────────────────────────────────────────────────────────┘
```

---

## ⚡ Key Implementation Details

### Voting Guards (as required by PDF)

```dart
// In VoteButtons widget — buttons are conditionally disabled:
bool get _isSelf => targetPlayerId == currentUserId;
bool get _disabled => _isSelf || hasVoted;

// In GameService.castVote() — double-checked server-side:
if (voterId == targetPlayerId) throw Exception('Cannot vote for yourself.');
if (targetSub.votes.containsKey(voterId)) throw Exception('Already voted.');
```

### Elimination → Spectator View

```dart
// PlayerModel has isEliminated: bool flag
// When settleVotingScores() runs:
if (sub.isEliminated) {
  batch.update(playerRef, {'isEliminated': true});
}

// In every screen, eliminated players see:
if (isEliminated) return _SpectatorBanner();   // read-only, no input/vote
```

### Uniqueness Algorithm (pure, unit-testable)

```dart
List<String> computeUniquePlayerIds(List<PlayerSubmission> submissions) {
  final freq = <String, int>{};
  for (final s in submissions) {
    final key = s.answer.trim().toLowerCase();
    freq[key] = (freq[key] ?? 0) + 1;
  }
  return submissions
      .where((s) => freq[s.answer.trim().toLowerCase()] == 1)
      .map((s) => s.playerId)
      .toList();
}
```

### Timer Sync (server timestamp)

```dart
// RoundModel.phaseStartedAt is a Firestore SERVER timestamp.
// All clients subtract elapsed time to get remaining seconds:
final elapsed = DateTime.now().difference(round.phaseStartedAt!);
final remaining = Duration(seconds: 30) - elapsed;
ref.read(timerProvider.notifier).startFrom(remaining.inSeconds.clamp(0, 30));
```

---

## 🚀 Setup Instructions

### 1. Create Firebase Project

```bash
# Install Firebase CLI
npm install -g firebase-tools
firebase login

# Install FlutterFire CLI
dart pub global activate flutterfire_cli

# Inside huroof_game/
flutterfire configure
```

This generates `lib/firebase_options.dart`. Then in `main.dart`:

```dart
import 'firebase_options.dart';

await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);
```

### 2. Enable Firebase Services

In Firebase Console:
- **Authentication** → Anonymous sign-in ✅
- **Firestore** → Create database in production mode ✅

### 3. Deploy Security Rules

```bash
firebase deploy --only firestore:rules
```

### 4. Install Dependencies

```bash
flutter pub get
```

### 5. Run

```bash
flutter run
```

---

## 🔥 Production Upgrade: Cloud Functions

For production, move `RoundOrchestrator` logic to Cloud Functions so the server (not a player's device) advances round states:

```javascript
// functions/index.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

// Trigger: when a round's state changes to 'typing', start a 30s countdown
exports.advanceRoundOnTimer = functions.firestore
  .document('games/{gameId}/rounds/{roundId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    if (before.state === after.state) return;

    const phases = { typing: 'voting', voting: 'uniqueness', uniqueness: 'results' };
    const nextState = phases[after.state];
    if (!nextState) return;

    // Wait 30 seconds then advance
    await new Promise(resolve => setTimeout(resolve, 30_000));

    // Settle scores
    if (after.state === 'voting') await settleVotingScores(context.params.gameId, context.params.roundId);
    if (after.state === 'uniqueness') await settleUniquenessScores(context.params.gameId, context.params.roundId);

    await change.after.ref.update({ state: nextState, phaseStartedAt: admin.firestore.FieldValue.serverTimestamp() });
    await admin.firestore().doc(`games/${context.params.gameId}`).update({ currentState: nextState });
  });
```

---

## 📦 Dependencies

| Package | Purpose |
|---------|---------|
| `firebase_core` | Firebase initialization |
| `firebase_auth` | Anonymous authentication |
| `cloud_firestore` | Real-time database |
| `flutter_riverpod` | State management |
| `riverpod_annotation` | Code generation for providers |
| `google_fonts` | Amiri Quran Arabic font |
| `flutter_animate` | Card flip, fade, slide animations |
| `uuid` | Unique game room IDs |

---

## 🎨 Design System

| Token | Value | Usage |
|-------|-------|-------|
| `teal` | `#4FC3BF` | App background (from PDF) |
| `cardBg` | `#E8D5C4` | Vintage card background |
| `cardBorder` | `#3D2B1F` | Card borders, text |
| `gold` | `#D4A843` | Highlights, score chips |
| `upvote` | `#2ECC71` | Upvote button |
| `downvote` | `#E74C3C` | Downvote button, elimination |

Font: **Amiri Quran** for all Arabic text, **Orbitron** for scores/timer.
