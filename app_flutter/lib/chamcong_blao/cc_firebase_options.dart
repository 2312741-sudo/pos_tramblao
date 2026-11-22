// Cấu hình Firebase dự án chamcongtramblao (chép từ app chamcong_tramblao) — dùng cho mô-đun Chấm Công BLAO trong POS.
// File generated automatically for chamcongtramblao.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class CcFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'CcFirebaseOptions have not been configured for macos.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'CcFirebaseOptions have not been configured for windows.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'CcFirebaseOptions have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'CcFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCxW87rArTmuqORZbyuE9ey5Zc7PgWPLhQ',
    appId: '1:744729032681:web:28ccb45858b290db333d78',
    messagingSenderId: '744729032681',
    projectId: 'chamcongtramblao',
    authDomain: 'chamcongtramblao.firebaseapp.com',
    storageBucket: 'chamcongtramblao.firebasestorage.app',
    measurementId: 'G-3BPJQ9V47Y',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDc37-yRjEF3DYpEqd1Rj21ETzVtVVoPWI',
    appId: '1:744729032681:android:87102fc8cbae3a9e333d78',
    messagingSenderId: '744729032681',
    projectId: 'chamcongtramblao',
    storageBucket: 'chamcongtramblao.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAYOKRM4Vdbe1fiMzVBzkLUEjjjsXfjktg',
    appId: '1:744729032681:ios:86a4b04ddb0d412e333d78',
    messagingSenderId: '744729032681',
    projectId: 'chamcongtramblao',
    storageBucket: 'chamcongtramblao.firebasestorage.app',
    iosClientId: '744729032681-k9886g97cunj6srep0tdj0udt349e093.apps.googleusercontent.com',
    iosBundleId: 'com.tramblao.chamcong',
  );
}
