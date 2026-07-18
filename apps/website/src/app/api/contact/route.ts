import { NextResponse } from "next/server";
import { createClient as createServiceClient } from "@supabase/supabase-js";

/**
 * POST /api/contact — public demo-request form on the marketing site.
 * Inserts straight into the same `leads` table apps/admin's sales pipeline
 * already reads from, tagged source: "website" so reps can filter on it.
 */
export async function POST(req: Request) {
  const body = await req.json().catch(() => null);
  if (!body?.shopName || !body?.phone) {
    return NextResponse.json({ error: "Shop name and phone number are required." }, { status: 400 });
  }

  const service = createServiceClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { autoRefreshToken: false, persistSession: false } }
  );

  const { error } = await service.from("leads").insert({
    shop_name: String(body.shopName).slice(0, 200),
    contact_name: String(body.contactName ?? "").slice(0, 200),
    phone: String(body.phone).slice(0, 30),
    email: String(body.email ?? "").slice(0, 200),
    city: String(body.city ?? "").slice(0, 100),
    notes: String(body.notes ?? "").slice(0, 2000),
    source: "website",
  });

  if (error) {
    return NextResponse.json({ error: "Could not submit your request. Please try again." }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
