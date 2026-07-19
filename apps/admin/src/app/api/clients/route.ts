import { NextResponse } from "next/server";
import { createClient as createServiceClient } from "@supabase/supabase-js";
import { createServerSupabase } from "@/lib/supabase/server";

/**
 * POST /api/clients — admin creates a client account manually (PRD 7.1, 8.2).
 * Creates the auth user, business, feature flags, expense categories/units
 * (via SQL defaults), and a subscription.
 */
export async function POST(req: Request) {
  // guard: caller must be a logged-in admin
  const supabase = await createServerSupabase();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  const { data: profile } = await supabase
    .from("profiles").select("role").eq("id", user.id).single();
  if (profile?.role !== "admin") {
    return NextResponse.json({ error: "Admin only" }, { status: 403 });
  }

  const body = await req.json();
  const { email, password, ownerName, business, planId, productId, expiryDate } = body;
  if (!email || !password || !business?.name) {
    return NextResponse.json({ error: "email, password and business.name are required" }, { status: 400 });
  }

  const service = createServiceClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { autoRefreshToken: false, persistSession: false } }
  );

  // 1. auth user (email confirmed so the owner can log in immediately)
  const { data: created, error: userError } = await service.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { full_name: ownerName ?? "" },
  });
  if (userError) return NextResponse.json({ error: userError.message }, { status: 400 });
  const userId = created.user.id;

  try {
    // 2. business
    const { data: biz, error: bizError } = await service
      .from("businesses")
      .insert({
        name: business.name,
        owner_name: ownerName ?? "",
        business_type: business.type ?? "other",
        phone: business.phone ?? "",
        email,
        address: business.address ?? "",
        gst_number: business.gstNumber ?? "",
        invoice_prefix: business.invoicePrefix || "INV",
        tax_preference: business.taxPreference ?? "gst",
        setup_complete: true,
      })
      .select("id")
      .single();
    if (bizError) throw bizError;

    // 3. link profile (handle_new_user trigger already created the row)
    await service.from("profiles").upsert({
      id: userId,
      business_id: biz.id,
      role: "owner",
      email,
      full_name: ownerName ?? "",
    });

    // 4. feature flags + default masters + subscription
    await service.from("feature_flags").upsert({ business_id: biz.id });
    await service.from("expense_categories").insert(
      ["Rent", "Salary", "Electricity", "Transport", "Packaging", "Repair", "Miscellaneous"]
        .map((name) => ({ business_id: biz.id, name }))
    );
    await service.from("units").insert(
      [
        ["Piece", "pcs", false], ["Kg", "kg", true], ["Gram", "g", true],
        ["Metre", "m", true], ["Litre", "L", true], ["Box", "box", false],
        ["Dozen", "dz", false], ["Set", "set", false],
      ].map(([name, short_name, allow_decimal]) => ({
        business_id: biz.id, name, short_name, allow_decimal,
      }))
    );
    // Trial length: explicit expiry wins, else the selected software's
    // trial_days, else a 14-day default. (software_products, NOT products —
    // `products` is the shop's inventory items.)
    let trialDays = 14;
    if (productId) {
      const { data: sw } = await service
        .from("software_products").select("trial_days").eq("id", productId).maybeSingle();
      if (sw?.trial_days) trialDays = sw.trial_days;
    }
    const expiry = expiryDate || new Date(Date.now() + trialDays * 86400000).toISOString().slice(0, 10);
    await service.from("subscriptions").insert({
      business_id: biz.id,
      plan_id: planId || null,
      software_id: productId || null,
      status: planId ? "active" : "trial",
      expiry_date: expiry,
    });

    // Enforce the plan's features on the shop's feature_flags so the app
    // hides anything this plan doesn't include. (No-op for a trial with no
    // plan — the shop keeps all features on by default.)
    if (planId) {
      await service.rpc("apply_plan_features", { p_business: biz.id, p_plan: planId });
    }

    return NextResponse.json({ businessId: biz.id, userId });
  } catch (e: unknown) {
    // rollback the auth user so the email can be reused
    await service.auth.admin.deleteUser(userId);
    const message = e instanceof Error ? e.message : "Failed to create client";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
