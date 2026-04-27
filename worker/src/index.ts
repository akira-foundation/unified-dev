export interface Env {
  GITHUB_CLIENT_ID: string;
  GITHUB_CLIENT_SECRET: string;
  GITHUB_OAUTH_CLIENT_ID?: string;
  GITHUB_OAUTH_CLIENT_SECRET?: string;
  GITHUB_APP_ID: string;
  GITHUB_PRIVATE_KEY: string;
  STRIPE_SECRET_KEY: string;
  STRIPE_WEBHOOK_SECRET: string;
  USAGE_HMAC_SECRET: string;
  MAILGUN_API_KEY: string;
  MAILGUN_DOMAIN: string;
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

    // Handle CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    if (request.method === "POST" && url.pathname === "/billing/webhook") {
      return handleBillingWebhook(request, env);
    }

    if (request.method === "GET" && url.pathname === "/billing/status") {
      return handleBillingStatus(request, env);
    }

    if (request.method === "GET" && url.pathname === "/billing/poll") {
      return handleBillingPoll(request, env);
    }

    if (request.method === "GET" && url.pathname === "/billing/invoices") {
      return handleBillingInvoices(request, env);
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
    if (url.pathname === "/billing/checkout") return handleBillingCheckout(request, env);
    if (url.pathname === "/billing/activate") return handleBillingActivate(request, env);
    if (url.pathname === "/billing/verify") return handleBillingVerify(request, env);
    if (url.pathname === "/billing/downgrade") return handleBillingDowngrade(request, env);
    if (url.pathname === "/billing/claim/request") return handleBillingClaimRequest(request, env);
    if (url.pathname === "/billing/claim/verify") return handleBillingClaimVerify(request, env);
    if (url.pathname === "/billing/portal") return handleBillingPortal(request, env);
    if (url.pathname === "/billing/usage") return handleBillingUsage(request, env);
    if (url.pathname === "/billing/feature_check") return handleBillingFeatureCheck(request, env);

    return json({ error: "not found" }, 404);
  },
};

