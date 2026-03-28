export interface Env {
  GITHUB_CLIENT_ID: string;
  GITHUB_CLIENT_SECRET: string;
  GITHUB_OAUTH_CLIENT_ID?: string;
  GITHUB_OAUTH_CLIENT_SECRET?: string;
  GITHUB_APP_ID: string;
  GITHUB_PRIVATE_KEY: string;
  STRIPE_SECRET_KEY: string;
  STRIPE_WEBHOOK_SECRET: string;
  LICENSES: KVNamespace;
}

function oauthClientId(env: Env): string {
  return env.GITHUB_OAUTH_CLIENT_ID || env.GITHUB_CLIENT_ID;
}

function oauthClientSecret(env: Env): string {
  return env.GITHUB_OAUTH_CLIENT_SECRET || env.GITHUB_CLIENT_SECRET;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "POST" && url.pathname === "/billing/webhook") {
      return handleBillingWebhook(request, env);
    }

    if (request.method === "GET" && url.pathname === "/billing/status") {
      return handleBillingStatus(request, env);
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
    if (url.pathname === "/billing/checkout") return handleBillingCheckout(request, env);
    if (url.pathname === "/billing/activate") return handleBillingActivate(request, env);

    return json({ error: "not found" }, 404);
  },
};

const PLAN_PRICES: Record<string, Record<string, string>> = {
  pro: {
    monthly: "price_pro_monthly",
    yearly: "price_pro_yearly",
  },
  ultimate: {
    monthly: "price_ultimate_monthly",
    yearly: "price_ultimate_yearly",
  },
};

async function handleBillingCheckout(request: Request, env: Env): Promise<Response> {
  const body = await parseBody(request);
  if (!body) return json({ error: "invalid json" }, 400);

  const plan = body.plan as string;
  const cycle = (body.cycle as string) ?? "monthly";

  if (!PLAN_PRICES[plan]?.[cycle]) {
    return json({ error: "invalid plan or cycle" }, 400);
  }

  const params = new URLSearchParams({
    "line_items[0][price]": PLAN_PRICES[plan][cycle],
    "line_items[0][quantity]": "1",
    mode: "subscription",
    success_url: `akira://license/activate?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `akira://license/cancelled`,
    allow_promotion_codes: "true",
    "subscription_data[metadata][plan]": plan,
    "subscription_data[metadata][cycle]": cycle,
  });

  const res = await fetch("https://api.stripe.com/v1/checkout/sessions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: params.toString(),
  });

  if (!res.ok) {
    const err = await res.text();
    return json({ error: "stripe error", detail: err }, 500);
  }

  const session = await res.json() as { url: string; id: string };
  return json({ url: session.url, session_id: session.id });
}

async function handleBillingActivate(request: Request, env: Env): Promise<Response> {
  const body = await parseBody(request);
  if (!body) return json({ error: "invalid json" }, 400);

  const sessionId = body.session_id as string;
  if (!sessionId) return json({ error: "session_id required" }, 400);

  const existingToken = await env.LICENSES.get(`session:${sessionId}`);
  if (existingToken) {
    const existing = await env.LICENSES.get(`license:${existingToken}`);
    if (existing) return json({ token: existingToken, ...JSON.parse(existing) });
  }

  const res = await fetch(`https://api.stripe.com/v1/checkout/sessions/${sessionId}?expand[]=subscription`, {
    headers: { Authorization: `Bearer ${env.STRIPE_SECRET_KEY}` },
  });

  if (!res.ok) return json({ error: "invalid session" }, 400);

  const session = await res.json() as StripeCheckoutSession;

  if (session.payment_status !== "paid") {
    return json({ error: "payment not completed" }, 402);
  }

  const email = session.customer_details?.email ?? "";
  const plan = session.subscription?.metadata?.plan ?? "pro";
  const cycle = session.subscription?.metadata?.cycle ?? "monthly";
  const token = crypto.randomUUID().replace(/-/g, "").toUpperCase();

  const licenseData: LicenseData = {
    plan,
    cycle,
    email,
    customer_id: session.customer as string,
    subscription_id: session.subscription?.id ?? "",
    valid_until: nextRenewalDate(cycle),
    status: "active",
    activated_at: new Date().toISOString(),
  };

  await env.LICENSES.put(`license:${token}`, JSON.stringify(licenseData));
  await env.LICENSES.put(`session:${sessionId}`, token);
  await env.LICENSES.put(`email:${email}`, token);

  return json({ token, ...licenseData });
}

