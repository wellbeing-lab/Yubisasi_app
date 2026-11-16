// Azure AI Speech（リアルタイム音声認識）を Flutter から使うための小さな窓口。
// Flutter 側（lib/web_speech/azure_speech_web.dart）から window.yubisasiAzureSpeech を呼ぶ。
//
// - Azure のキーはブラウザに置かない。仲介サーバー（speech-token-worker）から
//   10 分有効の一時トークンをもらって使う。
// - iPhone の Safari では、マイクの開始をボタンを押した処理の中で行う必要があるため、
//   トークンは事前に取得しておき（prefetchToken）、start() は待たずに開始する。
(function () {
  "use strict";

  let tokenUrl = "";
  let cached = null; // { token, region, expiresAt }
  let inflight = null;
  let current = null; // { recognizer, gen }
  let generation = 0;

  function hasFreshToken() {
    return !!cached && Date.now() < cached.expiresAt;
  }

  async function fetchToken() {
    if (!tokenUrl) throw new Error("トークンの URL が設定されていません");
    if (inflight) return inflight;
    inflight = (async () => {
      const res = await fetch(tokenUrl, { method: "GET", cache: "no-store" });
      if (!res.ok) {
        let detail = "";
        try { detail = JSON.stringify(await res.json()); } catch (_) {}
        throw new Error("HTTP " + res.status + " " + detail);
      }
      const body = await res.json();
      const ttl = Math.max(60, (body.expiresInSeconds || 540) - 30);
      cached = { token: body.token, region: body.region, expiresAt: Date.now() + ttl * 1000 };
      return cached;
    })();
    try {
      return await inflight;
    } finally {
      inflight = null;
    }
  }

  function cancellationCodeName(sdk, code) {
    const names = sdk.CancellationErrorCode || {};
    return typeof names[code] === "string" ? names[code] : String(code);
  }

  function closeRecognizer(entry) {
    if (!entry) return;
    try { entry.recognizer.close(); } catch (_) {}
  }

  function startWithToken(sdk, tok, opts, gen) {
    const call = (name, ...args) => {
      if (gen !== generation) return; // 古いセッションのイベントは無視する
      const fn = opts[name];
      if (typeof fn === "function") fn(...args);
    };

    const speechConfig = sdk.SpeechConfig.fromAuthorizationToken(tok.token, tok.region);
    speechConfig.speechRecognitionLanguage = opts.lang || "ja-JP";
    const audioConfig = sdk.AudioConfig.fromDefaultMicrophoneInput();
    const recognizer = new sdk.SpeechRecognizer(speechConfig, audioConfig);

    const phrases = Array.isArray(opts.phrases) ? opts.phrases : [];
    if (phrases.length > 0) {
      const phraseList = sdk.PhraseListGrammar.fromRecognizer(recognizer);
      phraseList.addPhrases(phrases);
    }

    recognizer.sessionStarted = () => call("onEvent", "sessionStarted", "");
    recognizer.speechStartDetected = () => call("onEvent", "speechStartDetected", "");
    recognizer.speechEndDetected = () => call("onEvent", "speechEndDetected", "");
    recognizer.recognizing = (_s, e) => call("onPartial", e.result.text || "");
    recognizer.recognized = (_s, e) => {
      if (e.result.reason === sdk.ResultReason.RecognizedSpeech) {
        call("onFinal", e.result.text || "");
      } else if (e.result.reason === sdk.ResultReason.NoMatch) {
        call("onEvent", "noMatch", "");
      }
    };
    recognizer.canceled = (_s, e) => {
      if (e.reason === sdk.CancellationReason.Error) {
        call("onError", cancellationCodeName(sdk, e.errorCode), e.errorDetails || "");
      } else {
        call("onEvent", "canceled", String(e.reason));
      }
    };
    recognizer.sessionStopped = () => call("onEvent", "sessionStopped", "");

    current = { recognizer, gen };
    recognizer.startContinuousRecognitionAsync(
      () => call("onEvent", "started", ""),
      (err) => call("onError", "StartFailed", String(err)),
    );
  }

  window.yubisasiAzureSpeech = {
    isAvailable() {
      return !!window.SpeechSDK;
    },

    configure(url) {
      tokenUrl = url || "";
    },

    hasFreshToken,

    // トークンを先に取っておく。成功したら true を返す Promise。
    prefetchToken() {
      if (hasFreshToken()) return Promise.resolve(true);
      return fetchToken().then(() => true);
    },

    // 認識を始める。トークンがあればすぐ（ボタン操作の中で）開始し、
    // なければ取得してから開始する。
    start(opts) {
      const sdk = window.SpeechSDK;
      const gen = ++generation;
      const prev = current;
      current = null;
      closeRecognizer(prev);

      const fail = (code, detail) => {
        if (gen !== generation) return;
        if (typeof opts.onError === "function") opts.onError(code, detail);
      };
      if (!sdk) {
        fail("SdkNotLoaded", "Azure Speech SDK が読み込まれていません");
        return false;
      }
      try {
        if (hasFreshToken()) {
          startWithToken(sdk, cached, opts, gen);
        } else {
          if (typeof opts.onEvent === "function") opts.onEvent("fetchingToken", "");
          fetchToken()
            .then((tok) => {
              if (gen === generation) startWithToken(sdk, tok, opts, gen);
            })
            .catch((err) => fail("TokenFailed", String(err && err.message ? err.message : err)));
        }
        return true;
      } catch (err) {
        fail("StartFailed", String(err));
        return false;
      }
    },

    // 認識を止める。最後の確定結果を受け取ってから onEnd を呼ぶ。
    stop(onEnd) {
      const entry = current;
      const done = () => {
        closeRecognizer(entry);
        if (current === entry) current = null;
        if (typeof onEnd === "function") onEnd();
      };
      if (!entry) {
        done();
        return;
      }
      try {
        entry.recognizer.stopContinuousRecognitionAsync(done, () => done());
      } catch (_) {
        done();
      }
    },

    // すぐに中断する（結果は受け取らない）。
    abort() {
      generation++;
      const entry = current;
      current = null;
      closeRecognizer(entry);
    },
  };
})();
