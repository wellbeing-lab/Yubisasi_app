// Web では Azure Speech（web/azure_speech.js）を使い、それ以外では何もしない実装を使う。
export 'azure_speech_stub.dart'
    if (dart.library.js_interop) 'azure_speech_web.dart';
