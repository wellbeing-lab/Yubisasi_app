# speech-token-worker

Azure AI Speech の一時トークン（10 分有効）を発行する Cloudflare Worker です。
ブラウザ（Flutter Web）には Azure のキーを渡さず、このトークンだけを渡します。

- `GET /token` → `{ "token": "...", "region": "japaneast", "expiresInSeconds": 540 }`
- `ALLOWED_ORIGINS`（`wrangler.jsonc`）に書いたページからの呼び出しだけに応えます。

## 初回のセットアップ

```sh
cd speech-token-worker
npm install
npx wrangler login                     # ブラウザで Cloudflare にログイン
npx wrangler deploy                    # Worker を公開（URL が表示される）
npx wrangler secret put AZURE_SPEECH_KEY   # Azure Speech のキーを入力（画面には表示されない）
```

表示された URL の末尾に `/token` を付けたものを、GitHub のリポジトリ変数
`SPEECH_TOKEN_URL` に登録します（Settings → Secrets and variables → Actions → Variables）。

## 動作確認

```sh
curl -H "Origin: https://wellbeing-lab.github.io" https://<Worker の URL>/token
```

`token` が返れば成功です。
