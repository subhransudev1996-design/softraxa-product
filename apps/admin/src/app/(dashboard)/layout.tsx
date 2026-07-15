import Link from "next/link";
import { redirect } from "next/navigation";
import { createServerSupabase } from "@/lib/supabase/server";
import { LogoutButton } from "./logout-button";

const nav = [
  { href: "/", label: "Dashboard" },
  { href: "/clients", label: "Clients" },
  { href: "/plans", label: "Plans" },
  { href: "/payments", label: "Payments" },
  { href: "/support", label: "Support" },
  { href: "/audit", label: "Audit logs" },
];

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
    <div className="flex min-h-screen bg-zinc-100">
      <aside className="fixed inset-y-0 flex w-56 flex-col border-r border-zinc-200 bg-white">
        <div className="border-b border-zinc-200 px-5 py-4">
          <p className="text-base font-bold text-zinc-900">SOFTRAXA</p>
          <p className="text-xs text-zinc-500">Admin panel</p>
        </div>
        <nav className="flex-1 space-y-1 p-3">
          {nav.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className="block rounded-lg px-3 py-2 text-sm font-medium text-zinc-700 hover:bg-zinc-100"
            >
              {item.label}
            </Link>
          ))}
        </nav>
        <div className="border-t border-zinc-200 p-3">
          <p className="truncate px-3 pb-2 text-xs text-zinc-500">{profile?.email}</p>
          <LogoutButton />
        </div>
      </aside>
      <main className="ml-56 flex-1 p-8">{children}</main>
    </div>
  );
}
