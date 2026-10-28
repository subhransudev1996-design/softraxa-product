import { redirect } from "next/navigation";
import { createServerSupabase } from "@/lib/supabase/server";
import type { Me } from "@/lib/team";
import { AppShell } from "./nav";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = await createServerSupabase();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  // Two-step login turned on but the code not entered yet.
  const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  if (aal?.nextLevel === "aal2" && aal.currentLevel !== "aal2") redirect("/login?step=code");

  // An active member of the admin team (migration 0098).
  const { data: me } = await supabase.rpc("admin_me");
  if (!me) redirect("/login");

  return <AppShell me={me as Me}>{children}</AppShell>;
}