const PLAN_PRICES: Record<string, Record<string, string>> = {
  pro: {
    monthly: "price_1TN1Bn5rHPk2eGVSkJf2gmg9",
    yearly: "price_1TN1Bn5rHPk2eGVStZxBDICB",
  },
  ultimate: {
    monthly: "price_1TN1Bo5rHPk2eGVSJe1m6Sk4",
    yearly: "price_1TN1Bm5rHPk2eGVSnFrv1XfO",
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

  const machineId = body.machine_id as string | undefined;

  const existingToken = await env.LICENSES.get(`session:${sessionId}`);
  if (existingToken) {
    const existing = await env.LICENSES.get(`license:${existingToken}`);
    if (existing) {
      const existingData = JSON.parse(existing) as LicenseData;
      if (!existingData.machines) existingData.machines = [];
      if (machineId && !existingData.machines.includes(machineId)) {
        if (existingData.machines.length >= 2) {
          return json({ error: "device_limit_reached" }, 403);
        }
        existingData.machines.push(machineId);
        await env.LICENSES.put(`license:${existingToken}`, JSON.stringify(existingData));
      }
      const signature = await signLicense(existingToken, existingData.plan, existingData.cycle, existingData.valid_until, existingData.email);
      return json({ token: existingToken, signature, ...existingData });
    }
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
    machines: machineId ? [machineId] : [],
  };

  await env.LICENSES.put(`license:${token}`, JSON.stringify(licenseData));
  await env.LICENSES.put(`session:${sessionId}`, token);
  await env.LICENSES.put(`email:${email}`, token);
  if (licenseData.customer_id) {
    await env.LICENSES.put(`customer:${licenseData.customer_id}`, token);
  }
  if (licenseData.subscription_id) {
    await env.LICENSES.put(`subscription:${licenseData.subscription_id}`, token);
  }

  const signature = await signLicense(token, licenseData.plan, licenseData.cycle, licenseData.valid_until, licenseData.email);
  return json({ token, signature, ...licenseData });
}

async function handleBillingVerify(request: Request, env: Env): Promise<Response> {
  const body = await parseBody(request);
  if (!body) return json({ error: "invalid json" }, 400);

  const token = body.token as string | undefined;
  const machineId = body.machine_id as string | undefined;

  if (!token) return json({ error: "token required" }, 400);
  if (!machineId) return json({ error: "machine_id required" }, 400);

  const raw = await env.LICENSES.get(`license:${token}`);
  if (!raw) return json({ error: "license_not_found" }, 404);

  const license = JSON.parse(raw) as LicenseData;

  if (license.status !== "active") {
    return json({ error: "license_expired" }, 402);
  }

  if (!license.machines) license.machines = [];

  if (!license.machines.includes(machineId)) {
    if (license.machines.length >= 2) {
      return json({ error: "device_limit_reached" }, 403);
    }
    license.machines.push(machineId);
    await env.LICENSES.put(`license:${token}`, JSON.stringify(license));
  }

  const signature = await signLicense(token, license.plan, license.cycle, license.valid_until, license.email);
  return json({ token, signature, ...license });
}

async function handleBillingDowngrade(request: Request, env: Env): Promise<Response> {
  const body = await parseBody(request);
  if (!body) return json({ error: "invalid json" }, 400);

  const token = body.token as string | undefined;
  if (!token) return json({ error: "token required" }, 400);

  const targetPlan = (body.target_plan as string | undefined) ?? "free";

  const raw = await env.LICENSES.get(`license:${token}`);
  if (!raw) return json({ error: "license_not_found" }, 404);

  const license = JSON.parse(raw) as LicenseData;
  if (!license.subscription_id) return json({ error: "no_subscription" }, 400);

  if (license.cancel_at_period_end && license.target_plan === targetPlan) {
    return json({
      cancel_at_period_end: license.cancel_at_period_end,
      cancel_at: license.cancel_at,
      target_plan: license.target_plan,
    });
  }

  if (targetPlan === "pro") {
    const cycle = license.cycle ?? "monthly";
    const newPriceId = PLAN_PRICES["pro"]?.[cycle];
    if (!newPriceId) return json({ error: "invalid_cycle" }, 400);

    const subRes = await fetch(`https://api.stripe.com/v1/subscriptions/${license.subscription_id}`, {
      headers: { Authorization: `Bearer ${env.STRIPE_SECRET_KEY}` },
    });
    if (!subRes.ok) return json({ error: "stripe_error" }, 500);

    const sub = await subRes.json() as { current_period_end: number; items: { data: { price: { id: string } }[] }; schedule: string | null };
    const currentPriceId = sub.items.data[0].price.id;
    let currentPeriodEnd = sub.current_period_end;
    let scheduleId = sub.schedule;

    if (!currentPriceId) {
      return json({ error: "stripe_data_missing" }, 500);
    }

    if (!scheduleId) {
      const createRes = await fetch("https://api.stripe.com/v1/subscription_schedules", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: new URLSearchParams({
          from_subscription: license.subscription_id,
        }).toString(),
      });

      if (!createRes.ok) {
        const err = await createRes.text();
        return json({ error: "stripe_error", detail: err }, 500);
      }

      const created = await createRes.json() as { id: string; phases: { end_date: number }[] };
      scheduleId = created.id;
      if (!currentPeriodEnd && created.phases?.[0]?.end_date) {
        currentPeriodEnd = created.phases[0].end_date;
      }
    } else if (!currentPeriodEnd) {
      const schedRes = await fetch(`https://api.stripe.com/v1/subscription_schedules/${scheduleId}`, {
        headers: { Authorization: `Bearer ${env.STRIPE_SECRET_KEY}` },
      });
      if (schedRes.ok) {
        const sched = await schedRes.json() as { phases: { start_date: number; end_date: number }[] };
        currentPeriodEnd = sched.phases?.[0]?.end_date;
      }
    }

    if (!currentPeriodEnd) {
      return json({ error: "stripe_data_missing" }, 500);
    }

    const schedFetchRes = await fetch(`https://api.stripe.com/v1/subscription_schedules/${scheduleId}`, {
      headers: { Authorization: `Bearer ${env.STRIPE_SECRET_KEY}` },
    });
    if (!schedFetchRes.ok) return json({ error: "stripe_error" }, 500);
    const schedData = await schedFetchRes.json() as { phases: { start_date: number; end_date: number }[] };
    const phase0StartDate = schedData.phases?.[0]?.start_date;

    const updateRes = await fetch(`https://api.stripe.com/v1/subscription_schedules/${scheduleId}`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        end_behavior: "release",
        "phases[0][items][0][price]": currentPriceId,
        "phases[0][items][0][quantity]": "1",
        "phases[0][start_date]": String(phase0StartDate),
        "phases[0][end_date]": String(currentPeriodEnd),
        "phases[1][items][0][price]": newPriceId,
        "phases[1][items][0][quantity]": "1",
      }).toString(),
    });

    if (!updateRes.ok) {
      const err = await updateRes.text();
      return json({ error: "stripe_error", detail: err }, 500);
    }

    const cancelAt = new Date(currentPeriodEnd * 1000).toISOString();
    license.target_plan = "pro";
    license.cancel_at_period_end = true;
    license.cancel_at = cancelAt;
    await env.LICENSES.put(`license:${token}`, JSON.stringify(license));

    return json({
      cancel_at_period_end: true,
      cancel_at: cancelAt,
      target_plan: "pro",
    });
  }

  const res = await fetch(`https://api.stripe.com/v1/subscriptions/${license.subscription_id}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({ cancel_at_period_end: "true" }).toString(),
  });

  if (!res.ok) {
    const err = await res.text();
    return json({ error: "stripe_error", detail: err }, 500);
  }

  const sub = await res.json() as { current_period_end: number; cancel_at_period_end: boolean; cancel_at: number | null };

  license.cancel_at_period_end = sub.cancel_at_period_end;
  license.cancel_at = sub.cancel_at ? new Date(sub.cancel_at * 1000).toISOString() : null;
  license.target_plan = "free";
  await env.LICENSES.put(`license:${token}`, JSON.stringify(license));

  return json({
    cancel_at_period_end: sub.cancel_at_period_end,
    cancel_at: license.cancel_at,
    target_plan: "free",
  });
}

async function handleBillingClaimRequest(request: Request, env: Env): Promise<Response> {
  const body = await parseBody(request);
  if (!body) return json({ error: "invalid json" }, 400);

  const email = body.email as string | undefined;
  if (!email) return json({ error: "email required" }, 400);

  const now = new Date();
  const rateLimitKey = `otp_rate:${email}:${now.getUTCHours()}`;
  const rateLimitRaw = await env.LICENSES.get(rateLimitKey);
  const rateCount = rateLimitRaw ? parseInt(rateLimitRaw, 10) : 0;
  if (rateCount >= 3) {
    const minutesUntilNextHour = 60 - now.getUTCMinutes();
    const secondsUntilNextHour = minutesUntilNextHour * 60 - now.getUTCSeconds();
    return json({ error: "rate_limit_exceeded", retry_after: secondsUntilNextHour }, 429);
  }
  await env.LICENSES.put(rateLimitKey, String(rateCount + 1), { expirationTtl: 3600 });

  let token = await env.LICENSES.get(`email:${email}`);

  if (!token) {
    const recovered = await recoverLicenseFromStripe(email, env);
    if (!recovered) {
      return json({ sent: true });
    }
    token = recovered;
  }

  const raw = await env.LICENSES.get(`license:${token}`);
  if (!raw) return json({ sent: true });

  const license = JSON.parse(raw) as LicenseData;
  if (license.status !== "active") return json({ sent: true });

  const otp = String(Math.floor(100000 + Math.random() * 900000));
  await env.LICENSES.put(`otp:${email}`, otp, { expirationTtl: 600 });

  await sendOtpEmail(email, otp, env);

  return json({ sent: true });
}

async function recoverLicenseFromStripe(email: string, env: Env): Promise<string | null> {
  const searchRes = await fetch(
    `https://api.stripe.com/v1/customers/search?query=email:'${encodeURIComponent(email)}'&limit=5`,
    { headers: { Authorization: `Bearer ${env.STRIPE_SECRET_KEY}` } },
  );
  if (!searchRes.ok) return null;

  const searchData = await searchRes.json() as { data: Array<{ id: string }> };
  if (!searchData.data.length) return null;

  for (const customer of searchData.data) {
    const subRes = await fetch(
      `https://api.stripe.com/v1/subscriptions?customer=${customer.id}&status=active&limit=1&expand[]=data.items.data.price.product`,
      { headers: { Authorization: `Bearer ${env.STRIPE_SECRET_KEY}` } },
    );
    if (!subRes.ok) continue;

    const subData = await subRes.json() as { data: Array<StripeSubscription> };
    if (!subData.data.length) continue;

    const sub = subData.data[0];
    const plan = sub.metadata?.plan ?? inferPlanFromSubscription(sub);
    const cycle = sub.metadata?.cycle ?? inferCycleFromSubscription(sub);
    const token = crypto.randomUUID().replace(/-/g, "").toUpperCase();

    const licenseData: LicenseData = {
      plan,
      cycle,
      email,
      customer_id: customer.id,
      subscription_id: sub.id,
      valid_until: new Date(sub.current_period_end * 1000).toISOString(),
      status: "active",
      activated_at: new Date().toISOString(),
      machines: [],
    };

    await env.LICENSES.put(`license:${token}`, JSON.stringify(licenseData));
    await env.LICENSES.put(`email:${email}`, token);
    await env.LICENSES.put(`customer:${customer.id}`, token);
    await env.LICENSES.put(`subscription:${sub.id}`, token);

    return token;
  }

  return null;
}

