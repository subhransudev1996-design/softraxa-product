import { randomBytes } from "node:crypto";
import { NextResponse } from "next/server";
import { createServerSupabase } from "@/lib/supabase/server";
import { createServiceClient, requireAdmin } from "@/lib/invite";

/**
 * POST /api/partner-login — the team manages an influencer partner's login
 * (migration 0107). { partnerId, action: "create", email } | "reset" | "remove".
 *
 * Creates a confirmed login with a generated password and returns the
 * password once, for the team to send on WhatsApp; the partner can change
 * it. Only a login made here can be reset or removed: an email that already
 * has an account (a shop owner, say) is refused, never taken over.
 */
const password = () => `Dk-${randomBytes(9).toString("base64url")}`;

export async function POST(req: Request) {
  const supabase = await createServerSupabase();
  const admin = await requireAdmin(supabase, "marketing");
  if (!admin.ok) return NextResponse.json({ error: admin.error }, { status: admin.status });

  const body = await req.json().catch(() => ({}));
  const partnerId = String(body.partnerId ?? "");
  const service = createServiceClient();
  const { data: partner } = await service.from("partners").select("id, name, user_id, login_email").eq("id", partnerId).maybeSingle();
  if (!partner) return NextResponse.json({ error: "Partner not found" }, { status: 404 });

  if (body.action === "create") {
    if (partner.user_id) return NextResponse.json({ error: "This partner already has a login" }, { status: 400 });
    const email = String(body.email ?? "").trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      return NextResponse.json({ error: "Enter a valid email address" }, { status: 400 });
    }
    const pass = password();
    const { data: created, error } = await service.auth.admin.createUser({
      email, password: pass, email_confirm: true, user_metadata: { full_name: partner.name },
    });
    if (error) {
      const taken = /already|registered|exists/i.test(error.message);
      return NextResponse.json({ error: taken ? "That email already has a Dukania account. Use another email for this partner." : error.message }, { status: 400 });
    }
    const { error: linkError } = await service.rpc("admin_link_partner_login", {
      p_partner: partner.id, p_user: created.user.id, p_email: email,
    });
    if (linkError) {
      await service.auth.admin.deleteUser(created.user.id);
      return NextResponse.json({ error: linkError.message }, { status: 500 });
    }
    return NextResponse.json({ email, password: pass });
  }

  if (!partner.user_id) return NextResponse.json({ error: "This partner has no login yet" }, { status: 400 });

  if (body.action === "reset") {
    const pass = password();
    const { error } = await service.auth.admin.updateUserById(partner.user_id, { password: pass });
    if (error) return NextResponse.json({ error: error.message }, { status: 500 });
    return NextResponse.json({ email: partner.login_email, password: pass });
  }

  if (body.action === "remove") {
    const { error: linkError } = await service.rpc("admin_link_partner_login", {
      p_partner: partner.id, p_user: null, p_email: "",
    });
    if (linkError) return NextResponse.json({ error: linkError.message }, { status: 500 });
    const { error } = await service.auth.admin.deleteUser(partner.user_id);
    if (error) return NextResponse.json({ error: `Unlinked, but the login could not be deleted: ${error.message}` }, { status: 500 });
    return NextResponse.json({ ok: true });
  }

  return NextResponse.json({ error: "Unknown action" }, { status: 400 });
}
