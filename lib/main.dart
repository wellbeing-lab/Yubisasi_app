import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:async';
import 'phrase_registration_screen.dart';
import 'web_speech/web_speech.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// ビルド時に CI から渡される版（git のコミット）。手元のビルドでは 'dev'
const String _appVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '指さし会話帳アプリ',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MainMenuScreen(),
    );
  }
}

// チャットメッセージの型定義
class ChatMessage {
  final String text;
  final bool isPartner; // true: 相手(青), false: 自分(ピンク)

  ChatMessage({required this.text, required this.isPartner});
}

// 1枚目：メインメニュー画面
class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  '指さし会話帳アプリ版',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),
                _buildMenuButton(
                  context,
                  icon: Icons.front_hand_outlined,
                  label: '指さし会話アプリ',
                  color: const Color(0xFF2F80ED),
                  textColor: Colors.white,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PointingConversationScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                _buildMenuButton(
                  context,
                  icon: Icons.format_list_bulleted,
                  label: '語句登録画面',
                  color: Colors.white,
                  textColor: Colors.black87,
                  borderColor: Colors.black12,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PhraseRegistrationScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                _buildMenuButton(
                  context,
                  icon: Icons.history,
                  label: 'トーク履歴',
                  color: Colors.white,
                  textColor: Colors.black87,
                  borderColor: Colors.black12,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required Color textColor,
    Color? borderColor,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: borderColor != null
                ? BorderSide(color: borderColor)
                : BorderSide.none,
          ),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: textColor),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 2枚目：指さし会話画面
class PointingConversationScreen extends StatefulWidget {
  const PointingConversationScreen({super.key});

  @override
  State<PointingConversationScreen> createState() =>
      _PointingConversationScreenState();
}

class _PointingConversationScreenState
    extends State<PointingConversationScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();

  // speech_to_text はアプリ全体で1つのインスタンスを共有する（initialize も初回のみ有効）
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;
  // 試す言語指定の候補と、今何番目を試しているか
  List<String> _localeCandidates = const [];
  int _localeAttempt = 0;
  // 認識セッションの番号（古いセッションのコールバックを無視するため）
  int _speechSessionId = 0;
  bool _receivedSpeechResult = false;
  // 別の言語指定で再試行する準備中（直前のセッションの done を無視する）
  bool _speechRetryPending = false;
  // 認識エンジンが前のセッションをまだ終えていない（done 待ち）
  bool _speechEngineBusy = false;
  Completer<void>? _speechEngineIdle;
  // Web ではブラウザの音声認識を直接使う（speech_to_text は使わない）
  final WebSpeechRecognizer _webSpeech = WebSpeechRecognizer();
  Completer<void>? _webSpeechEnded;
  Timer? _webAudioWatchdog;
  bool _webAudioStarted = false;
  bool _isOpponentMode = false;
  String _recognizedText = '';

  // 音声認識の調査用ログ（画面に表示し、コピーできるようにする）
  final List<String> _speechLogs = [];
  static const int _maxSpeechLogs = 100;

  Map<String, List<String>> _customPhrasesMap = {};
  String _selectedSubCategory = '目的';
  String _selectedMainTab = '身体情報';

  @override
  void initState() {
    super.initState();
    _loadCustomPhrasesForChat();
  }

  @override
  void dispose() {
    _webAudioWatchdog?.cancel();
    if (kIsWeb) {
      _webSpeech.abort();
    } else {
      // 共有インスタンスなので、この画面のコールバックを外してから止める
      _speech.statusListener = null;
      _speech.errorListener = null;
      if (_isListening) {
        _speech.cancel();
      }
    }
    _textController.dispose();
    super.dispose();
  }

  // メッセージ送信処理
  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(
        ChatMessage(
          text: text,
          isPartner: _isOpponentMode,
        ),
      );
      _textController.clear();
      _isOpponentMode = false;
    });
  }

  // 音声認識のログを1行追加する（画面表示とコンソール出力）
  void _addSpeechLog(String message) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final line =
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.${now.millisecond.toString().padLeft(3, '0')} $message';
    debugPrint('[speech] $line');
    if (!mounted) return;
    setState(() {
      _speechLogs.add(line);
      if (_speechLogs.length > _maxSpeechLogs) {
        _speechLogs.removeAt(0);
      }
    });
  }

  String _speechLogText() {
    final header = [
      '指さし会話 音声ログ',
      'version: $_appVersion',
      'platform: ${kIsWeb ? 'web' : 'native'} / ${defaultTargetPlatform.name}',
      'exported: ${DateTime.now().toIso8601String()}',
      '',
    ];
    return [...header, ..._speechLogs].join('\n');
  }

  Future<void> _copySpeechLogs() async {
    await Clipboard.setData(ClipboardData(text: _speechLogText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('音声ログをコピーしました')),
    );
  }

  void _showSpeechLogDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('音声ログ'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: _speechLogs.isEmpty
              ? const Center(child: Text('ログはまだありません'))
              : SingleChildScrollView(
                  reverse: true,
                  child: SelectableText(
                    _speechLogText(),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _speechLogs.clear());
              Navigator.of(context).pop();
            },
            child: const Text('消去'),
          ),
          TextButton(
            onPressed: _copySpeechLogs,
            child: const Text('コピー'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  // マイクボタン：認識中なら停止、そうでなければ開始
  Future<void> _listenSpeech() async {
    if (_isListening) {
      _addSpeechLog('停止ボタン押下 (recognizedText="$_recognizedText")');
      if (kIsWeb) {
        _webSpeech.stop();
        _addSpeechLog('stop() 呼び出し');
      } else {
        try {
          await _speech.stop();
          _addSpeechLog('stop() 完了');
        } catch (e) {
          _addSpeechLog('stop() 例外: $e');
        }
      }
      _finishListening('停止ボタン');
      return;
    }

    _addSpeechLog('---- マイクボタン押下：開始 (version $_appVersion) ----');

    if (kIsWeb) {
      await _startWebListening();
      return;
    }

    if (!_speechAvailable) {
      try {
        _speechAvailable = await _speech.initialize(
          onStatus: _onSpeechStatus,
          onError: _onSpeechError,
        );
      } catch (e) {
        _addSpeechLog('initialize() 例外: $e');
      }
      _addSpeechLog('initialize() 結果: available=$_speechAvailable');
    }
    if (!_speechAvailable) {
      _showSpeechMessage('この環境では音声入力が使えません。'
          'iPhone では Safari で開いてください。'
          'キーボードのマイクボタンからの音声入力も使えます。');
      return;
    }
    // 共有インスタンスなので、毎回この画面のコールバックを付け直す
    _speech.statusListener = _onSpeechStatus;
    _speech.errorListener = _onSpeechError;

    await _prepareSpeechEngine();

    _localeCandidates = await _speechLocaleCandidates();
    _localeAttempt = 0;
    _addSpeechLog('言語指定の候補: $_localeCandidates');
    await _startListeningAttempt();
  }

  // Web：ブラウザの音声認識を直接使って1回分の認識を始める。
  // iOS Safari では speech_to_text 経由（continuous=true・使い回し）だと
  // 2回目以降に結果が届かないため、毎回新しく作り continuous=false で使う。
  Future<void> _startWebListening() async {
    if (!WebSpeechRecognizer.isSupported) {
      _addSpeechLog('このブラウザは SpeechRecognition に対応していません');
      _showSpeechMessage('この環境では音声入力が使えません。'
          'iPhone では Safari で開いてください。'
          'キーボードのマイクボタンからの音声入力も使えます。');
      return;
    }

    if (_webSpeech.isActive) {
      _addSpeechLog('前のセッションの終了待ち…');
      final ended = _webSpeechEnded ??= Completer<void>();
      try {
        await ended.future.timeout(const Duration(seconds: 2));
        _addSpeechLog('前のセッションが終了しました');
      } on TimeoutException {
        _addSpeechLog('終了待ちがタイムアウト。abort() します');
        _webSpeech.abort();
      }
    }

    final sessionId = ++_speechSessionId;
    _receivedSpeechResult = false;
    _webAudioStarted = false;

    _webSpeech
      ..onEvent = (name) {
        _addSpeechLog('event #$sessionId: $name');
        if (name == 'audiostart') _webAudioStarted = true;
      }
      ..onResult = (text, isFinal) {
        _addSpeechLog('onResult #$sessionId: "$text" (final=$isFinal)');
        if (sessionId != _speechSessionId || !_isListening) return;
        if (text.isEmpty) return;
        _receivedSpeechResult = true;
        setState(() {
          _recognizedText = text;
          _textController.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
        });
      }
      ..onError = (code, message) {
        _addSpeechLog('onError #$sessionId: $code ${message.isEmpty ? '' : '($message)'}');
        if (sessionId != _speechSessionId) return;
        _finishListening('onError: $code');
        final text = _speechErrorMessage(code);
        if (text != null) _showSpeechMessage(text);
      }
      ..onEnd = () {
        _addSpeechLog('event #$sessionId: end');
        final ended = _webSpeechEnded;
        _webSpeechEnded = null;
        if (ended != null && !ended.isCompleted) ended.complete();
        if (sessionId == _speechSessionId) {
          _finishListening('end');
        }
      };

    setState(() {
      _isListening = true;
      _recognizedText = '';
    });

    final ok = _webSpeech.start(
      lang: 'ja-JP',
      continuous: false,
      interimResults: true,
    );
    _addSpeechLog('start() #$sessionId: $ok (lang=ja-JP, continuous=false)');
    if (!ok) {
      _finishListening('start() 失敗');
      return;
    }

    // マイクの音が届いているか（audiostart が来るか）を確認する
    _webAudioWatchdog?.cancel();
    _webAudioWatchdog = Timer(const Duration(seconds: 4), () {
      if (sessionId == _speechSessionId && _isListening && !_webAudioStarted) {
        _addSpeechLog('警告 #$sessionId: 4秒たっても audiostart が来ていません'
            '（マイクの音が認識に届いていない可能性）');
      }
    });
  }

  // ネイティブ：前のセッションが終わるのを待つ
  Future<void> _prepareSpeechEngine() async {
    if (_speechEngineBusy) {
      _addSpeechLog('前のセッションの終了待ち…');
      _speechEngineIdle ??= Completer<void>();
      try {
        await _speechEngineIdle!.future.timeout(const Duration(seconds: 3));
        _addSpeechLog('前のセッションが終了しました');
      } on TimeoutException {
        _addSpeechLog('終了待ちがタイムアウト。cancel() で中断します');
        try {
          await _speech.cancel();
        } catch (e) {
          _addSpeechLog('cancel() 例外: $e');
        }
        await Future.delayed(const Duration(milliseconds: 300));
        _markSpeechEngineIdle();
      }
    }
  }

  void _markSpeechEngineIdle() {
    _speechEngineBusy = false;
    final idle = _speechEngineIdle;
    _speechEngineIdle = null;
    if (idle != null && !idle.isCompleted) {
      idle.complete();
    }
  }

  // ネイティブ：端末の言語一覧から日本語を探す
  Future<List<String>> _speechLocaleCandidates() async {
    try {
      final locales = await _speech.locales();
      _addSpeechLog('locales(): ${locales.map((l) => l.localeId).toList()}');
      for (final locale in locales) {
        if (locale.localeId.toLowerCase().startsWith('ja')) {
          return [locale.localeId];
        }
      }
    } catch (e) {
      _addSpeechLog('locales() 例外: $e');
    }
    return const ['ja_JP'];
  }

  Future<void> _startListeningAttempt() async {
    final localeId = _localeCandidates[_localeAttempt];
    final sessionId = ++_speechSessionId;
    _speechRetryPending = false;
    _receivedSpeechResult = false;
    _speechEngineBusy = true;
    _addSpeechLog('listen() 開始 #$sessionId (localeId="$localeId", '
        '${_localeAttempt + 1}/${_localeCandidates.length})');

    setState(() {
      _isListening = true;
      _recognizedText = '';
    });

    try {
      await _speech.listen(
        onResult: (val) {
          _addSpeechLog(
              'onResult #$sessionId: "${val.recognizedWords}" (final=${val.finalResult})');
          // 終了済み・古いセッションの結果は無視する
          if (sessionId != _speechSessionId || !_isListening) return;
          if (val.recognizedWords.isEmpty) return;
          _receivedSpeechResult = true;
          setState(() {
            _recognizedText = val.recognizedWords;
            // 認識途中の文字を入力欄に表示する
            _textController.value = TextEditingValue(
              text: _recognizedText,
              selection:
                  TextSelection.collapsed(offset: _recognizedText.length),
            );
          });
        },
        listenOptions: stt.SpeechListenOptions(
          localeId: localeId,
          partialResults: true,
        ),
      );
      _addSpeechLog('listen() 呼び出し完了 #$sessionId');
    } catch (e) {
      _addSpeechLog('listen() 例外: $e');
      _markSpeechEngineIdle();
      _finishListening('listen() 例外');
      _showSpeechMessage('音声入力を開始できませんでした（$e）');
    }
  }

  void _onSpeechStatus(String status) {
    _addSpeechLog('onStatus: $status');
    if (status == stt.SpeechToText.doneStatus) {
      _markSpeechEngineIdle();
    }
    if (_speechRetryPending) return;
    // ブラウザや OS が認識を自動で終えた場合も、画面を元に戻す
    if (status == stt.SpeechToText.doneStatus ||
        status == stt.SpeechToText.notListeningStatus) {
      _finishListening('onStatus: $status');
    }
  }

  void _onSpeechError(SpeechRecognitionError error) {
    _addSpeechLog(
        'onError: ${error.errorMsg} (permanent=${error.permanent})');
    if (!_isListening || _speechRetryPending) return;

    final code = error.errorMsg;
    final canRetry = (code == 'service-not-allowed' ||
            code == 'language-not-supported') &&
        !_receivedSpeechResult &&
        _localeAttempt + 1 < _localeCandidates.length;
    if (canRetry) {
      // 言語指定が原因で断られた可能性があるので、次の候補で試す
      _speechRetryPending = true;
      _localeAttempt++;
      _addSpeechLog('別の言語指定で再試行します');
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted || !_speechRetryPending) return;
        _startListeningAttempt();
      });
      return;
    }

    _finishListening('onError: $code');
    final message = _speechErrorMessage(code);
    if (message != null) {
      _showSpeechMessage(message);
    }
  }

  // エラーコードを利用者向けの説明に変換する（null なら表示しない）
  String? _speechErrorMessage(String code) {
    switch (code) {
      case 'service-not-allowed':
        return 'この端末では音声認識サービスが使えませんでした（service-not-allowed）。'
            '「設定 → プライバシーとセキュリティ → 音声認識」で Safari がオンか、'
            '「設定 → 一般 → キーボード → 音声入力」がオンかを確認してください。';
      case 'not-allowed':
        return 'マイクの使用が許可されていません。'
            '「設定 → アプリ → Safari → マイク」を確認してください。';
      case 'audio-capture':
        return 'マイクを使えませんでした。ほかのアプリやタブがマイクを使っていないか確認してください。';
      case 'network':
        return 'ネットワークに接続できず、音声認識できませんでした。電波の良い場所でもう一度試してください。';
      case 'no-speech':
      case 'error_speech_timeout':
      case 'error_no_match':
        return '声を聞き取れませんでした。もう一度マイクボタンを押して話してください。';
      case 'language-not-supported':
        return 'この端末では日本語の音声認識が使えませんでした。';
      case 'aborted':
        return null;
      default:
        return '音声入力でエラーが起きました（$code）。';
    }
  }

  void _showSpeechMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 8),
      ));
  }

  // 認識セッションを終了し、認識した文字をチャットに追加する（何度呼んでもよい）
  void _finishListening(String reason) {
    _speechRetryPending = false;
    _webAudioWatchdog?.cancel();
    if (!_isListening) return;
    _addSpeechLog('終了処理 ($reason)');
    final text = _recognizedText.trim();
    setState(() {
      _isListening = false;
      if (text.isNotEmpty) {
        _messages.add(ChatMessage(text: text, isPartner: true));
        // 入力欄にも残っていると、送信ボタンで二重に送られるため消す
        _textController.clear();
      }
      _recognizedText = '';
    });
  }

  // SharedPreferencesからカスタム語句を読み込む
  Future<void> _loadCustomPhrasesForChat() async {
    final prefs = await SharedPreferences.getInstance();
    final savedData = prefs.getString('custom_phrases');
    if (savedData != null) {
      try {
        final decoded = jsonDecode(savedData) as Map<String, dynamic>;
        setState(() {
          _customPhrasesMap = decoded.map((key, value) {
            final list = (value as List)
                .map((item) => item['text'].toString())
                .toList();
            return MapEntry(key, list);
          });
        });
      } catch (e) {
        debugPrint('Error loading custom phrases in chat: $e');
      }
    }
  }

  Widget _buildPresetContent() {
    final subCategories = ['目的', '基本情報', '汎用', '痛みのお種類', '体', '薬・薬局'];

    return Column(
      children: [
        SizedBox(
          height: 45,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: subCategories.length,
            itemBuilder: (context, index) {
              final category = subCategories[index];
              final isSelected = (_selectedSubCategory == category);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: ChoiceChip(
                  label: Text(category),
                  selected: isSelected,
                  selectedColor: const Color(0xFF6FCF97),
                  backgroundColor: Colors.grey.shade100,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                  onSelected: (selected) {
                    setState(() {
                      _selectedSubCategory = category;
                    });
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            children: _getPresetButtonsForCategory(_selectedSubCategory),
          ),
        ),
      ],
    );
  }

  List<Widget> _getPresetButtonsForCategory(String category) {
    List<String> buttonTexts = [];

    switch (category) {
      case '目的':
        buttonTexts = [
          '初診です',
          '(診察券/保険証/医療証)を忘れました',
          '(予約を取り/診察/予防接種/健康診断)に来ました',
          '予約(あり/なし)です',
        ];
        break;
      case '基本情報':
        buttonTexts = [
          '年齢：○歳',
          '年齢：○ヶ月',
          '体重：○g',
          '体重：○kg',
          '体重：わからないです',
          '体温：○度',
          '体温：測れていないです',
          'アレルギー：(なし/あり)',
          '保育園/幼稚園/小学校/通っていない',
        ];
        break;
      case '汎用':
        buttonTexts = [
          'トイレに行きたいです',
          '水を飲んでもいいですか',
          '待ち時間はどのくらいですか',
        ];
        break;
      case '痛みのお種類':
        buttonTexts = [
          '痛みが強いです',
          'ズキズキ痛みます',
          'チクチク痛みます',
        ];
        break;
      case '体':
        buttonTexts = [
          '頭が痛いです',
          'お腹が痛いです',
          '熱があります',
          '咳が出ます',
        ];
        break;
      case '薬・薬局':
        buttonTexts = [
          'お薬手帳忘れました',
          '粉薬/錠剤/シロップ/坐薬',
          'この薬は飲めません',
          '飲んだことが(ある/ない)',
          'お薬を変更できますか？',
          'ジェネリックを希望(します/しません)',
          '自宅に(○日分/○袋/○錠)残っています',
        ];
        break;
      default:
        buttonTexts = ['項目がありません'];
    }

    if (_customPhrasesMap.containsKey(category)) {
      buttonTexts.addAll(_customPhrasesMap[category]!);
    }

    return buttonTexts.map((text) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            side: const BorderSide(color: Color(0xFF2C3E50), width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            backgroundColor: Colors.white,
          ),
          onPressed: () {
            if (text.contains('○')) {
              _showNumberInputDialog(text);
            } else if (text.contains('(') && text.contains('/')) {
              _showSelectionDialog(text);
            } else {
              _sendMyMessage(text);
            }
          },
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  void _showNumberInputDialog(String titleTemplate) {
    final TextEditingController inputController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(titleTemplate, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: inputController,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '数値を入力',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2ECC71),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final value = inputController.text.trim();
                if (value.isNotEmpty) {
                  final message = titleTemplate.replaceAll('○', value);
                  Navigator.pop(context);
                  _sendMyMessage(message);
                }
              },
              child: const Text('決定'),
            ),
          ],
        );
      },
    );
  }

  void _showSelectionDialog(String template) {
    final RegExp regExp = RegExp(r'\(([^)]+)\)');
    final match = regExp.firstMatch(template);
    
    if (match == null) return;
    
    final fullMatch = match.group(0)!;
    final optionsStr = match.group(1)!;
    final options = optionsStr.split('/');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('選択してください', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((option) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      side: const BorderSide(color: Colors.grey),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      final result = template.replaceFirst(fullMatch, option);
                      Navigator.pop(context);
                      _sendMyMessage(result);
                    },
                    child: Text(option, style: const TextStyle(fontSize: 16)),
                  ),
                ),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
            ),
          ],
        );
      },
    );
  }

  void _showBodySelectionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        String selectedTab = '体（正面）';

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '症状部位を選択',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              content: SizedBox(
                width: 320,
                height: 360,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildTabButton('体（正面）', selectedTab, (val) {
                          setStateDialog(() => selectedTab = val);
                        }),
                        _buildTabButton('体（背面）', selectedTab, (val) {
                          setStateDialog(() => selectedTab = val);
                        }),
                        _buildTabButton('顔', selectedTab, (val) {
                          setStateDialog(() => selectedTab = val);
                        }),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: _buildMannequinIllustration(selectedTab),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMannequinIllustration(String tabType) {
    if (tabType == '顔') {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              color: const Color(0xFFFFDAB9),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF2C3E50), width: 3),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 40,
                  top: 22,
                  child: Container(
                    width: 80,
                    height: 18,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB6C1),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: const Color(0xFF2C3E50), width: 1.5),
                    ),
                  ),
                ),
                Positioned(left: 45, top: 65, child: _facePart(15)),
                Positioned(right: 45, top: 65, child: _facePart(15)),
                Positioned(left: 30, top: 90, child: _cheekPart()),
                Positioned(right: 30, top: 90, child: _cheekPart()),
                Center(
                  child: Container(
                    width: 10,
                    height: 16,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0AC9D),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 28,
                  left: 65,
                  child: Container(
                    width: 30,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFFC0392B),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      bool isFront = (tabType == '体（正面）');
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFFFDAB9),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF2C3E50), width: 2),
            ),
          ),
          Container(
            width: 18,
            height: 6,
            color: const Color(0xFFFFDAB9),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0AC9D),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF2C3E50), width: 1.5),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    width: 14,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFDAB9),
                      border: Border.all(color: const Color(0xFF2C3E50), width: 1.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.bottomCenter,
                    child: Container(height: 2, color: const Color(0xFF2C3E50)),
                  ),
                  Container(
                    width: 14,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFDAB9),
                      border: Border.all(color: const Color(0xFF2C3E50), width: 1.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.bottomCenter,
                    child: Container(height: 2, color: const Color(0xFF2C3E50)),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Container(
                width: 65,
                height: 105,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFDAB9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF2C3E50), width: 2),
                ),
                child: Center(
                  child: Container(
                    width: isFront ? 1 : 2,
                    height: double.infinity,
                    color: isFront
                        ? const Color(0xFF2C3E50).withOpacity(0.3)
                        : const Color(0xFF2C3E50),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Column(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0AC9D),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF2C3E50), width: 1.5),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    width: 14,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFDAB9),
                      border: Border.all(color: const Color(0xFF2C3E50), width: 1.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.bottomCenter,
                    child: Container(height: 2, color: const Color(0xFF2C3E50)),
                  ),
                  Container(
                    width: 14,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFDAB9),
                      border: Border.all(color: const Color(0xFF2C3E50), width: 1.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.bottomCenter,
                    child: Container(height: 2, color: const Color(0xFF2C3E50)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 24,
                height: 65,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFDAB9),
                  border: Border.all(color: const Color(0xFF2C3E50), width: 1.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Container(height: 2, color: const Color(0xFF2C3E50)),
              ),
              const SizedBox(width: 6),
              Container(
                width: 24,
                height: 65,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFDAB9),
                  border: Border.all(color: const Color(0xFF2C3E50), width: 1.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Container(height: 2, color: const Color(0xFF2C3E50)),
              ),
            ],
          ),
        ],
      );
    }
  }

  Widget _facePart(double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFF2C3E50),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _cheekPart() {
    return Container(
      width: 24,
      height: 18,
      decoration: BoxDecoration(
        color: const Color(0xFFFF9999),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildTabButton(String title, String currentTab, Function(String) onTap) {
    bool isSelected = (title == currentTab);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isSelected ? const Color(0xFF1A2530) : Colors.white,
            foregroundColor: isSelected ? Colors.white : Colors.black87,
            elevation: isSelected ? 2 : 0,
            side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey.shade300),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () => onTap(title),
          child: Text(title, style: const TextStyle(fontSize: 13)),
        ),
      ),
    );
  }

  void _sendMyMessage(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      _messages.add(ChatMessage(text: text, isPartner: false));
    });
    _textController.clear();
  }

  void _showNoticeDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('お医者様・受付の方へ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '耳が聞こえにくいため、このアプリで会話させてください。\n（文字または音声で会話できます）',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _showTutorialScreen();
                },
                icon: const Icon(Icons.help_outline, color: Colors.blue),
                label: const Text(
                  '操作方法はこちら ＞',
                  style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }

  void _showTutorialScreen() {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (BuildContext context, _, __) {
          return Scaffold(
            backgroundColor: Colors.black.withOpacity(0.7),
            appBar: AppBar(
              title: const Text('操作方法のご案内'),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              '💡 アプリの使い方のコツ',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('🎤 ', style: TextStyle(fontSize: 18)),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('音声で入力する', style: TextStyle(fontWeight: FontWeight.bold)),
                                      Text('画面下のマイクボタンを押すと、話した言葉が自動で文字に変換され入力されます。', style: TextStyle(color: Colors.grey, fontSize: 13)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Divider(height: 24),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('🔄 ', style: TextStyle(fontSize: 18)),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('自分と相手を切り替える', style: TextStyle(fontWeight: FontWeight.bold)),
                                      Text('リバースボタンを押すと、対話相手（青）と自分（ピンク）の入力を切り替えて会話できます。', style: TextStyle(color: Colors.grey, fontSize: 13)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Divider(height: 24),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('🗑️ ', style: TextStyle(fontSize: 18)),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('メッセージを削除する', style: TextStyle(fontWeight: FontWeight.bold)),
                                      Text('チャットの吹き出し右上にあるゴミ箱マークを押すと、選んだ項目を削除できます。', style: TextStyle(color: Colors.grey, fontSize: 13)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text(
                            'わかった（閉じる）',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showDeleteConfirmDialog(int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('この項目を削除しますか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _messages.removeAt(index);
                });
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('指さし会話'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        leadingWidth: 120,
        leading: Builder(
          builder: (context) => Padding(
            padding: const EdgeInsets.only(left: 8.0, top: 8.0, bottom: 8.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE8F9EE),
                foregroundColor: Colors.black87,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Color(0xFF6FCF97)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: const Text('📖', style: TextStyle(fontSize: 14)),
              label: const Text(
                '指差し機能',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: '音声ログ',
            onPressed: _showSpeechLogDialog,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: Colors.grey.shade200,
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              icon: const Text('ℹ️', style: TextStyle(fontSize: 14)),
              label: const Text(
                '相手の方へ',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              onPressed: _showNoticeDialog,
            ),
          ),
        ],
      ),

      drawer: Drawer(
        child: Container(
          color: const Color(0xFFF8F9FA),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 40, 16, 12),
                color: Colors.white,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '身体情報・症状選択',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                        backgroundColor: Colors.grey.shade100,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_left, size: 20),
                      label: const Text('閉じる', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Container(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectedMainTab == '身体情報' ? Colors.blue : Colors.white,
                          foregroundColor: _selectedMainTab == '身体情報' ? Colors.white : Colors.black87,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedMainTab = '身体情報';
                          });
                        },
                        child: const Text('身体情報'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectedMainTab == '定型文' ? Colors.blue : Colors.white,
                          foregroundColor: _selectedMainTab == '定型文' ? Colors.white : Colors.black87,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedMainTab = '定型文';
                          });
                        },
                        child: const Text('定型文'),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _selectedMainTab == '定型文'
                    ? _buildPresetContent()
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFF6FCF97)),
                                  backgroundColor: const Color(0xFFE8F9EE),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 2),
                                ),
                                onPressed: () {
                                  _showBodySelectionDialog();
                                },
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Text('🧍‍♂️', style: TextStyle(fontSize: 12)),
                                    SizedBox(width: 2),
                                    Text(
                                      '体の部位をイラストから選択',
                                      style: TextStyle(
                                        color: Colors.black87,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 9.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text('症状を選択', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.all(8.0),
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _buildSymptomBtn('発熱'),
                                    _buildSymptomBtn('せき'),
                                    _buildSymptomBtn('鼻水・鼻づまり'),
                                    _buildSymptomBtn('下痢'),
                                    _buildSymptomBtn('吐き気'),
                                    _buildSymptomBtn('嘔吐'),
                                    _buildSymptomBtn('めまい'),
                                    _buildSymptomBtn('機嫌が悪い'),
                                    _buildSymptomBtn('寝つきが悪い'),
                                    _buildSymptomBtn('泣き止まない'),
                                    _buildSymptomBtn('腹痛'),
                                    _buildSymptomBtn('頭痛'),
                                    _buildSymptomBtn('転んだ'),
                                    _buildSymptomBtn('ぶつけた'),
                                    _buildSymptomBtn('さされた'),
                                    _buildSymptomBtn('はさんだ'),
                                    _buildSymptomBtn('痛む'),
                                    _buildSymptomBtn('痛がる'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),

      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    return Align(
                      alignment: msg.isPartner
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                            padding: const EdgeInsets.fromLTRB(12, 12, 24, 12),
                            decoration: BoxDecoration(
                              color: msg.isPartner
                                  ? const Color(0xFFE8F1FF)
                                  : const Color(0xFFFFEBF0),
                              border: Border.all(
                                color: msg.isPartner
                                    ? const Color(0xFF70A6FF)
                                    : const Color(0xFFFF85A1),
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              msg.text,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () => _showDeleteConfirmDialog(index),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(4),
                                child: const Icon(
                                  Icons.delete,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1, thickness: 1),
              Container(
                padding: const EdgeInsets.all(8),
                color: _isOpponentMode ? Colors.blue.shade50 : Colors.white,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.loop),
                      color: _isOpponentMode ? Colors.blue : Colors.green,
                      tooltip: _isOpponentMode ? '自分側の入力に切り替え' : '相手側の入力に切り替え',
                      onPressed: () {
                        setState(() {
                          _isOpponentMode = !_isOpponentMode;
                        });
                      },
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        style: const TextStyle(fontSize: 18.0),
                        decoration: InputDecoration(
                          hintText: _isOpponentMode ? '相手の方のテキストを入力...' : 'テキストを入力',
                          filled: true,
                          fillColor: _isOpponentMode ? Colors.blue.shade50 : Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                              color: _isOpponentMode ? Colors.blue : Colors.grey.shade300,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                              color: _isOpponentMode ? Colors.blue.shade200 : Colors.grey.shade300,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onSubmitted: (text) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.send),
                      color: _isOpponentMode ? Colors.blue : Colors.green,
                      onPressed: _sendMessage,
                    ),
                    FloatingActionButton.small(
                      backgroundColor: Colors.blue,
                      onPressed: _listenSpeech,
                      child: const Icon(
                        Icons.mic_none,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_isListening)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.6),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '音声入力中...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: 250,
                        height: 70,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            elevation: 8,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(35),
                            ),
                          ),
                          onPressed: _listenSpeech,
                          icon: const Icon(Icons.stop, size: 36),
                          label: const Text(
                            'ボタンを押して終了',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        width: 320,
                        height: 200,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.builder(
                          reverse: true,
                          itemCount: _speechLogs.length,
                          itemBuilder: (context, index) => Text(
                            _speechLogs[_speechLogs.length - 1 - index],
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _copySpeechLogs,
                        icon: const Icon(Icons.copy, color: Colors.white70, size: 18),
                        label: const Text(
                          'ログをコピー',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSymptomBtn(String label) {
    return SizedBox(
      width: 100,
      height: 44,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFF6FCF97)),
          backgroundColor: const Color(0xFFE8F9EE),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: EdgeInsets.zero,
        ),
        onPressed: () => _appendSymptomText(label),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _appendSymptomText(String text) {
    setState(() {
      if (_textController.text.isEmpty) {
        _textController.text = text;
      } else {
        _textController.text = '${_textController.text} $text';
      }
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: _textController.text.length),
      );
    });
  }
}