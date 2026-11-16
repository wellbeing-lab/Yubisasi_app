// Azure Speech の一時トークン（有効期間 10 分）を発行する。
// ブラウザには本物のキーを渡さず、このトークンだけを渡す。
//
// GET /token -> { "token": "...", "region": "japaneast", "expiresInSeconds": 540 }

const TOKEN_TTL_SECONDS = 540; // Azure 側は 10 分。余裕を持って 9 分で取り直してもらう

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const origin = request.headers.get("Origin") ?? "";
    const allowed = (env.ALLOWED_ORIGINS ?? "")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);
    const originAllowed = allowed.includes(origin);

    const corsHeaders = originAllowed
      ? {
          "Access-Control-Allow-Origin": origin,
          "Access-Control-Allow-Methods": "GET, OPTIONS",
          "Access-Control-Max-Age": "86400",
          Vary: "Origin",
        }
      : { Vary: "Origin" };

    if (request.method === "OPTIONS") {
      return new Response(null, { status: originAllowed ? 204 : 403, headers: corsHeaders });
    }

    if (url.pathname !== "/token") {
      return json({ error: "not_found" }, 404, corsHeaders);
    }
    if (request.method !== "GET") {
      return json({ error: "method_not_allowed" }, 405, corsHeaders);
    }
    // 許可したページ以外からの呼び出しは断る（ブラウザ以外からの悪用を完全には防げないが、
    // Azure を無料プラン F0 にしておけば、使われても料金は発生しない）
    if (!originAllowed) {
      return json({ error: "origin_not_allowed" }, 403, corsHeaders);
    }
    if (!env.AZURE_SPEECH_KEY || !env.AZURE_SPEECH_REGION) {
      return json({ error: "server_not_configured" }, 500, corsHeaders);
    }

    const issueUrl = `https://${env.AZURE_SPEECH_REGION}.api.cognitive.microsoft.com/sts/v1.0/issueToken`;
    const azureResponse = await fetch(issueUrl, {
      method: "POST",
      headers: {
        "Ocp-Apim-Subscription-Key": env.AZURE_SPEECH_KEY,
        "Content-Length": "0",
      },
    });
    if (!azureResponse.ok) {
      console.error("Azure issueToken failed", azureResponse.status);
      return json({ error: "azure_token_failed", status: azureResponse.status }, 502, corsHeaders);
    }

    const token = await azureResponse.text();
    return json(
      { token, region: env.AZURE_SPEECH_REGION, expiresInSeconds: TOKEN_TTL_SECONDS },
      200,
      { ...corsHeaders, "Cache-Control": "no-store" },
    );
  },
};

function json(body, status, headers) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...headers },
  });
}