function inferPlanFromSubscription(sub: StripeSubscription): string {
  const item = sub.items?.data?.[0];
  const productName = (item?.price?.product as { name?: string } | undefined)?.name?.toLowerCase() ?? "";
  if (productName.includes("ultimate")) return "ultimate";
  return "pro";
}

function inferCycleFromSubscription(sub: StripeSubscription): string {
  const item = sub.items?.data?.[0];
  const interval = item?.price?.recurring?.interval;
  return interval === "year" ? "yearly" : "monthly";
}

async function handleBillingClaimVerify(request: Request, env: Env): Promise<Response> {
  const body = await parseBody(request);
  if (!body) return json({ error: "invalid json" }, 400);

  const email = body.email as string | undefined;
  const otp = body.otp as string | undefined;
  const machineId = body.machine_id as string | undefined;

  if (!email) return json({ error: "email required" }, 400);
  if (!otp) return json({ error: "otp required" }, 400);
  if (!machineId) return json({ error: "machine_id required" }, 400);

  const verifyRateKey = `otp_verify_rate:${email}`;
  const verifyRateRaw = await env.LICENSES.get(verifyRateKey);
  const verifyCount = verifyRateRaw ? parseInt(verifyRateRaw, 10) : 0;
  if (verifyCount >= 5) {
    await env.LICENSES.delete(`otp:${email}`);
    return json({ error: "otp_brute_force" }, 429);
  }

  const storedOtp = await env.LICENSES.get(`otp:${email}`);
  if (!storedOtp) return json({ error: "otp_expired" }, 410);

  if (storedOtp !== otp) {
    await env.LICENSES.put(verifyRateKey, String(verifyCount + 1), { expirationTtl: 600 });
    return json({ error: "otp_invalid" }, 400);
  }

  await env.LICENSES.delete(`otp:${email}`);
  await env.LICENSES.delete(verifyRateKey);

  const token = await env.LICENSES.get(`email:${email}`);
  if (!token) return json({ error: "email_not_found" }, 404);

  const raw = await env.LICENSES.get(`license:${token}`);
  if (!raw) return json({ error: "email_not_found" }, 404);

  const license = JSON.parse(raw) as LicenseData;
  if (license.status !== "active") return json({ error: "license_expired" }, 402);

  if (!license.machines) license.machines = [];

  if (!license.machines.includes(machineId)) {
    if (license.machines.length >= 2) return json({ error: "device_limit_reached" }, 403);
    license.machines.push(machineId);
    await env.LICENSES.put(`license:${token}`, JSON.stringify(license));
  }

  const signature = await signLicense(token, license.plan, license.cycle, license.valid_until, license.email);
  return json({ token, signature, ...license });
}

