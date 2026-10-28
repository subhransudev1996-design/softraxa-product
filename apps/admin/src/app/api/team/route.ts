import { randomBytes } from "crypto";
import { NextResponse } from "next/server";
import { createServerSupabase } from "@/lib/supabase/server";
import { sendTeamInviteEmail } from "@/lib/email";
import { createServiceClient, createSetPasswordLink, requireAdmin } from "@/lib/invite";
import { roleLabel, type TeamRole } from "@/lib/team";

/**
 * POST /api/team — the owner adds someone to the admin team (0098).
 * Body: { email, name, role, areas, resend? }.
 *
 * A new email gets a login with a random password nobody knows, then
 * admin_team_save (run as the owner, so the database checks it is the
 * owner) puts it on the team, and the person gets a set-password email.
 * An email that is already a shop's login is refused by admin_team_save.
 * With resend: true, only the set-password email is sent again.
 */
export async function POST(req: Request) {
  const supabase = await createServerSupabase();
  const admin = await requireAdmin(supabase, "owner");
  if (!admin.ok) return NextResponse.json({ error: admin.error }, { status: admin.status });

  const body = await req.json();
  const email = String(body.email ?? "").trim().toLowerCase();
  const name = String(body.name ?? "").trim();
  const role = String(body.role ?? "") as TeamRole;
  const areas: string[] = Array.isArray(body.areas) ? body.areas.map(String) : [];
  const resend = body.resend === true;
  if (!/^\S+@\S+\.\S+$/.test(email)) return NextResponse.json({ error: "Enter a valid email" }, { status: 400 });

  const service = createServiceClient();
  const { data: existing } = await service
    .from("profiles")
    .select("id, business_id, full_name")
    .eq("email", email)
    .maybeSingle();
  if (existing?.business_id) {
    return NextResponse.json({ error: `${email} is a shop's login. Use a different email for the team.` }, { status: 400 });
  }

  let userId = existing?.id as string | undefined;
  let created = false;
  if (!resend) {
    if (!userId) {
      const { data, error } = await service.auth.admin.createUser({
        email,
        password: randomBytes(24).toString("base64url"), // never shared; they set their own
        email_confirm: true,
        user_metadata: { full_name: name },
      });
      if (error) return NextResponse.json({ error: error.message }, { status: 400 });
      userId = data.user.id;
      created = true;
    }
    const { error: saveError } = await supabase.rpc("admin_team_save", {
      p_user: userId,
      p_name: name,
      p_role: role,
      p_areas: areas,
      p_active: true,
    });
    if (saveError) {
      if (created) await service.auth.admin.deleteUser(userId);
      return NextResponse.json({ error: saveError.message }, { status: 400 });
    }
  } else if (!userId) {
    return NextResponse.json({ error: "No such team member" }, { status: 404 });
  }

  let link: string;
  try {
    link = await createSetPasswordLink(service, email);
  } catch (e: unknown) {
    return NextResponse.json(
      { added: true, sent: false, error: e instanceof Error ? e.message : "Could not create the set-password link" },
      { status: 502 }
    );
  }

  const { data: me } = await supabase.rpc("admin_me");
  const result = await sendTeamInviteEmail({
    email,
    name: name || existing?.full_name || "",
    roleLabel: roleLabel(role),
    invitedBy: (me as { name?: string } | null)?.name ?? "",
    panelUrl: new URL(req.url).origin,
    setPasswordUrl: link,
  });
  if (result.sent) return NextResponse.json({ added: true, sent: true, email });
  return NextResponse.json({ added: true, sent: false, email, error: result.error, setPasswordLink: link }, { status: 502 });
}
