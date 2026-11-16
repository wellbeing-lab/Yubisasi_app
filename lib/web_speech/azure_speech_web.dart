import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// web/azure_speech.js（window.yubisasiAzureSpeech）を呼ぶ Dart 側の窓口。
class AzureSpeechRecognizer {
  static JSObject? get _api =>
      globalContext.getProperty<JSObject?>('yubisasiAzureSpeech'.toJS);

  /// azure_speech.js と Azure Speech SDK の両方が読み込まれているか。
  static bool get isAvailable {
    final api = _api;
    if (api == null) return false;
    return api.callMethod<JSBoolean>('isAvailable'.toJS).toDart;
  }

  static void configure(String tokenUrl) {
    _api?.callMethod<JSAny?>('configure'.toJS, tokenUrl.toJS);
  }

  static bool get hasFreshToken =>
      _api?.callMethod<JSBoolean>('hasFreshToken'.toJS).toDart ?? false;

  /// トークンを先に取得しておく（失敗したら例外）。
  static Future<void> prefetchToken() async {
    final api = _api;
    if (api == null) throw StateError('azure_speech.js が読み込まれていません');
    await api.callMethod<JSPromise<JSAny?>>('prefetchToken'.toJS).toDart;
  }

  void Function(String event, String detail)? onEvent;
  void Function(String text)? onPartial;
  void Function(String text)? onFinal;
  void Function(String code, String detail)? onError;

  /// 認識を始める。ボタンを押した処理の中で、await を挟まずに呼ぶこと。
  bool start({required String lang, List<String> phrases = const []}) {
    final api = _api;
    if (api == null) {
      onError?.call('ScriptNotLoaded', 'azure_speech.js が読み込まれていません');
      return false;
    }
    final opts = JSObject()
      ..['lang'] = lang.toJS
      ..['phrases'] = phrases.map((p) => p.toJS).toList().toJS
      ..['onEvent'] = ((JSString event, JSString detail) {
        onEvent?.call(event.toDart, detail.toDart);
      }).toJS
      ..['onPartial'] = ((JSString text) {
        onPartial?.call(text.toDart);
      }).toJS
      ..['onFinal'] = ((JSString text) {
        onFinal?.call(text.toDart);
      }).toJS
      ..['onError'] = ((JSString code, JSString detail) {
        onError?.call(code.toDart, detail.toDart);
      }).toJS;
    return api.callMethod<JSBoolean>('start'.toJS, opts).toDart;
  }

  /// 認識を止める。最後の確定結果が届いてから onEnd が呼ばれる。
  void stop(void Function() onEnd) {
    final api = _api;
    if (api == null) {
      onEnd();
      return;
    }
    api.callMethod<JSAny?>('stop'.toJS, (() => onEnd()).toJS);
  }

  void abort() {
    _api?.callMethod<JSAny?>('abort'.toJS);
  }
}
