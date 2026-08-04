import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyC6m0TuTppWYVkP1eUp5qSwvoOLHLaumpo',
    appId: '1:193898349536:web:87c53bfe3c34320834e185',
    messagingSenderId: '193898349536',
    projectId: 'kindred-app-2fe7a',
    authDomain: 'kindred-app-2fe7a.firebaseapp.com',
    storageBucket: 'kindred-app-2fe7a.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCFu2NQ7YQd0qhN6k9qj3EytySo_revC10',
    appId: '1:193898349536:android:083917d82ca12bcc34e185',
    messagingSenderId: '193898349536',
    projectId: 'kindred-app-2fe7a',
    storageBucket: 'kindred-app-2fe7a.firebasestorage.app',
  );
}
