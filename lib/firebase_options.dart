// File generated manually from the Firebase console's Web app config
// snippet (Project settings → Your apps → Web). These are the public
// client-side keys, not secrets — Firebase's own docs confirm this; real
// access control lives in firestore.rules and storage.rules.
//
// Only the `web` platform is configured: this app targets PWA only, no
// Android/iOS build. `currentPlatform` throws for any other platform.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    throw UnsupportedError(
      'DefaultFirebaseOptions solo está configurado para web. '
      'Plataforma actual: $defaultTargetPlatform.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCnMjY3nX4A45uTTnAAsfLoXomBe595FGY',
    appId: '1:839543437752:web:3a28975b9761c5e680774d',
    messagingSenderId: '839543437752',
    projectId: 'auditorias-taller',
    authDomain: 'auditorias-taller.firebaseapp.com',
    storageBucket: 'auditorias-taller.firebasestorage.app',
    measurementId: 'G-Z0PG7LBR4V',
  );
}
