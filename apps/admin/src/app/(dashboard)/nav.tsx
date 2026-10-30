"use client";

import { ReactNode, useEffect, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import {
  Boxes,
  CalendarCheck,
  Handshake,
  HeartHandshake,
  HeartPulse,
  IndianRupee,
  Layers,
  ListTodo,
  LifeBuoy,
  ListChecks,
  Megaphone,
  Menu,
  ScanSearch,
  ScrollText,
  Settings,
  TrendingUp,
  Store,
  Target,
  UserCog,
  Wallet,
  Users,
  X,
} from "lucide-react";
import { BrandMark } from "@/components/brand-mark";
import { MeProvider } from "@/components/me";
import { AlertsBell } from "@/components/alerts";
import { Card, CardBody } from "@/components/ui";
import { Me, areaFor, canUse, roleLabel } from "@/lib/team";
import { LogoutButton } from "./logout-button";

// Grouped by the work, so a team member finds their part quickly.
const groups: { title?: string; items: { href: string; label: string; icon: typeof Store }[] }[] = [
  { items: [
    { href: "/", label: "Today", icon: CalendarCheck },
    { href: "/tasks", label: "Tasks & calendar", icon: ListTodo },
  ] },
  { title: "Customers", items: [
    { href: "/clients", label: "Clients", icon: Store },
    { href: "/success", label: "Customer success", icon: HeartHandshake },
    { href: "/support", label: "Support", icon: LifeBuoy },
  ] },
  { title: "Growth", items: [
    { href: "/leads", label: "Leads", icon: Target },
    { href: "/marketing", label: "Marketing", icon: Megaphone },
    { href: "/influencers", label: "Influencers", icon: Handshake },
  ] },
  { title: "Money", items: [
    { href: "/payments", label: "Payments", icon: IndianRupee },
    { href: "/sales", label: "Sales", icon: TrendingUp },
    { href: "/accounts", label: "Accounts", icon: Wallet },
    { href: "/reconciliation", label: "Reconciliation", icon: ScanSearch },
  ] },
  { title: "Setup", items: [
    { href: "/plans", label: "Plans", icon: Layers },
    { href: "/catalog", label: "Master products", icon: ListChecks },
    { href: "/products", label: "Software", icon: Boxes },
    { href: "/settings", label: "Settings", icon: Settings },
    { href: "/team", label: "Team", icon: Users },
    { href: "/health", label: "System health", icon: HeartPulse },
    { href: "/audit", label: "Audit logs", icon: ScrollText },
    { href: "/account", label: "My login", icon: UserCog },
  ] },
];

export function SidebarNav({ me, onNavigate }: { me: Me; onNavigate?: () => void }) {
  const pathname = usePathname();
  // Only the pages this team member may use (migration 0098).
  const allowed = (item: { href: string }) => canUse(me, areaFor(item.href));
  const isActive = (href: string) =>
    href === "/" ? pathname === "/" : pathname === href || pathname.startsWith(`${href}/`);

  const link = (item: (typeof groups)[number]["items"][number]) => {
    const active = isActive(item.href);
    const Icon = item.icon;
    return (
      <Link
        key={item.href}
        href={item.href}
        onClick={onNavigate}
        aria-current={active ? "page" : undefined}
        className={`relative flex items-center gap-2.5 rounded-lg px-2.5 py-1.5 text-sm font-medium transition-colors ${
          active ? "bg-white/10 text-white" : "text-sidebar-muted hover:bg-white/5 hover:text-white"
        }`}
      >
        {active && <span className="absolute -left-3 top-1.5 bottom-1.5 w-[3px] rounded-r-full bg-marigold" />}
        <Icon size={16} className={active ? "text-marigold" : ""} />
        {item.label}
      </Link>
    );
  };

  return (
    <nav className="sidebar-scroll flex-1 space-y-4 overflow-y-auto px-3 py-3">
      {groups.map((group) => {
        const items = group.items.filter(allowed);
        if (items.length === 0) return null;
        return (
          <div key={group.title ?? "main"} className="space-y-0.5">
            {group.title && <p className="px-2.5 pb-1 text-xs font-medium text-sidebar-muted/70">{group.title}</p>}
            {items.map(link)}
          </div>
        );
      })}
    </nav>
  );
}

function SidebarContent({ me, onNavigate }: { me: Me; onNavigate?: () => void }) {
  return (
    <>
      <div className="flex h-14 shrink-0 items-center gap-2.5 border-b border-white/10 px-4">
        <BrandMark />
        <p className="text-sm font-bold text-white">Dukania <span className="font-medium text-sidebar-muted">Admin</span></p>
        <div className="ml-auto hidden lg:block"><AlertsBell /></div>
      </div>
      {/* Search everything from anywhere (also Ctrl+K). */}
      <form
        className="px-3 pt-3"
        onSubmit={(e) => {
          e.preventDefault();
          const q = String(new FormData(e.currentTarget).get("q") ?? "").trim();
          if (q) window.location.href = `/search?q=${encodeURIComponent(q)}`;
        }}
      >
        <input
          name="q"
          placeholder="Search…  Ctrl+K"
          aria-label="Search everything"
          className="min-h-9 w-full rounded-lg border border-white/10 bg-white/5 px-3 py-1.5 text-sm text-white outline-none placeholder:text-sidebar-muted focus:border-marigold/60 focus:ring-2 focus:ring-marigold/20"
        />
      </form>
      <SidebarNav me={me} onNavigate={onNavigate} />
      <div className="border-t border-white/10 p-3">
        <div className="flex items-center gap-2.5 px-2.5 py-1.5">
          <span className="grid h-7 w-7 shrink-0 place-items-center rounded-full bg-brand text-xs font-bold uppercase text-white">
            {(me.name || me.email || "A").slice(0, 1)}
          </span>
          <div className="min-w-0">
            <p className="truncate text-[13px] font-semibold text-white">{me.name || me.email}</p>
            <p className="truncate text-xs text-sidebar-muted">{roleLabel(me.team_role)}</p>
          </div>
        </div>
        <LogoutButton />
      </div>
    </>
  );
}

/** Sidebar on large screens; a top bar with a slide-in menu on phones. */
export function AppShell({ me, children }: { me: Me; children: ReactNode }) {
  const [open, setOpen] = useState(false);
  const pathname = usePathname();
  const allowed = canUse(me, areaFor(pathname));
  const router = useRouter();

  // Ctrl+K (Cmd+K on a Mac): search everything.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        router.push("/search");
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [router]);
  return (
    <div className="min-h-screen bg-canvas">
      <aside className="fixed inset-y-0 z-20 hidden w-60 flex-col bg-sidebar lg:flex print:hidden">
        <SidebarContent me={me} />
      </aside>

      <header className="sticky top-0 z-30 flex h-14 items-center gap-3 bg-sidebar px-4 lg:hidden print:hidden">
        <button onClick={() => setOpen(true)} className="grid h-9 w-9 cursor-pointer place-items-center rounded-lg text-white hover:bg-white/10" aria-label="Open menu">
          <Menu size={22} />
        </button>
        <p className="text-sm font-bold text-white">Dukania <span className="font-medium text-sidebar-muted">Admin</span></p>
        <div className="ml-auto"><AlertsBell alignRight /></div>
      </header>
      {open && (
        <div className="fixed inset-0 z-40 lg:hidden" onClick={() => setOpen(false)}>
          <div className="absolute inset-0 bg-black/40" />
          <aside
            className="absolute inset-y-0 left-0 flex w-64 flex-col bg-sidebar"
            onClick={(e) => e.stopPropagation()}
          >
            <button onClick={() => setOpen(false)} className="absolute right-3 top-3 z-10 grid h-9 w-9 cursor-pointer place-items-center rounded-lg text-sidebar-muted hover:bg-white/10 hover:text-white" aria-label="Close menu">
              <X size={20} />
            </button>
            <SidebarContent me={me} onNavigate={() => setOpen(false)} />
          </aside>
        </div>
      )}

      <main className="p-4 sm:p-6 lg:ml-60 print:m-0 print:p-0">
        <div className="animate-rise mx-auto max-w-7xl">
          <MeProvider me={me}>
            {allowed ? (
              children
            ) : (
              <Card>
                <CardBody>
                  <p className="font-semibold text-ink">This page isn&apos;t part of your work.</p>
                  <p className="mt-1 text-sm text-zinc-500">Ask the owner to give you access on the Team page.</p>
                </CardBody>
              </Card>
            )}
          </MeProvider>
        </div>
      </main>
    </div>
  );
}
