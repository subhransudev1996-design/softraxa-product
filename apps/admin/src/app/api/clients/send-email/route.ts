import { NextResponse } from "next/server";
import { createServerSupabase } from "@/lib/supabase/server";
import { sendWelcomeEmail } from "@/lib/email";
import { createServiceClient, createSetPasswordLink, requireAdmin } from "@/lib/invite";

/**
 * POST /api/clients/send-email
 * (Re)sends the welcome email with a fresh one-time set-password link to a
 * client's owner. The business is looked up server-side; the caller only
 * names it. Reports honestly whether the email was sent.
 */
export async function POST(req: Request) {
  const supabase = await createServerSupabase();
  const admin = await requireAdmin(supabase);
  if (!admin.ok) return NextResponse.json({ error: admin.error }, { status: admin.status });

  const { businessId } = await req.json();
  if (!businessId) return NextResponse.json({ error: "businessId is required" }, { status: 400 });

  const service = createServiceClient();
  const { data: biz, error: bizError } = await service
    .from("businesses")
    .select("id, name, owner_name, email")
    .eq("id", businessId)
    .maybeSingle();
  if (bizError || !biz) return NextResponse.json({ error: "Client not found" }, { status: 404 });

  // The owner's login email is on their profile (business email may differ).
  const { data: owner } = await service
    .from("profiles")
    .select("email, full_name")
    .eq("business_id", businessId)
    .eq("role", "owner")
    .limit(1)
    .maybeSingle();
  const email = (owner?.email || biz.email || "").trim().toLowerCase();
  if (!email) return NextResponse.json({ error: "This client has no owner email" }, { status: 400 });

  const { data: sub } = await service
    .from("subscriptions")
    .select("expiry_date, plans(name)")
    .eq("business_id", businessId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  let link: string;
  try {
    link = await createSetPasswordLink(service, email);
  } catch (e: unknown) {
    return NextResponse.json(
      { error: e instanceof Error ? e.message : "Could not create the set-password link" },
      { status: 500 }
    );
  }

  const result = await sendWelcomeEmail({
    email,
    ownerName: owner?.full_name || biz.owner_name || "",
    businessName: biz.name,
    planName: (sub?.plans as { name?: string } | null)?.name ?? "Trial",
    expiryDate: sub?.expiry_date ?? "",
    setPasswordUrl: link,
  });

  if (result.sent) return NextResponse.json({ sent: true, email });
  return NextResponse.json(
    { sent: false, email, error: result.error, setPasswordLink: link },
    { status: 502 }
  );
}
