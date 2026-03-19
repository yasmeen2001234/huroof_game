import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBySPdzAXkwaZ6etF7RM-yW5zXWbaCNULg',
    appId: '1:95841834900:web:24041e59e26fc60f282181',
    messagingSenderId: '95841834900',
    projectId: 'huroof-game-86e99',
    authDomain: 'huroof-game-86e99.firebaseapp.com',
    storageBucket: 'huroof-game-86e99.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBySPdzAXkwaZ6etF7RM-yW5zXWbaCNULg',
    appId: '1:95841834900:web:24041e59e26fc60f282181',
    messagingSenderId: '95841834900',
    projectId: 'huroof-game-86e99',
    storageBucket: 'huroof-game-86e99.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBySPdzAXkwaZ6etF7RM-yW5zXWbaCNULg',
    appId: '1:95841834900:web:24041e59e26fc60f282181',
    messagingSenderId: '95841834900',
    projectId: 'huroof-game-86e99',
    storageBucket: 'huroof-game-86e99.firebasestorage.app',
    iosBundleId: 'com.example.huruofGame',
  );
}