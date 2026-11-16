/// Web 以外で使われる空の実装。
class AzureSpeechRecognizer {
  static bool get isAvailable => false;

  static void configure(String tokenUrl) {}

  static bool get hasFreshToken => false;

  static Future<void> prefetchToken() async {}

  void Function(String event, String detail)? onEvent;
  void Function(String text)? onPartial;
  void Function(String text)? onFinal;
  void Function(String code, String detail)? onError;

  bool start({required String lang, List<String> phrases = const []}) => false;

  void stop(void Function() onEnd) => onEnd();

  void abort() {}
}