async function sendOtpEmail(email: string, otp: string, env: Env): Promise<void> {
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Your activation code</title>
</head>
<body style="margin:0;padding:0;background:#0a0a0a;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#0a0a0a;padding:40px 16px;">
    <tr>
      <td align="center">
        <table width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;">
          <tr>
            <td style="padding-bottom:32px;" align="center">
              <span style="font-size:18px;font-weight:700;color:#ffffff;letter-spacing:-0.5px;">Unified Dev</span>
            </td>
          </tr>
          <tr>
            <td style="background:#141414;border:1px solid #222;border-radius:12px;padding:40px 36px;">
              <p style="margin:0 0 8px;font-size:13px;font-weight:600;color:#a1a1aa;text-transform:uppercase;letter-spacing:0.8px;">License Activation</p>
              <h1 style="margin:0 0 24px;font-size:22px;font-weight:700;color:#ffffff;line-height:1.3;">Your verification code</h1>
              <p style="margin:0 0 28px;font-size:14px;color:#71717a;line-height:1.6;">
                Use the code below to activate your Unified Dev license. It expires in <strong style="color:#a1a1aa;">10 minutes</strong>.
              </p>
              <div style="background:#0a0a0a;border:1px solid #333;border-radius:8px;padding:24px;text-align:center;margin-bottom:28px;">
                <span style="font-size:36px;font-weight:700;color:#ffffff;letter-spacing:10px;font-variant-numeric:tabular-nums;">${otp}</span>
              </div>
              <p style="margin:0;font-size:12px;color:#52525b;line-height:1.6;">
                If you did not request this code, you can safely ignore this email. Someone may have entered your email address by mistake.
              </p>
            </td>
          </tr>
          <tr>
            <td style="padding-top:24px;" align="center">
              <p style="margin:0;font-size:11px;color:#3f3f46;">
                &copy; ${new Date().getFullYear()} Unified Dev &middot; noreply@akira-io.com
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

  const form = new URLSearchParams({
    from: `Unified Dev <noreply@akira-io.com>`,
    to: email,
    subject: `Your Unified Dev activation code: ${otp}`,
    text: `Your Unified Dev license activation code is: ${otp}\n\nThis code expires in 10 minutes.\n\nIf you did not request this, you can safely ignore this email.`,
    html,
  });

  await fetch(`https://api.mailgun.net/v3/${env.MAILGUN_DOMAIN}/messages`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${btoa(`api:${env.MAILGUN_API_KEY}`)}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: form.toString(),
  });
}

