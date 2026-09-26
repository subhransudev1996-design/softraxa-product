// push-alerts — scheduled Supabase Edge Function that mirrors the app's
// in-app notification bell (low/out-of-stock, expired & near-expiry
// products, job cards due) and delivers a summary push per business via
// Firebase Cloud Messaging (HTTP v1 API).
//
// Setup (see PLAN.md Runbook):
//   supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat service-account.json)"
//   supabase secrets set PUSH_ALERTS_SECRET="<long random string>"
//   supabase functions deploy push-alerts --no-verify-jwt
//   Schedule it (e.g. daily 09:00 IST) as a POST with the header
//     Authorization: Bearer <PUSH_ALERTS_SECRET>
//
// Security (PROJECT_ANALYSIS finding 12): the gateway's JWT check is off
// for the scheduler, so this function authenticates the caller itself,
// accepts only POST, and runs at most once per day (push_alert_runs table,
// migration 0039) — a leaked URL can't be used to spam every device.
//
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from "npm:@supabase/supabase-js@2";

const NEAR_EXPIRY_DAYS = 30;

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

// ---------- FCM auth: service-account JWT -> OAuth access token ----------

function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importKey(pem: string): Promise<CryptoKey> {
  const raw = atob(
    pem
      .replace("-----BEGIN PRIVATE KEY-----", "")
      .replace("-----END PRIVATE KEY-----", "")
      .replace(/\s/g, ""),
  );
  const bytes = new Uint8Array([...raw].map((c) => c.charCodeAt(0)));
  return crypto.subtle.importKey(
    "pkcs8",
    bytes,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

async function fcmAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const enc = new TextEncoder();
  const header = b64url(enc.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = b64url(
    enc.encode(
      JSON.stringify({
        iss: sa.client_email,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: "https://oauth2.googleapis.com/token",
        iat: now,
        exp: now + 3600,
      }),
    ),
  );
  const key = await importKey(sa.private_key);
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    enc.encode(`${header}.${claims}`),
  );
  const jwt = `${header}.${claims}.${b64url(new Uint8Array(sig))}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error(`OAuth token exchange failed: ${await res.text()}`);
  return (await res.json()).access_token as string;
}

// ---------- Alert computation (mirrors lib/core/notifications.dart) ----------

// deno-lint-ignore no-explicit-any
async function alertLines(db: any, businessId: string): Promise<string[]> {
  const lines: string[] = [];
  const today = new Date().toISOString().slice(0, 10);
  const cutoff = new Date(Date.now() + NEAR_EXPIRY_DAYS * 86400_000)
    .toISOString()
    .slice(0, 10);

  const { count: outCount } = await db
    .from("products")
    .select("id", { count: "exact", head: true })
    .eq("business_id", businessId)
    .eq("is_active", true)
    .lte("current_stock", 0);
  if (outCount) lines.push(`${outCount} product(s) out of stock`);

  const { data: lowRows } = await db
    .from("products")
    .select("current_stock, low_stock_qty")
    .eq("business_id", businessId)
    .eq("is_active", true)
    .gt("low_stock_qty", 0)
    .gt("current_stock", 0);
  const low = (lowRows ?? []).filter(
    (r: { current_stock: number; low_stock_qty: number }) =>
      r.current_stock <= r.low_stock_qty,
  ).length;
  if (low) lines.push(`${low} product(s) low on stock`);

  const { data: expRows } = await db
    .from("products")
    .select("expiry_date")
    .eq("business_id", businessId)
    .eq("is_active", true)
    .not("expiry_date", "is", null)
    .lte("expiry_date", cutoff);
  let expired = 0, near = 0;
  for (const r of expRows ?? []) {
    if ((r.expiry_date as string) < today) expired++;
    else near++;
  }
  if (expired) lines.push(`${expired} product(s) expired`);
  if (near) lines.push(`${near} product(s) expiring within ${NEAR_EXPIRY_DAYS} days`);

  const { count: jobs } = await db
    .from("job_cards")
    .select("id", { count: "exact", head: true })
    .eq("business_id", businessId)
    .not("status", "in", "(delivered,cancelled,returned_unrepaired)")
    .lte("expected_delivery", today);
  if (jobs) lines.push(`${jobs} job card(s) due for delivery`);

  return lines;
}

// ---------- Caller authentication ----------

/** Constant-time string comparison (no early exit on the first mismatch). */
function safeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const x = enc.encode(a);
  const y = enc.encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  }
  return diff === 0;
}

function isAuthorized(req: Request): boolean {
  const secret = Deno.env.get("PUSH_ALERTS_SECRET") ?? "";
  if (secret.length < 16) return false; // not configured → refuse everyone
  const header = req.headers.get("Authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  return safeEqual(token, secret);
}

// ---------- Main ----------

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: { Allow: "POST" } });
  }
  if (!isAuthorized(req)) {
    return new Response("Unauthorized", { status: 401 });
  }

  const sa = JSON.parse(
    Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "{}",
  ) as ServiceAccount;
  if (!sa.project_id) {
    return new Response("FIREBASE_SERVICE_ACCOUNT secret not set", { status: 500 });
  }

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // At most one broadcast per day (IST), even if the scheduler retries or
  // the endpoint is called repeatedly.
  const runDate = new Date(Date.now() + 5.5 * 3600_000).toISOString().slice(0, 10);
  const { error: runError } = await db
    .from("push_alert_runs")
    .insert({ run_date: runDate });
  if (runError) {
    if (runError.code === "23505") {
      return new Response(JSON.stringify({ skipped: "already ran today", run_date: runDate }), {
        headers: { "Content-Type": "application/json" },
      });
    }
    return new Response(`run ledger failed: ${runError.message}`, { status: 500 });
  }

  const { data: tokens, error } = await db
    .from("device_tokens")
    .select("business_id, token");
  if (error) return new Response(`token query failed: ${error.message}`, { status: 500 });
  if (!tokens?.length) return new Response("no devices registered", { status: 200 });

  const byBusiness = new Map<string, string[]>();
  for (const t of tokens) {
    byBusiness.set(t.business_id, [
      ...(byBusiness.get(t.business_id) ?? []),
      t.token,
    ]);
  }

  const accessToken = await fcmAccessToken(sa);
  const fcmUrl =
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
  let sent = 0, skipped = 0, pruned = 0;

  for (const [businessId, deviceTokens] of byBusiness) {
    const lines = await alertLines(db, businessId);
    if (lines.length === 0) {
      skipped++;
      continue;
    }
    for (const token of deviceTokens) {
      const res = await fetch(fcmUrl, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            notification: {
              title: "Dukania — attention needed",
              body: lines.join(" • "),
            },
            android: {
              // Without this Android treats the push as batchable and may
              // defer it for minutes (Doze); business alerts should land
              // immediately. TTL: stop retrying after a day — a stale
              // stock alert is superseded by the next day's run anyway.
              priority: "HIGH",
              ttl: "86400s",
            },
          },
        }),
      });
      if (res.ok) {
        sent++;
      } else if (res.status === 404 || res.status === 410) {
        // Token no longer valid (app uninstalled, token rotated) — prune.
        await db.from("device_tokens").delete().eq("token", token);
        pruned++;
      }
    }
  }

  return new Response(
    JSON.stringify({ sent, businesses_quiet: skipped, tokens_pruned: pruned }),
    { headers: { "Content-Type": "application/json" } },
  );
});
