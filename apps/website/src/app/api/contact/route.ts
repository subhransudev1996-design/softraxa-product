import { NextResponse } from "next/server";
import { createClient as createServiceClient } from "@supabase/supabase-js";

/**
 * POST /api/contact — public demo-request form on the marketing site.
 * Inserts straight into the same `leads` table apps/admin's sales pipeline
 * already reads from, tagged source: "website" so reps can filter on it.
 *
 * Abuse protection (PROJECT_ANALYSIS finding 20): a hidden honeypot field,
 * basic input validation and a per-IP rate limit. The limiter is in memory,
 * so it is per server instance — a first line of defence, not a guarantee;
 * add a CAPTCHA or edge rate limiting if spam gets through.
 */

const WINDOW_MS = 10 * 60 * 1000;
const MAX_PER_WINDOW = 5;
const hits = new Map<string, number[]>();

function rateLimited(ip: string): boolean {
  const now = Date.now();
  const recent = (hits.get(ip) ?? []).filter((t) => now - t < WINDOW_MS);
  recent.push(now);
  hits.set(ip, recent);
  if (hits.size > 5000) {
    for (const [key, times] of hits) {
      if (times.every((t) => now - t >= WINDOW_MS)) hits.delete(key);
    }
  }
  return recent.length > MAX_PER_WINDOW;
}

export async function POST(req: Request) {
  const body = await req.json().catch(() => null);

  // Bots fill every field, including the invisible "website" one. Pretend
  // success so they don't retry.
  if (body?.website) return NextResponse.json({ ok: true });

  const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || "unknown";
  if (rateLimited(ip)) {
    return NextResponse.json({ error: "Too many requests. Please try again in a few minutes." }, { status: 429 });
  }

  const shopName = String(body?.shopName ?? "").trim();
  const phone = String(body?.phone ?? "").replace(/[\s-]/g, "");
  const email = String(body?.email ?? "").trim();
  if (!shopName || !phone) {
    return NextResponse.json({ error: "Shop name and phone number are required." }, { status: 400 });
  }
  if (!/^\+?\d{10,13}$/.test(phone)) {
    return NextResponse.json({ error: "Enter a valid phone number." }, { status: 400 });
  }
  if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    return NextResponse.json({ error: "Enter a valid email address." }, { status: 400 });
  }

  const service = createServiceClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { autoRefreshToken: false, persistSession: false } }
  );

  const { error } = await service.from("leads").insert({
    shop_name: shopName.slice(0, 200),
    contact_name: String(body?.contactName ?? "").slice(0, 200),
    phone: phone.slice(0, 30),
    email: email.slice(0, 200),
    city: String(body?.city ?? "").slice(0, 100),
    notes: String(body?.notes ?? "").slice(0, 2000),
    source: "website",
  });

  if (error) {
    return NextResponse.json({ error: "Could not submit your request. Please try again." }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