async function handleBillingUsage(request: Request, env: Env): Promise<Response> {
  const body = await parseBody(request);
  if (!body) return json({ error: "invalid json" }, 400);

  const machineId = body.machine_id as string | undefined;
  const token = body.token as string | undefined;
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

  const bindingKey = `machine:${machineId}`;
  const existingToken = await env.LICENSES.get(bindingKey);
  const effectiveToken = token ?? "";

  if (existingToken === null) {
    await env.LICENSES.put(bindingKey, effectiveToken);
  } else if (existingToken !== effectiveToken) {
    return json({ error: "machine_id_token_mismatch" }, 403);
  }

  const raw = effectiveToken ? await env.LICENSES.get(`license:${effectiveToken}`) : null;
  const plan = raw ? (JSON.parse(raw) as LicenseData).plan : "free";

  if (plan === "pro" || plan === "ultimate") {
    return json({ allowed: true, count: 0, limit: null, created_at_sig: null });
  }

  const createdAtKey = `created_at:${machineId}`;
  let storedCreatedAt = await env.LICENSES.get(createdAtKey);

  if (storedCreatedAt === null) {
    storedCreatedAt = new Date().toISOString();
    await env.LICENSES.put(createdAtKey, storedCreatedAt);
  } else if (createdAtSig) {
    const expectedSig = await hmacSign(env.USAGE_HMAC_SECRET, `${machineId}:${storedCreatedAt}`);
    if (createdAtSig !== expectedSig) {
      return json({ error: "created_at_sig_invalid" }, 403);
    }
  }

  const newCreatedAtSig = await hmacSign(env.USAGE_HMAC_SECRET, `${machineId}:${storedCreatedAt}`);

  const usageKey = `usage:${machineId}:${date}`;
  const DAILY_LIMIT = 5;

  const existing = await env.LICENSES.get(usageKey);
  const count = existing ? parseInt(existing, 10) : 0;

  if (action === "check") {
    return json({ allowed: count < DAILY_LIMIT, count, limit: DAILY_LIMIT, created_at_sig: newCreatedAtSig });
  }

  if (count >= DAILY_LIMIT) {
    return json({ allowed: false, count, limit: DAILY_LIMIT, created_at_sig: newCreatedAtSig });
  }

  const newCount = count + 1;
  await env.LICENSES.put(usageKey, String(newCount), { expirationTtl: 172800 });

  return json({ allowed: true, count: newCount, limit: DAILY_LIMIT, created_at_sig: newCreatedAtSig });
}

const FEATURE_PLAN_REQUIREMENTS: Record<string, string[]> = {
  autopilot: ["pro", "ultimate"],
  remote: ["ultimate"],
};

