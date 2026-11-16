import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// ブラウザの音声認識（Web Speech API）を直接使う薄いラッパー。
///
/// speech_to_text の Web 版は SpeechRecognition を1つだけ作って使い回し、
/// continuous を partialResults と同じ値（true）に固定する。iOS Safari では
/// その組み合わせで2回目以降に結果が届かないため、ここでは
/// - セッションごとに新しい SpeechRecognition を作る
/// - continuous を個別に指定できる（既定は false）
/// - すべてのイベントを onEvent で通知する（調査用）
/// ようにしている。
class WebSpeechRecognizer {
  JSObject? _recognition;
  // 古いインスタンスのイベントを無視するための世代番号
  int _generation = 0;

  static bool get isSupported => _constructor() != null;

  static JSFunction? _constructor() =>
      globalContext.getProperty<JSFunction?>('SpeechRecognition'.toJS) ??
      globalContext.getProperty<JSFunction?>('webkitSpeechRecognition'.toJS);

  void Function(String event)? onEvent;
  void Function(String transcript, bool isFinal)? onResult;
  void Function(String error, String message)? onError;
  void Function()? onEnd;

  /// start してから end が来るまでの間 true。
  bool get isActive => _recognition != null;

  bool start({
    required String lang,
    required bool continuous,
    required bool interimResults,
  }) {
    abort();
    final ctor = _constructor();
    if (ctor == null) return false;

    final gen = ++_generation;
    bool current() => gen == _generation;

    final r = ctor.callAsConstructor<JSObject>();
    r['lang'] = lang.toJS;
    r['continuous'] = continuous.toJS;
    r['interimResults'] = interimResults.toJS;
    r['maxAlternatives'] = 1.toJS;

    for (final name in const [
      'start',
      'audiostart',
      'soundstart',
      'speechstart',
      'speechend',
      'soundend',
      'audioend',
      'nomatch',
    ]) {
      r['on$name'] = ((JSAny? _) {
        if (current()) onEvent?.call(name);
      }).toJS;
    }

    r['onresult'] = ((JSObject event) {
      if (!current()) return;
      final results = event.getProperty<JSObject>('results'.toJS);
      final length = results.getProperty<JSNumber>('length'.toJS).toDartInt;
      final buffer = StringBuffer();
      var isFinal = length > 0;
      for (var i = 0; i < length; i++) {
        final result = results.callMethod<JSObject>('item'.toJS, i.toJS);
        final alt = result.callMethod<JSObject>('item'.toJS, 0.toJS);
        buffer.write(alt.getProperty<JSString>('transcript'.toJS).toDart);
        if (!result.getProperty<JSBoolean>('isFinal'.toJS).toDart) {
          isFinal = false;
        }
      }
      onResult?.call(buffer.toString(), isFinal);
    }).toJS;

    r['onerror'] = ((JSObject event) {
      if (!current()) return;
      final error =
          event.getProperty<JSString?>('error'.toJS)?.toDart ?? 'unknown';
      final message =
          event.getProperty<JSString?>('message'.toJS)?.toDart ?? '';
      onError?.call(error, message);
    }).toJS;

    r['onend'] = ((JSAny? _) {
      if (!current()) return;
      _recognition = null;
      onEnd?.call();
    }).toJS;

    _recognition = r;
    try {
      r.callMethod<JSAny?>('start'.toJS);
      return true;
    } catch (e) {
      _recognition = null;
      _generation++;
      onError?.call('start-failed', e.toString());
      return false;
    }
  }

  /// 認識を止める（最終結果と end はこの後に届く）。
  void stop() {
    try {
      _recognition?.callMethod<JSAny?>('stop'.toJS);
    } catch (_) {}
  }

  /// 認識を中断し、以後このインスタンスのイベントは無視する。
  void abort() {
    final r = _recognition;
    _recognition = null;
    _generation++;
    if (r == null) return;
    try {
      r.callMethod<JSAny?>('abort'.toJS);
    } catch (_) {}
  }
}
