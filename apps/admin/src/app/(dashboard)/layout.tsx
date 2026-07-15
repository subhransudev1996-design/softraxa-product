import { redirect } from "next/navigation";
import { createServerSupabase } from "@/lib/supabase/server";
import { LogoutButton } from "./logout-button";
import { SidebarNav } from "./nav";

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

  const { data: profile } = await supabase
    .from("profiles")
    .select("role, full_name, email")
    .eq("id", user.id)
    .single();
  if (profile?.role !== "admin") redirect("/login");

  return (
    <div className="flex min-h-screen bg-canvas">
      <aside className="fixed inset-y-0 z-20 flex w-60 flex-col bg-sidebar">
        <div className="flex items-center gap-3 px-5 py-5">
          <span className="grid h-9 w-9 place-items-center rounded-xl bg-gradient-to-br from-brand to-[#4c1d95] text-base font-extrabold text-white shadow-[0_4px_14px_-4px_rgba(124,58,237,0.7)]">
            S
          </span>
          <div>
            <p className="text-[15px] font-extrabold leading-5 tracking-tight text-white">
              SOFTRAXA
            </p>
            <p className="text-[11px] font-medium uppercase tracking-[0.14em] text-sidebar-muted">
              Admin panel
            </p>
          </div>
        </div>
        <div className="mx-4 h-px bg-white/[0.06]" />
        <SidebarNav />
        <div className="mx-4 h-px bg-white/[0.06]" />
        <div className="p-3">
          <div className="flex items-center gap-2.5 rounded-xl px-2 py-2">
            <span className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-white/[0.08] text-xs font-bold uppercase text-zinc-300">
              {(profile?.full_name || profile?.email || "A").slice(0, 1)}
            </span>
            <p className="truncate text-xs font-medium text-sidebar-muted">{profile?.email}</p>
          </div>
          <LogoutButton />
        </div>
      </aside>
      <main className="ml-60 flex-1 p-8">
        <div className="animate-rise mx-auto max-w-6xl">{children}</div>
      </main>
    </div>
  );
}