async function handleBillingStatus(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const token = url.searchParams.get("token");
  if (!token) return json({ error: "token required" }, 400);

  const raw = await env.LICENSES.get(`license:${token}`);
  if (!raw) return json({ valid: false, error: "license not found" }, 404);

  const license = JSON.parse(raw) as LicenseData;

  if (license.subscription_id) {
    const subRes = await fetch(`https://api.stripe.com/v1/subscriptions/${license.subscription_id}`, {
      headers: { Authorization: `Bearer ${env.STRIPE_SECRET_KEY}` },
    });
    if (subRes.ok) {
      const sub = await subRes.json() as { status: string; current_period_end: number };
      license.valid_until = new Date(sub.current_period_end * 1000).toISOString();
      license.status = sub.status === "active" || sub.status === "trialing" ? "active" : "expired";
      await env.LICENSES.put(`license:${token}`, JSON.stringify(license));
    }
  }

  return json({ valid: license.status === "active", ...license });
}

async function handleBillingWebhook(request: Request, env: Env): Promise<Response> {
  const signature = request.headers.get("stripe-signature") ?? "";
  const rawBody = await request.text();

  if (!await verifyStripeSignature(rawBody, signature, env.STRIPE_WEBHOOK_SECRET)) {
    return json({ error: "invalid signature" }, 400);
  }

  const event = JSON.parse(rawBody) as StripeEvent;

  if (event.type === "customer.subscription.deleted" || event.type === "customer.subscription.updated") {
    const sub = event.data.object as { id: string; status: string };
    await updateLicenseBySubscription(sub.id, sub.status, env);
  }

  return json({ received: true });
}

async function updateLicenseBySubscription(subscriptionId: string, status: string, env: Env): Promise<void> {
  const list = await env.LICENSES.list({ prefix: "license:" });
  for (const key of list.keys) {
    const raw = await env.LICENSES.get(key.name);
    if (!raw) continue;
    const license = JSON.parse(raw) as LicenseData;
    if (license.subscription_id === subscriptionId) {
      license.status = status === "active" || status === "trialing" ? "active" : "expired";
      await env.LICENSES.put(key.name, JSON.stringify(license));
      break;
    }
  }
}

function nextRenewalDate(cycle: string): string {
  const date = new Date();
  if (cycle === "yearly") {
    date.setFullYear(date.getFullYear() + 1);
  } else {
    date.setMonth(date.getMonth() + 1);
  }
  return date.toISOString();
}

async function verifyStripeSignature(payload: string, header: string, secret: string): Promise<boolean> {
  try {
    const parts = Object.fromEntries(header.split(",").map(p => p.split("=")));
    const timestamp = parts["t"];
    const signature = parts["v1"];
    if (!timestamp || !signature) return false;

    const signedPayload = `${timestamp}.${payload}`;
    const key = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(secret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(signedPayload));
    const computed = Array.from(new Uint8Array(mac)).map(b => b.toString(16).padStart(2, "0")).join("");
    return computed === signature;
  } catch {
    return false;
  }
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

interface LicenseData {
  plan: string;
  cycle: string;
  email: string;
  customer_id: string;
  subscription_id: string;
  valid_until: string;
  status: "active" | "expired";
  activated_at: string;
}

interface StripeCheckoutSession {
  id: string;
  payment_status: string;
  customer: string;
  customer_details?: { email: string };
  subscription?: { id: string; metadata: Record<string, string> };
}

interface StripeEvent {
  type: string;
  data: { object: unknown };
}

async function handleInstallationToken(request: Request, env: Env): Promise<Response> {
  const body = await parseBody(request);
  if (!body) return json({ error: "invalid json" }, 400);

  const accessToken = body.access_token;
  const targetLogin = typeof body.target_login === "string" && body.target_login.length > 0 ? body.target_login : null;
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

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
