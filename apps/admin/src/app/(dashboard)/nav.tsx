"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  LayoutDashboard,
  Store,
  Target,
  Layers,
  IndianRupee,
  LifeBuoy,
  ScrollText,
} from "lucide-react";

const nav = [
  { href: "/", label: "Dashboard", icon: LayoutDashboard },
  { href: "/clients", label: "Clients", icon: Store },
  { href: "/leads", label: "Leads", icon: Target },
  { href: "/plans", label: "Plans", icon: Layers },
  { href: "/payments", label: "Payments", icon: IndianRupee },
  { href: "/support", label: "Support", icon: LifeBuoy },
  { href: "/audit", label: "Audit logs", icon: ScrollText },
];

export function SidebarNav() {
  const pathname = usePathname();
  const isActive = (href: string) =>
    href === "/" ? pathname === "/" : pathname === href || pathname.startsWith(`${href}/`);

  return (
    <nav className="flex-1 space-y-1 p-3">
      {nav.map((item) => {
        const active = isActive(item.href);
        const Icon = item.icon;
        return (
          <Link
            key={item.href}
            href={item.href}
            className={`group relative flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-semibold transition-colors duration-150 ${
              active
                ? "bg-white/[0.07] text-white"
                : "text-sidebar-muted hover:bg-white/[0.04] hover:text-zinc-200"
            }`}
          >
            {active && (
              <span className="absolute left-0 top-1/2 h-5 w-1 -translate-y-1/2 rounded-r-full bg-gradient-to-b from-brand to-[#f0698a]" />
            )}
            <Icon
              size={17}
              strokeWidth={2.2}
              className={active ? "text-brand" : "text-sidebar-muted transition-colors group-hover:text-zinc-300"}
            />
            {item.label}
          </Link>
        );
      })}
    </nav>
  );
}
