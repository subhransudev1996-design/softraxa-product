import { NextResponse } from "next/server";
import { createServerSupabase } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/invite";

type Check = { key: string; ok: boolean | null; detail: string };

async function probe(url: string, init: RequestInit = {}): Promise<number | null> {
  try {
    const res = await fetch(url, { ...init, cache: "no-store", signal: AbortSignal.timeout(8000) });
    return res.status;
  } catch {
    return null;
  }
}

/**
 * GET /api/health — setup checks only the admin server can make (its own
 * settings, email sending, the website, the Edge Functions). The database
 * checks come from get_system_health() (migration 0053). Never returns a
 * secret, only whether it is set and working.
 */
export async function GET() {
  const supabase = await createServerSupabase();
  const admin = await requireAdmin(supabase);
  if (!admin.ok) return NextResponse.json({ error: admin.error }, { status: admin.status });

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
  const resendKey = process.env.RESEND_API_KEY ?? "";
  const emailFrom = process.env.EMAIL_FROM ?? "";
  const website = (process.env.WEBSITE_URL ?? "").replace(/\/$/, "");
  const checks: Check[] = [];

  checks.push({
    key: "service_key",
    ok: serviceKey.length > 20,
    detail: serviceKey ? "Set" : "SUPABASE_SERVICE_ROLE_KEY is missing — creating clients and suspending won't work",
  });

  // Welcome / set-password emails (Resend): key set and sender domain verified.
  if (!resendKey) {
    checks.push({ key: "email", ok: false, detail: "RESEND_API_KEY is not set — set-password links must be shared by hand" });
  } else {
    const domain = (emailFrom.match(/@([^>\s]+)/)?.[1] ?? "").toLowerCase();
    try {
      const res = await fetch("https://api.resend.com/domains", {
        headers: { Authorization: `Bearer ${resendKey}` },
        cache: "no-store",
        signal: AbortSignal.timeout(8000),
      });
      if (!res.ok) {
        checks.push({ key: "email", ok: false, detail: `Resend rejected the key (HTTP ${res.status})` });
      } else {
        const json = (await res.json()) as { data?: { name: string; status: string }[] };
        const d = json.data?.find((x) => x.name.toLowerCase() === domain);
        checks.push({
          key: "email",
          ok: d?.status === "verified",
          detail: !domain
            ? "EMAIL_FROM is not set"
            : d
              ? `Sender domain ${domain} is ${d.status}`
              : `Sender domain ${domain} isn't added in Resend`,
        });
      }
    } catch {
      checks.push({ key: "email", ok: null, detail: "Couldn't reach Resend to check" });
    }
  }

  // The website page that opens set-password and signup links.
  if (!website) {
    checks.push({ key: "website", ok: false, detail: "WEBSITE_URL is not set — links fall back to https://dukania.softraxa.com" });
  } else {
    const status = await probe(`${website}/auth/callback`);
    checks.push({
      key: "website",
      ok: status === 200,
      detail: status === 200 ? `${website}/auth/callback answers` : `${website}/auth/callback ${status ? `returned HTTP ${status}` : "didn't answer"}`,
    });
  }

  // Edge Functions: a deployed function answers (405 for a GET); a missing one is 404.
  for (const fn of ["push-alerts", "approval-push", "support-push"]) {
    const status = url ? await probe(`${url}/functions/v1/${fn}`, { headers: { Authorization: `Bearer ${serviceKey}` } }) : null;
    checks.push({
      key: `fn_${fn}`,
      ok: status === null ? null : status !== 404,
      detail: status === 404 ? `${fn} is not deployed` : status === null ? `Couldn't reach ${fn}` : `${fn} is deployed`,
    });
  }

  return NextResponse.json({ checks });
}
