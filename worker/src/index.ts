export interface Env {
  GITHUB_CLIENT_ID: string;
  GITHUB_CLIENT_SECRET: string;
  GITHUB_OAUTH_CLIENT_ID?: string;
  GITHUB_OAUTH_CLIENT_SECRET?: string;
  GITHUB_APP_ID: string;
  GITHUB_PRIVATE_KEY: string;
  USAGE_HMAC_SECRET: string;
  LICENSES: KVNamespace;
}

function oauthClientId(env: Env): string {
  return env.GITHUB_OAUTH_CLIENT_ID || env.GITHUB_CLIENT_ID;
}

function oauthClientSecret(env: Env): string {
  return env.GITHUB_OAUTH_CLIENT_SECRET || env.GITHUB_CLIENT_SECRET;
}

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    if (request.method === "GET" && url.pathname === "/download") {
      return handleDownload(request, env);
    }

    if (request.method !== "POST") {
      return json({ error: "method not allowed" }, 405);
    }

    if (request.headers.get("Content-Type") !== "application/json") {
      return json({ error: "content-type must be application/json" }, 415);
    }

    if (url.pathname === "/github/connect") return handleConnect(request, env);
    if (url.pathname === "/github/refresh") return handleRefresh(request, env);
    if (url.pathname === "/github/installation-token") return handleInstallationToken(request, env);
    if (url.pathname === "/github/uninstall-installation") return handleUninstallInstallation(request, env);
    if (url.pathname === "/billing/usage") return handleBillingUsage(request, env);

    return json({ error: "not found" }, 404);
  },
};

async function handleBillingUsage(request: Request, env: Env): Promise<Response> {
  const body = await parseBody(request);
  if (!body) return json({ error: "invalid json" }, 400);

  const machineId = body.machine_id as string | undefined;
  const action = body.action as string | undefined;
  const date = body.date as string | undefined;
  const createdAtSig = body.created_at_sig as string | undefined;

  if (!machineId || !action || !date) {
    return json({ error: "machine_id, action, and date are required" }, 400);
  }

  if (action !== "increment" && action !== "check") {
    return json({ error: "action must be 'increment' or 'check'" }, 400);
  }

  const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const ipKey = `ip_rate:${ip}:${date}:${new Date().getUTCHours()}`;
  const ipCountRaw = await env.LICENSES.get(ipKey);
  const ipCount = ipCountRaw ? parseInt(ipCountRaw, 10) : 0;
  const IP_HOURLY_LIMIT = 120;
  if (ipCount >= IP_HOURLY_LIMIT) {
    return json({ error: "rate_limit_exceeded" }, 429);
  }
  await env.LICENSES.put(ipKey, String(ipCount + 1), { expirationTtl: 7200 });

  const createdAtKey = `created_at:${machineId}`;
  const existingCreatedAt = await env.LICENSES.get(createdAtKey);
  const storedCreatedAt = existingCreatedAt ?? new Date().toISOString();

  if (existingCreatedAt === null) {
    await env.LICENSES.put(createdAtKey, storedCreatedAt);
  }

  if (existingCreatedAt !== null && createdAtSig) {
    const expectedSig = await hmacSign(env.USAGE_HMAC_SECRET, `${machineId}:${storedCreatedAt}`);
    if (createdAtSig !== expectedSig) {
      return json({ error: "created_at_sig_invalid" }, 403);
    }
  }

  const newCreatedAtSig = await hmacSign(env.USAGE_HMAC_SECRET, `${machineId}:${storedCreatedAt}`);

  const usageKey = `usage:${machineId}:${date}`;
  const existing = await env.LICENSES.get(usageKey);
  const count = existing ? parseInt(existing, 10) : 0;

  if (action === "check") {
    return json({ allowed: true, count, limit: null, created_at_sig: newCreatedAtSig });
  }

  const newCount = count + 1;
  await env.LICENSES.put(usageKey, String(newCount), { expirationTtl: 172800 });

  return json({ allowed: true, count: newCount, limit: null, created_at_sig: newCreatedAtSig });
}

