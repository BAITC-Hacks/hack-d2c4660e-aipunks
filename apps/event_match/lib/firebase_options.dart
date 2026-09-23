import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Public Firebase app identifiers retrieved from the Firebase CLI.
/// These are client configuration, not an OpenAI key or server credentials.
class DefaultFirebaseOptions {
  static bool get isSupported =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android;

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    if (defaultTargetPlatform == TargetPlatform.android) return android;
    throw UnsupportedError('Firebase is configured for Web and Android only.');
  }

  static const web = FirebaseOptions(
    apiKey: 'AIzaSyC9LDtpO0Jjz9ENg4b9c0Sjm0EFItaxBOY',
    appId: '1:328723396096:web:288162fd9d9d0884074ae5',
    messagingSenderId: '328723396096',
    projectId: 'hackalem-84547',
    authDomain: 'hackalem-84547.firebaseapp.com',
    storageBucket: 'hackalem-84547.firebasestorage.app',
    measurementId: 'G-9661XBJ7LH',
  );

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyACH8JcNHE6NRYcF55WazsUwK8MmMWda74',
    appId: '1:328723396096:android:f4ae0749599db5e4074ae5',
    messagingSenderId: '328723396096',
    projectId: 'hackalem-84547',
    storageBucket: 'hackalem-84547.firebasestorage.app',
  );
}
