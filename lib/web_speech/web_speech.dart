// Web ではブラウザの音声認識を直接使い、それ以外では何もしない実装を使う。
export 'web_speech_stub.dart'
    if (dart.library.js_interop) 'web_speech_web.dart';
