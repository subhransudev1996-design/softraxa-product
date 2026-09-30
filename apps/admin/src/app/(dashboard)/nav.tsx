"use client";

import { ReactNode, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  Boxes,
  CalendarCheck,
  HeartPulse,
  IndianRupee,
  Layers,
  LifeBuoy,
  Menu,
  ScanSearch,
  ScrollText,
  Settings,
  Store,
  Target,
  X,
} from "lucide-react";
import { LogoutButton } from "./logout-button";

// Daily work first; setup pages below.
const daily = [
  { href: "/", label: "Today", icon: CalendarCheck },
  { href: "/clients", label: "Clients", icon: Store },
  { href: "/payments", label: "Payments", icon: IndianRupee },
  { href: "/support", label: "Support", icon: LifeBuoy },
  { href: "/leads", label: "Leads", icon: Target },
  { href: "/reconciliation", label: "Reconciliation", icon: ScanSearch },
];
const setup = [
  { href: "/plans", label: "Plans", icon: Layers },
  { href: "/products", label: "Products", icon: Boxes },
  { href: "/settings", label: "Settings", icon: Settings },
  { href: "/health", label: "System health", icon: HeartPulse },
  { href: "/audit", label: "Audit logs", icon: ScrollText },
];

export function SidebarNav({ onNavigate }: { onNavigate?: () => void }) {
  const pathname = usePathname();
  const isActive = (href: string) =>
    href === "/" ? pathname === "/" : pathname === href || pathname.startsWith(`${href}/`);

  const link = (item: (typeof daily)[number]) => {
    const active = isActive(item.href);
    const Icon = item.icon;
    return (
      <Link
        key={item.href}
        href={item.href}
        onClick={onNavigate}
        className={`group relative flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-semibold transition-colors duration-150 ${
          active ? "bg-white/[0.07] text-white" : "text-sidebar-muted hover:bg-white/[0.04] hover:text-zinc-200"
        }`}
      >
        {active && (
          <span className="absolute left-0 top-1/2 h-5 w-1 -translate-y-1/2 rounded-r-full bg-gradient-to-b from-brand to-[#a78bfa]" />
        )}
        <Icon
          size={17}
          strokeWidth={2.2}
          className={active ? "text-[#a78bfa]" : "text-sidebar-muted transition-colors group-hover:text-zinc-300"}
        />
        {item.label}
      </Link>
    );
  };

  return (
    <nav className="flex-1 space-y-1 overflow-y-auto p-3">
      {daily.map(link)}
      <p className="px-3 pb-1 pt-4 text-[10px] font-bold uppercase tracking-[0.14em] text-sidebar-muted/70">Setup</p>
      {setup.map(link)}
    </nav>
  );
}

function SidebarContent({ email, onNavigate }: { email: string; onNavigate?: () => void }) {
  return (
    <>
      <div className="flex items-center gap-3 px-5 py-5">
        <span className="grid h-9 w-9 place-items-center rounded-xl bg-gradient-to-br from-brand to-[#4c1d95] text-base font-extrabold text-white shadow-[0_4px_14px_-4px_rgba(124,58,237,0.7)]">
          S
        </span>
        <div>
          <p className="text-[15px] font-extrabold leading-5 tracking-tight text-white">Dukania</p>
          <p className="text-[11px] font-medium uppercase tracking-[0.14em] text-sidebar-muted">Admin panel</p>
        </div>
      </div>
      <div className="mx-4 h-px bg-white/[0.06]" />
      {/* Find a client from anywhere: name, phone, email or GSTIN. */}
      <form
        className="px-3 pt-3"
        onSubmit={(e) => {
          e.preventDefault();
          const q = String(new FormData(e.currentTarget).get("q") ?? "").trim();
          if (q) window.location.href = `/clients?q=${encodeURIComponent(q)}`;
        }}
      >
        <input
          name="q"
          placeholder="Find a client…"
          aria-label="Find a client"
          className="w-full rounded-xl bg-white/[0.06] px-3 py-2 text-sm text-white outline-none placeholder:text-sidebar-muted focus:ring-2 focus:ring-brand"
        />
      </form>
      <SidebarNav onNavigate={onNavigate} />
      <div className="mx-4 h-px bg-white/[0.06]" />
      <div className="p-3">
        <div className="flex items-center gap-2.5 rounded-xl px-2 py-2">
          <span className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-white/[0.08] text-xs font-bold uppercase text-zinc-300">
            {(email || "A").slice(0, 1)}
          </span>
          <p className="truncate text-xs font-medium text-sidebar-muted">{email}</p>
        </div>
        <LogoutButton />
      </div>
    </>
  );
}

/** Sidebar on large screens; a top bar with a slide-in menu on phones. */
export function AppShell({ email, children }: { email: string; children: ReactNode }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="min-h-screen bg-canvas">
      <aside className="fixed inset-y-0 z-20 hidden w-60 flex-col bg-sidebar lg:flex print:hidden">
        <SidebarContent email={email} />
      </aside>

      <header className="sticky top-0 z-30 flex items-center gap-3 bg-sidebar px-4 py-3 lg:hidden print:hidden">
        <button onClick={() => setOpen(true)} className="rounded-lg p-1 text-white" aria-label="Open menu">
          <Menu size={22} />
        </button>
        <p className="font-extrabold text-white">Dukania admin</p>
      </header>
      {open && (
        <div className="fixed inset-0 z-40 lg:hidden" onClick={() => setOpen(false)}>
          <div className="absolute inset-0 bg-black/50" />
          <aside
            className="absolute inset-y-0 left-0 flex w-64 flex-col bg-sidebar"
            onClick={(e) => e.stopPropagation()}
          >
            <button onClick={() => setOpen(false)} className="absolute right-3 top-5 text-sidebar-muted" aria-label="Close menu">
              <X size={20} />
            </button>
            <SidebarContent email={email} onNavigate={() => setOpen(false)} />
          </aside>
        </div>
      )}

      <main className="p-4 sm:p-6 lg:ml-60 lg:p-8 print:m-0 print:p-0">
        <div className="animate-rise mx-auto max-w-6xl">{children}</div>
      </main>
    </div>
  );
}