async function handleBillingFeatureCheck(request: Request, env: Env): Promise<Response> {
  const body = await parseBody(request);
  if (!body) return json({ error: "invalid json" }, 400);

  const machineId = body.machine_id as string | undefined;
  const token = body.token as string | undefined;
  const feature = body.feature as string | undefined;

  if (!machineId || !feature) {
    return json({ error: "machine_id and feature are required" }, 400);
  }

  const required = FEATURE_PLAN_REQUIREMENTS[feature];
  if (!required) {
    return json({ error: "unknown feature" }, 400);
  }

  const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const ipKey = `ip_rate:${ip}:${new Date().toISOString().slice(0, 10)}:${new Date().getUTCHours()}`;
  const ipCountRaw = await env.LICENSES.get(ipKey);
  const ipCount = ipCountRaw ? parseInt(ipCountRaw, 10) : 0;
  const IP_HOURLY_LIMIT = 240;
  if (ipCount >= IP_HOURLY_LIMIT) {
    return json({ error: "rate_limit_exceeded" }, 429);
  }
  await env.LICENSES.put(ipKey, String(ipCount + 1), { expirationTtl: 7200 });

  const bindingKey = `machine:${machineId}`;
  const existingToken = await env.LICENSES.get(bindingKey);
  const effectiveToken = token ?? "";

  if (existingToken === null) {
    await env.LICENSES.put(bindingKey, effectiveToken);
  } else if (existingToken !== effectiveToken) {
    return json({ error: "machine_id_token_mismatch" }, 403);
  }

  const raw = effectiveToken ? await env.LICENSES.get(`license:${effectiveToken}`) : null;
  const plan = raw ? (JSON.parse(raw) as LicenseData).plan : "free";

  const allowed = required.includes(plan);
  return json({ allowed, plan, feature, required });
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

async function handleBillingPortal(request: Request, env: Env): Promise<Response> {
  const body = await parseBody(request);
  if (!body) return json({ error: "invalid json" }, 400);

  const token = body.token as string;
  if (!token) return json({ error: "token required" }, 400);

  const raw = await env.LICENSES.get(`license:${token}`);
  if (!raw) return json({ error: "license not found" }, 404);

  const license = JSON.parse(raw) as LicenseData;
  if (!license.customer_id) return json({ error: "no customer on file" }, 400);

  const params = new URLSearchParams({
    customer: license.customer_id,
    return_url: "akira://settings",
  });

  const res = await fetch("https://api.stripe.com/v1/billing_portal/sessions", {
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

  const session = await res.json() as { url: string };
  return json({ url: session.url });
}

async function handleBillingInvoices(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const token = url.searchParams.get("token");
  if (!token) return json({ error: "token required" }, 400);

  const startingAfter = url.searchParams.get("starting_after");

  const raw = await env.LICENSES.get(`license:${token}`);
  if (!raw) return json({ error: "license not found" }, 404);

  const license = JSON.parse(raw) as LicenseData;
  if (!license.email) return json({ invoices: [], hasMore: false, nextCursor: null });

  // Fetch all Stripe customers with this email
  const customersRes = await fetch(
    `https://api.stripe.com/v1/customers?email=${encodeURIComponent(license.email)}&limit=100`,
    { headers: { Authorization: `Bearer ${env.STRIPE_SECRET_KEY}` } }
  );
  if (!customersRes.ok) {
    const err = await customersRes.text();
    return json({ error: `stripe customers error: ${err}` }, 500);
  }
  const customersData = await customersRes.json() as { data: Array<{ id: string }> };
  const customerIds = customersData.data.map(c => c.id);
  if (customerIds.length === 0) return json({ invoices: [], hasMore: false, nextCursor: null });

  type StripeInvoice = {
    id: string;
    number: string | null;
    amount_paid: number;
    currency: string;
    status: string;
    created: number;
    invoice_pdf: string | null;
    hosted_invoice_url: string | null;
    period_start: number;
    period_end: number;
  };

  // Fetch invoices for all customers in parallel (first page only uses startingAfter on primary customer)
  const pages = await Promise.all(customerIds.map(async (customerId) => {
    const params = new URLSearchParams({ customer: customerId, limit: "100", status: "paid" });
    if (startingAfter && customerId === customerIds[0]) params.set("starting_after", startingAfter);
    const res = await fetch(`https://api.stripe.com/v1/invoices?${params.toString()}`, {
      headers: { Authorization: `Bearer ${env.STRIPE_SECRET_KEY}` },
    });
    if (!res.ok) return { data: [] as StripeInvoice[], has_more: false };
    return res.json() as Promise<{ data: StripeInvoice[]; has_more: boolean }>;
  }));

  // Merge and sort all invoices by date descending
  const allInvoices = pages.flatMap(p => p.data).filter(inv => inv.amount_paid > 0);
  allInvoices.sort((a, b) => b.created - a.created);

  const PAGE_SIZE = 10;
  const offset = 0;
  const page = allInvoices.slice(offset, PAGE_SIZE);
  const hasMore = allInvoices.length > PAGE_SIZE;
  const nextCursor = hasMore ? page[page.length - 1].id : null;

  const invoices = page.map(inv => ({
    id: inv.id,
    number: inv.number,
    amount: inv.amount_paid,
    currency: inv.currency,
    date: new Date(inv.created * 1000).toISOString(),
    periodStart: new Date(inv.period_start * 1000).toISOString(),
    periodEnd: new Date(inv.period_end * 1000).toISOString(),
    pdfUrl: inv.invoice_pdf,
    hostedUrl: inv.hosted_invoice_url,
  }));

  return json({ invoices, hasMore, nextCursor });
}

async function handleBillingPoll(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const sessionId = url.searchParams.get("session_id");
  if (!sessionId) return json({ error: "session_id required" }, 400);

  const existingToken = await env.LICENSES.get(`session:${sessionId}`);
  if (existingToken) {
    return json({ paid: true });
  }

  const res = await fetch(`https://api.stripe.com/v1/checkout/sessions/${sessionId}`, {
    headers: { Authorization: `Bearer ${env.STRIPE_SECRET_KEY}` },
  });

  if (!res.ok) return json({ paid: false });

  const session = await res.json() as { payment_status: string };
  return json({ paid: session.payment_status === "paid" });
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
      const sub = await subRes.json() as { status: string; current_period_end: number; cancel_at_period_end: boolean; cancel_at: number | null };
      license.valid_until = new Date(sub.current_period_end * 1000).toISOString();
      license.status = sub.status === "active" || sub.status === "trialing" ? "active" : "expired";
      await env.LICENSES.put(`license:${token}`, JSON.stringify(license));
      return json({
        valid: license.status === "active",
        cancel_at_period_end: sub.cancel_at_period_end,
        cancel_at: sub.cancel_at ? new Date(sub.cancel_at * 1000).toISOString() : null,
        target_plan: license.target_plan ?? null,
        signature: await signLicense(token, license.plan, license.cycle, license.valid_until, license.email),
        ...license,
      });
    }
  }

  return json({ valid: license.status === "active", cancel_at_period_end: false, cancel_at: null, target_plan: license.target_plan ?? null, signature: await signLicense(token, license.plan, license.cycle, license.valid_until, license.email), ...license });
}

async function handleBillingWebhook(request: Request, env: Env): Promise<Response> {
  const signature = request.headers.get("stripe-signature") ?? "";
  const rawBody = await request.text();

  if (!await verifyStripeSignature(rawBody, signature, env.STRIPE_WEBHOOK_SECRET)) {
    return json({ error: "invalid signature" }, 400);
  }

  const event = JSON.parse(rawBody) as StripeEvent;

  if (event.type === "invoice.created") {
    const invoice = event.data.object as { id: string; auto_advance: boolean; subscription: string | null };
    if (invoice.subscription && invoice.auto_advance === false) {
      await fetch(`https://api.stripe.com/v1/invoices/${invoice.id}/finalize`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
      });
    }
  }

  if (event.type === "customer.subscription.deleted" || event.type === "customer.subscription.updated") {
    const sub = event.data.object as { id: string; status: string; cancel_at_period_end: boolean; cancel_at: number | null; current_period_end: number; items?: { data: { price: { id: string } }[] } };
    const newPriceId = sub.items?.data?.[0]?.price?.id;
    await updateLicenseBySubscription(sub.id, sub.status, sub.cancel_at_period_end, sub.cancel_at, sub.current_period_end, newPriceId, env);
  }

  if (event.type === "invoice.payment_failed") {
    const invoice = event.data.object as { subscription: string };
    if (invoice.subscription) {
      await updateLicenseBySubscription(invoice.subscription, "past_due", false, null, undefined, undefined, env);
    }
  }

  if (event.type === "invoice.payment_succeeded") {
    const invoice = event.data.object as { subscription: string; lines: { data: Array<{ period: { end: number } }> } };
    if (invoice.subscription) {
      const periodEnd = invoice.lines?.data?.[0]?.period?.end;
      await updateLicenseBySubscriptionRenewal(invoice.subscription, periodEnd, env);
    }
  }

  return json({ received: true });
}

