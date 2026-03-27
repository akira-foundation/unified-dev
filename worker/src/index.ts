export interface Env {
  GITHUB_CLIENT_ID: string;
  GITHUB_CLIENT_SECRET: string;
  STRIPE_SECRET_KEY: string;
  STRIPE_WEBHOOK_SECRET: string;
  LICENSES: KVNamespace;
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
    if (url.pathname === "/billing/checkout") return handleBillingCheckout(request, env);
    if (url.pathname === "/billing/activate") return handleBillingActivate(request, env);

    return json({ error: "not found" }, 404);
  },
};

const PLAN_PRICES: Record<string, Record<string, string>> = {
  developer: {
    monthly: "price_developer_monthly",
    yearly: "price_developer_yearly",
  },
  team: {
    monthly: "price_team_monthly",
    yearly: "price_team_yearly",
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
  const plan = session.subscription?.metadata?.plan ?? "developer";
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
  if (!tokenRes) return json({ error: "internal error" }, 500);

  const userRes = await fetch("https://api.github.com/user", {
    headers: {
      Authorization: `Bearer ${tokenRes.access_token}`,
      Accept: "application/vnd.github+json",
      "User-Agent": "Akira/1.0",
    },
  });

  if (!userRes.ok) return json({ error: "internal error" }, 500);

  const user = await userRes.json() as { login: string; type: string };
  const expiresAt = tokenRes.expires_in ? Math.floor(Date.now() / 1000) + tokenRes.expires_in : null;

  return json({
    access_token: tokenRes.access_token,
    refresh_token: tokenRes.refresh_token ?? null,
    expires_at: expiresAt,
    account_login: user.login,
    account_type: user.type,
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
    client_id: env.GITHUB_CLIENT_ID,
    client_secret: env.GITHUB_CLIENT_SECRET,
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

async function exchangeCode(code: string, env: Env): Promise<OAuthTokenResponse | null> {
  const params = new URLSearchParams({
    client_id: env.GITHUB_CLIENT_ID,
    client_secret: env.GITHUB_CLIENT_SECRET,
    code,
  });

  const res = await fetch("https://github.com/login/oauth/access_token", {
    method: "POST",
    headers: { Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded" },
    body: params.toString(),
  });

  if (!res.ok) return null;

  const data = await res.json() as OAuthTokenResponse;
  if ("error" in data) return null;

  return data;
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
