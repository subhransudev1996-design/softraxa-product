import { randomBytes } from "node:crypto";
import { NextResponse } from "next/server";
import { createServerSupabase } from "@/lib/supabase/server";
import { sendWelcomeEmail } from "@/lib/email";
import { createServiceClient, createSetPasswordLink, requireAdmin } from "@/lib/invite";

/**
 * POST /api/clients — admin creates a client account (PRD 7.1, 8.2).
 *
 * 1. Creates the owner's login with an unusable random password.
 * 2. Sets up business, masters, subscription and plan features in ONE
 *    database transaction (admin_provision_business, migration 0039); on
 *    any failure the login is deleted too, so nothing is left half-made.
 * 3. Emails a one-time set-password link. The admin never chooses or sees
 *    a password. If the email can't be sent, the response says so and
 *    returns the link for the admin to share.
 */
export async function POST(req: Request) {
  const supabase = await createServerSupabase();
  const admin = await requireAdmin(supabase);
  if (!admin.ok) return NextResponse.json({ error: admin.error }, { status: admin.status });

  const body = await req.json();
  const { ownerName, business, planId, productId, expiryDate } = body;
  const email = String(body.email ?? "").trim().toLowerCase();
  if (!email || !business?.name) {
    return NextResponse.json({ error: "email and business.name are required" }, { status: 400 });
  }

  const service = createServiceClient();

  const { data: created, error: userError } = await service.auth.admin.createUser({
    email,
    password: randomBytes(24).toString("base64url"), // never shared; owner sets their own
    email_confirm: true,
    user_metadata: { full_name: ownerName ?? "" },
  });
  if (userError) return NextResponse.json({ error: userError.message }, { status: 400 });
  const userId = created.user.id;

  const { data: businessId, error: provisionError } = await service.rpc("admin_provision_business", {
    p_user_id: userId,
    p_email: email,
    p_owner_name: ownerName ?? "",
    p_business: business,
    p_plan: planId || null,
    p_software: productId || null,
    p_expiry: expiryDate || null,
  });
  if (provisionError || !businessId) {
    const { error: cleanupError } = await service.auth.admin.deleteUser(userId);
    return NextResponse.json(
      {
        error: provisionError?.message ?? "Failed to set up the business",
        ...(cleanupError ? { cleanupError: `The login ${email} could not be removed: ${cleanupError.message}` } : {}),
      },
      { status: 500 }
    );
  }

  // The account exists from here on; email problems are reported, not fatal.
  const { data: sub } = await service
    .from("subscriptions")
    .select("expiry_date, plans(name)")
    .eq("business_id", businessId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  const planName = (sub?.plans as { name?: string } | null)?.name ?? "Trial";

  let setPasswordLink: string | null = null;
  let emailSent = false;
  let emailError: string | null = null;
  try {
    setPasswordLink = await createSetPasswordLink(service, email);
    const result = await sendWelcomeEmail({
      email,
      ownerName: ownerName ?? "",
      businessName: business.name,
      planName,
      expiryDate: sub?.expiry_date ?? "",
      setPasswordUrl: setPasswordLink,
    });
    emailSent = result.sent;
    if (!result.sent) emailError = result.error;
  } catch (e: unknown) {
    emailError = e instanceof Error ? e.message : "Could not create the set-password link";
  }

  return NextResponse.json({
    businessId,
    userId,
    emailSent,
    emailError,
    // Only needed when the email didn't go out, so the admin can share it.
    setPasswordLink: emailSent ? null : setPasswordLink,
  });
}
