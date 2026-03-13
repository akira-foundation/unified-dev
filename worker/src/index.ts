export interface Env {
  GITHUB_CLIENT_ID: string;
  GITHUB_CLIENT_SECRET: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method !== "POST") {
      return json({ error: "method not allowed" }, 405);
    }

    if (request.headers.get("Content-Type") !== "application/json") {
      return json({ error: "content-type must be application/json" }, 415);
    }

    const url = new URL(request.url);

    if (url.pathname === "/github/connect") {
      return handleConnect(request, env);
    }

    if (url.pathname === "/github/refresh") {
      return handleRefresh(request, env);
    }

    return json({ error: "not found" }, 404);
  },
};

// Exchanges an OAuth code for tokens + account info.
// Called once during GitHub App installation.
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

  const expiresAt = tokenRes.expires_in
    ? Math.floor(Date.now() / 1000) + tokenRes.expires_in
    : null;

  return json({
    access_token: tokenRes.access_token,
    refresh_token: tokenRes.refresh_token ?? null,
    expires_at: expiresAt,
    account_login: user.login,
    account_type: user.type,
  });
}

// Exchanges a refresh token for new tokens.
// Called when the access token expires (every 8h if expiration is enabled).
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
    headers: {
      Accept: "application/json",
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: params.toString(),
  });

  if (!res.ok) return json({ error: "internal error" }, 500);

  const data = await res.json() as OAuthTokenResponse;
  if ("error" in data) return json({ error: "internal error" }, 500);

  const expiresAt = data.expires_in
    ? Math.floor(Date.now() / 1000) + data.expires_in
    : null;

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
    headers: {
      Accept: "application/json",
      "Content-Type": "application/x-www-form-urlencoded",
    },
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