async function updateLicenseBySubscriptionRenewal(subscriptionId: string, periodEnd: number | undefined, env: Env): Promise<void> {
  const token = await env.LICENSES.get(`subscription:${subscriptionId}`);
  if (!token) return;

  const raw = await env.LICENSES.get(`license:${token}`);
  if (!raw) return;

  const license = JSON.parse(raw) as LicenseData;
  if (license.subscription_id !== subscriptionId) return;

  license.status = "active";
  if (periodEnd) {
    license.valid_until = new Date(periodEnd * 1000).toISOString();
  }
  await env.LICENSES.put(`license:${token}`, JSON.stringify(license));
}

async function updateLicenseBySubscription(subscriptionId: string, status: string, cancelAtPeriodEnd: boolean, cancelAt: number | null | undefined, currentPeriodEnd: number | undefined, newPriceId: string | undefined, env: Env): Promise<void> {
  const resolvedPlan = newPriceId
    ? Object.entries(PLAN_PRICES).find(([, cycles]) => Object.values(cycles).includes(newPriceId))?.[0]
    : undefined;

  const token = await env.LICENSES.get(`subscription:${subscriptionId}`);
  if (!token) return;

  const raw = await env.LICENSES.get(`license:${token}`);
  if (!raw) return;

  const license = JSON.parse(raw) as LicenseData;
  if (license.subscription_id !== subscriptionId) return;

  const newStatus = status === "active" || status === "trialing" ? "active" : "expired";
  license.status = newStatus;
  license.cancel_at_period_end = cancelAtPeriodEnd ?? false;
  license.cancel_at = cancelAt ? new Date(cancelAt * 1000).toISOString() : null;
  if (currentPeriodEnd) {
    license.valid_until = new Date(currentPeriodEnd * 1000).toISOString();
  }
  if (resolvedPlan && resolvedPlan !== license.plan) {
    license.plan = resolvedPlan;
    license.target_plan = null;
  } else if (!cancelAtPeriodEnd && license.target_plan && license.target_plan !== "free") {
    license.plan = license.target_plan;
    license.target_plan = null;
  }
  if (newStatus === "expired" && license.target_plan === "free") {
    license.target_plan = null;
  }
  await env.LICENSES.put(`license:${token}`, JSON.stringify(license));
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

    if (Math.abs(Date.now() / 1000 - parseInt(timestamp, 10)) > 300) return false;

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
  machines: string[];
  cancel_at_period_end?: boolean;
  cancel_at?: string | null;
  target_plan?: string | null;
}

