import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { Area } from "@/lib/team";

/** Service-role client for trusted server routes only. */
export function createServiceClient(): SupabaseClient {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { autoRefreshToken: false, persistSession: false } }
  );
}

/**
 * One-time link to the website's set-password page for [email]. Uses the
 * same token_hash recovery flow as "Forgot password", so it works in any
 * browser (apps/website/src/app/auth/callback).
 */
export async function createSetPasswordLink(service: SupabaseClient, email: string): Promise<string> {
  const { data, error } = await service.auth.admin.generateLink({ type: "recovery", email });
  if (error) throw error;
  const tokenHash = data.properties?.hashed_token;
  if (!tokenHash) throw new Error("Could not create a set-password link");
  const site = (process.env.WEBSITE_URL || "https://www.dukania.in").replace(/\/$/, "");
  return `${site}/auth/callback?token_hash=${encodeURIComponent(tokenHash)}&type=recovery`;
}

/**
 * Admin check for API routes: the signed-in user must be an active member
 * of the admin team with [area] (migration 0098); "owner" = the owner only.
 */
export async function requireAdmin(
  supabase: SupabaseClient,
  area: Area | "owner"
): Promise<{ ok: true; userId: string } | { ok: false; status: number; error: string }> {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { ok: false, status: 401, error: "Not authenticated" };
  const { data: allowed } =
    area === "owner" ? await supabase.rpc("admin_is_owner") : await supabase.rpc("admin_can", { p_area: area });
  if (allowed !== true) {
    return { ok: false, status: 403, error: area === "owner" ? "Only the owner can do this" : `You don't have access to ${area}` };
  }
  return { ok: true, userId: user.id };
}