async function hmacSign(secret: string, payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  return Array.from(new Uint8Array(mac)).map(b => b.toString(16).padStart(2, "0")).join("");
}

async function handleConnect(request: Request, env: Env): Promise<Response> {
  const body = await parseBody(request);
  if (!body) return json({ error: "invalid json" }, 400);

  const code = body.code;
  if (typeof code !== "string" || code.length === 0) {
    return json({ error: "code must be a non-empty string" }, 400);
  }

  const tokenRes = await exchangeCode(code, env);
  if (!tokenRes.ok) return json({ error: "oauth exchange failed", detail: tokenRes.error }, 500);

  const expiresAt = tokenRes.data.expires_in ? Math.floor(Date.now() / 1000) + tokenRes.data.expires_in : null;

  return json({
    access_token: tokenRes.data.access_token,
    refresh_token: tokenRes.data.refresh_token ?? null,
    expires_at: expiresAt,
  });
}

async function handleRefresh(request: Request, env: Env): Promise<Response> {
  const body = await parseBody(request);
  if (!body) return json({ error: "invalid json" }, 400);

  const refreshToken = body.refresh_token;
  if (typeof refreshToken !== "string" || refreshToken.length === 0) {
    return json({ error: "refresh_token must be a non-empty string" }, 400);
  }

  const params = new URLSearchParams({
    client_id: oauthClientId(env),
    client_secret: oauthClientSecret(env),
    grant_type: "refresh_token",
    refresh_token: refreshToken,
  });

  const res = await fetch("https://github.com/login/oauth/access_token", {
    method: "POST",
    headers: { Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded" },
    body: params.toString(),
  });

  if (!res.ok) return json({ error: "internal error" }, 500);

  const data = await res.json() as OAuthTokenResponse;
  if ("error" in data) return json({ error: "internal error" }, 500);

  const expiresAt = data.expires_in ? Math.floor(Date.now() / 1000) + data.expires_in : null;

  return json({
    access_token: data.access_token,
    refresh_token: data.refresh_token ?? null,
    expires_at: expiresAt,
  });
}

async function exchangeCode(code: string, env: Env): Promise<{ ok: true; data: OAuthTokenResponse } | { ok: false; error: string }> {
  const params = new URLSearchParams({
    client_id: oauthClientId(env),
    client_secret: oauthClientSecret(env),
    redirect_uri: "http://localhost:4567",
    code,
  });

  const res = await fetch("https://github.com/login/oauth/access_token", {
    method: "POST",
    headers: { Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded" },
    body: params.toString(),
  });

  if (!res.ok) return { ok: false, error: `github http ${res.status}` };

  const data = await res.json() as OAuthTokenResponse;
  if ("error" in data) {
    return { ok: false, error: `${data.error}: ${(data as unknown as Record<string, string>).error_description ?? ""}` };
  }

  return { ok: true, data };
}

interface OAuthTokenResponse {
  access_token: string;
  refresh_token?: string;
  token_type?: string;
  expires_in?: number;
  refresh_token_expires_in?: number;
  error?: string;
}

async function handleInstallationToken(request: Request, env: Env): Promise<Response> {
  const body = await parseBody(request);
  if (!body) return json({ error: "invalid json" }, 400);

  const accessToken = body.access_token;
  const targetLogin = typeof body.target_login === "string" && body.target_login.length > 0 ? body.target_login : null;
  const installationId = typeof body.installation_id === "number" ? body.installation_id : null;
  if (typeof accessToken !== "string" || accessToken.length === 0) {
    return json({ error: "access_token required" }, 400);
  }

  const jwt = await signAppJwt(env.GITHUB_APP_ID, env.GITHUB_PRIVATE_KEY);
  if (!jwt.ok) return json({ error: "failed to sign jwt", detail: jwt.error }, 500);

  const installationsRes = await fetch("https://api.github.com/user/installations", {
    headers: {
      Authorization: `Bearer ${accessToken}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "UnifiedDev/1.0",
    },
  });

  if (!installationsRes.ok) {
    const detail = await installationsRes.text();
    return json({ error: "failed to list installations", status: installationsRes.status, detail }, 502);
  }

  const installationsData = await installationsRes.json() as { installations: Array<{ id: number; app_id: number; account?: { login?: string } }> };
  const appId = parseInt(env.GITHUB_APP_ID, 10);
  const installation = installationsData.installations.find((i) => {
    if (i.app_id !== appId) return false;
    if (installationId !== null) return i.id === installationId;
    if (!targetLogin) return true;
    return i.account?.login === targetLogin;
  });

  if (!installation) {
    return json({
      error: "app not installed for requested target",
      app_id: appId,
      target_login: targetLogin,
      found: installationsData.installations.map(i => ({ app_id: i.app_id, login: i.account?.login ?? null })),
    }, 404);
  }

  const tokenRes = await fetch(`https://api.github.com/app/installations/${installation.id}/access_tokens`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${jwt.token}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "UnifiedDev/1.0",
    },
  });

  if (!tokenRes.ok) {
    const err = await tokenRes.text();
    return json({ error: "failed to create installation token", detail: err }, 502);
  }

  const tokenData = await tokenRes.json() as { token: string; expires_at: string };

  return json({
    token: tokenData.token,
    expires_at: Math.floor(new Date(tokenData.expires_at).getTime() / 1000),
    installation_id: installation.id,
  });
}

async function handleUninstallInstallation(request: Request, env: Env): Promise<Response> {
  const body = await parseBody(request);
  if (!body) return json({ error: "invalid json" }, 400);

  const accessToken = body.access_token;
  const targetLogin = body.target_login;

  if (typeof accessToken !== "string" || accessToken.length === 0) {
    return json({ error: "access_token required" }, 400);
  }

  if (typeof targetLogin !== "string" || targetLogin.length === 0) {
    return json({ error: "target_login required" }, 400);
  }

  const jwt = await signAppJwt(env.GITHUB_APP_ID, env.GITHUB_PRIVATE_KEY);
  if (!jwt.ok) return json({ error: "failed to sign jwt", detail: jwt.error }, 500);

  const installationsRes = await fetch("https://api.github.com/user/installations", {
    headers: {
      Authorization: `Bearer ${accessToken}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "UnifiedDev/1.0",
    },
  });

  if (!installationsRes.ok) {
    const detail = await installationsRes.text();
    return json({ error: "failed to list installations", status: installationsRes.status, detail }, 502);
  }

  const installationsData = await installationsRes.json() as { installations: Array<{ id: number; app_id: number; account?: { login?: string } }> };
  const appId = parseInt(env.GITHUB_APP_ID, 10);
  const installation = installationsData.installations.find((i) => i.app_id === appId && i.account?.login === targetLogin);

  if (!installation) {
    return json({ error: "installation not found for target", target_login: targetLogin }, 404);
  }

  const response = await fetch(`https://api.github.com/app/installations/${installation.id}`, {
    method: "DELETE",
    headers: {
      Authorization: `Bearer ${jwt.token}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "UnifiedDev/1.0",
    },
  });

  if (!response.ok) {
    const detail = await response.text();
    return json({ error: "failed to uninstall installation", status: response.status, detail }, 502);
  }

  return json({ success: true, target_login: targetLogin });
}

async function signAppJwt(appId: string, pemKey: string): Promise<{ ok: true; token: string } | { ok: false; error: string }> {
  try {
    const normalizedKey = normalizePrivateKey(pemKey);
    const keyData = pemToDer(normalizedKey);
    const pkcs8KeyData = normalizedKey.includes("BEGIN RSA PRIVATE KEY") ? wrapPkcs1InPkcs8(keyData) : keyData;

    const now = Math.floor(Date.now() / 1000);
    const header = { alg: "RS256", typ: "JWT" };
    const payload = { iat: now - 60, exp: now + 540, iss: appId };
    const signingInput = `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(JSON.stringify(payload))}`;

    const privateKey = await crypto.subtle.importKey(
      "pkcs8",
      pkcs8KeyData,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"],
    );

    const signature = await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      privateKey,
      new TextEncoder().encode(signingInput),
    );

    const token = `${signingInput}.${base64UrlEncode(signature)}`;

    return { ok: true, token };
  } catch (e) {
    const normalizedKey = normalizePrivateKey(pemKey);
    const header = normalizedKey.split("\n").find((line) => line.startsWith("-----BEGIN ")) ?? "missing";
    return {
      ok: false,
      error: JSON.stringify({
        message: String(e),
        header,
        hasEscapedNewlines: pemKey.includes("\\n"),
        lineCount: normalizedKey.split("\n").length,
        bodyLength: normalizedKey
          .replace(/-----BEGIN [A-Z ]+-----/g, "")
          .replace(/-----END [A-Z ]+-----/g, "")
          .replace(/\s+/g, "").length,
      }),
    };
  }
}

function normalizePrivateKey(privateKey: string): string {
  return privateKey.replace(/\\n/g, "\n").trim();
}

function pemToDer(pem: string): Uint8Array {
  const pemBody = pem
    .replace(/-----BEGIN [A-Z ]+-----/g, "")
    .replace(/-----END [A-Z ]+-----/g, "")
    .replace(/\s+/g, "");

  return Uint8Array.from(atob(pemBody), (char) => char.charCodeAt(0));
}

function wrapPkcs1InPkcs8(pkcs1: Uint8Array): Uint8Array {
  const version = new Uint8Array([0x02, 0x01, 0x00]);
  const algorithmIdentifier = new Uint8Array([
    0x30, 0x0d,
    0x06, 0x09,
    0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01,
    0x05, 0x00,
  ]);
  const privateKey = encodeDer(0x04, pkcs1);

  return encodeDer(0x30, concatBytes(version, algorithmIdentifier, privateKey));
}

function encodeDer(tag: number, value: Uint8Array): Uint8Array {
  return concatBytes(new Uint8Array([tag]), encodeDerLength(value.length), value);
}

function encodeDerLength(length: number): Uint8Array {
  if (length < 0x80) {
    return new Uint8Array([length]);
  }

  const bytes: number[] = [];
  let remaining = length;

  while (remaining > 0) {
    bytes.unshift(remaining & 0xff);
    remaining >>= 8;
  }

  return new Uint8Array([0x80 | bytes.length, ...bytes]);
}

function concatBytes(...arrays: Uint8Array[]): Uint8Array {
  const totalLength = arrays.reduce((sum, array) => sum + array.length, 0);
  const result = new Uint8Array(totalLength);
  let offset = 0;

  for (const array of arrays) {
    result.set(array, offset);
    offset += array.length;
  }

  return result;
}

function base64UrlEncode(value: string | ArrayBuffer): string {
  const bytes = typeof value === "string"
    ? new TextEncoder().encode(value)
    : new Uint8Array(value);

  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
}

async function parseBody(request: Request): Promise<Record<string, unknown> | null> {
  try {
    return await request.json();
  } catch {
    return null;
  }
}

async function handleDownload(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const arch = url.searchParams.get("arch");

  const cdnArch = arch === "intel" ? "x86_64" : "aarch64";
  const kvKey = arch === "intel" ? "download:intel" : "download:arm";

  const latestRes = await fetch("https://api.github.com/repos/akira-foundation/unified-dev/releases/latest", {
    headers: { "User-Agent": "UnifiedDev/1.0", Accept: "application/vnd.github+json" },
  });
  if (!latestRes.ok) return new Response("Could not resolve latest version", { status: 502 });

  const release = await latestRes.json() as { tag_name: string; assets: Array<{ name: string; browser_download_url: string }> };
  const version = release.tag_name.replace(/^v/, "");
  const assetName = `unified_dev_${version}_${cdnArch}.dmg`;
  const asset = release.assets.find((a) => a.name === assetName);
  if (!asset) return new Response("Release asset not found", { status: 502 });

  const current = await env.LICENSES.get(kvKey);
  const count = parseInt(current ?? "0", 10) + 1;
  await env.LICENSES.put(kvKey, String(count));

  return Response.redirect(asset.browser_download_url, 302);
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}
