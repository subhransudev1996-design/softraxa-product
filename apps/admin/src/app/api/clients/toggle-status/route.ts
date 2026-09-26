import { NextResponse } from "next/server";
import { createServerSupabase } from "@/lib/supabase/server";
import { createServiceClient, requireAdmin } from "@/lib/invite";

/**
 * POST /api/clients/toggle-status
 * Suspends or restores a client. Business and subscription status change
 * together in one transaction (admin_set_business_status, migration 0039)
 * and the response carries the resulting state.
 */
export async function POST(req: Request) {
  const supabase = await createServerSupabase();
  const admin = await requireAdmin(supabase);
  if (!admin.ok) return NextResponse.json({ error: admin.error }, { status: admin.status });

  const { businessId, suspend } = await req.json();
  if (!businessId || typeof suspend !== "boolean") {
    return NextResponse.json({ error: "businessId and suspend (boolean) are required" }, { status: 400 });
  }

  const { data, error } = await createServiceClient().rpc("admin_set_business_status", {
    p_business: businessId,
    p_suspend: suspend,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ success: true, ...data });
}
