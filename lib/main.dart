import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'firebase_options.dart';
import './home_screen.dart';
import './game_service.dart';
import './game_widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // On every launch: if this browser session was previously a host,
  // delete that stale game and sign out so no ghost rooms linger.
  await GameService().cleanupStaleHostGame();

  runApp(const ProviderScope(child: HuruufApp()));
}

class HuruufApp extends StatelessWidget {
  const HuruufApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'حروف',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: HuruufColors.teal,
          brightness: Brightness.light,
        ),
        textTheme: GoogleFonts.amiriTextTheme(),
        scaffoldBackgroundColor: HuruufColors.teal,
      ),
      home: HomeScreen(),
    );
  }
}