async function signLicense(token: string, plan: string, cycle: string, valid_until: string, email: string): Promise<string> {
  const payload = `${plan}:${cycle}:${valid_until}:${email}`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(token),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  return Array.from(new Uint8Array(mac)).map(b => b.toString(16).padStart(2, "0")).join("");
}

interface StripeSubscription {
  id: string;
  status: string;
  current_period_end: number;
  metadata?: Record<string, string>;
  items?: {
    data: Array<{
      price: {
        recurring?: { interval: string };
        product?: unknown;
      };
    }>;
  };
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

  const latestRes = await fetch("https://unified-dev.nyc3.cdn.digitaloceanspaces.com/releases/latest.json", { cf: { cacheEverything: true, cacheTtl: 300 } } as RequestInit);
  if (!latestRes.ok) return new Response("Could not resolve latest version", { status: 502 });
  const { version } = await latestRes.json() as { version: string };

  const cdnUrl = `https://unified-dev.nyc3.cdn.digitaloceanspaces.com/releases/v${version}/unified_dev_${version}_${cdnArch}.dmg`;

  const current = await env.LICENSES.get(kvKey);
  const count = parseInt(current ?? "0", 10) + 1;
  await env.LICENSES.put(kvKey, String(count));

  return Response.redirect(cdnUrl, 302);
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}
