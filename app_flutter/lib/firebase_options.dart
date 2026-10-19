// lib/firebase_options.dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for postramblao project
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return ios;
      default:
        return android;
    }
  }

  // Cấu hình Web
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB6Sk10Xy9tIi4uYgdpT5ohyajr6863ybk',
    appId: '1:351954155486:web:4dbd4ecf4cff30f3a10f4f',
    messagingSenderId: '351954155486',
    projectId: 'postramblao',
    authDomain: 'postramblao.firebaseapp.com',
    databaseURL: 'https://postramblao-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'postramblao.firebasestorage.app',
    measurementId: 'G-5PTS5LFS8H',
  );

  // Cấu hình Android
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC5alAH_cSqcW-Z6i_eSmq0HRus7KFcbOo',
    appId: '1:351954155486:android:54e090fd7f7a7001a10f4f',
    messagingSenderId: '351954155486',
    projectId: 'postramblao',
    databaseURL: 'https://postramblao-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'postramblao.firebasestorage.app',
  );

  // Cấu hình iOS / macOS
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCL4h3G8gFDqiB1q60NGsgVpd-Dd09ZI0w',
    appId: '1:351954155486:ios:0bf6fcc7a080931ea10f4f',
    messagingSenderId: '351954155486',
    projectId: 'postramblao',
    databaseURL: 'https://postramblao-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'postramblao.firebasestorage.app',
    iosClientId: '351954155486-b39rgcl6tmfk3vv2q99qt5ho6lsrngnk.apps.googleusercontent.com',
    iosBundleId: 'com.tramblao.pos',
  );
}
