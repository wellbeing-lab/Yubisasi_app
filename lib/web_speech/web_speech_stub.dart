/// Web 以外で使われる空の実装（ネイティブは speech_to_text を使う）。
class WebSpeechRecognizer {
  static bool get isSupported => false;

  void Function(String event)? onEvent;
  void Function(String transcript, bool isFinal)? onResult;
  void Function(String error, String message)? onError;
  void Function()? onEnd;

  bool get isActive => false;

  bool start({
    required String lang,
    required bool continuous,
    required bool interimResults,
  }) =>
      false;

  void stop() {}

  void abort() {}
}
