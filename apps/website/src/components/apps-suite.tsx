import Link from "next/link";
import {
  Store, Building2, Briefcase, Scissors, GraduationCap, Wrench, ArrowUpRight,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import Reveal from "./reveal";

/**
 * The range of business apps Softraxa builds, shown as floating glass cards
 * with a small representative preview each — same collage language as the
 * Dukania bento. Honesty: Dukania (inventory) is "Live"; the rest are
 * "Built to order" — apps we build for a client, not shipped products with
 * their own user base. Preview data is illustrative.
 */
type App = {
  icon: LucideIcon;
  accent: string; // tailwind text colour for the icon
  tile: string; // tailwind gradient for the icon tile
  category: string;
  name: string;
  body: string;
  preview: { label: string; value: string }[];
  status: "live" | "build";
  href?: string;
  wide?: boolean;
};

const APPS: App[] = [
  {
    icon: Store,
    accent: "text-sky",
    tile: "from-violet/25 to-sky/20",
    category: "Retail & inventory",
    name: "Dukania — Inventory & POS",
    body: "Billing, stock, expiry, GST and reports for shops — offline-first. Our flagship, live in production.",
    preview: [
      { label: "Stock value", value: "₹2,84,290" },
      { label: "On hand", value: "537 units" },
    ],
    status: "live",
    href: "/dukania",
    wide: true,
  },
  {
    icon: Building2,
    accent: "text-teal",
    tile: "from-teal/25 to-sky/20",
    category: "Property",
    name: "Real-estate management",
    body: "Track units, tenants, rent cycles and dues in one place.",
    preview: [
      { label: "Units", value: "24 · 3 vacant" },
      { label: "Rent due", value: "₹1,20,000" },
    ],
    status: "build",
  },
  {
    icon: Briefcase,
    accent: "text-sky",
    tile: "from-sky/25 to-violet/20",
    category: "Solo & agencies",
    name: "Freelance management",
    body: "Clients, projects, time and invoices — money in and out at a glance.",
    preview: [
      { label: "Clients", value: "6 active" },
      { label: "Invoices due", value: "3" },
    ],
    status: "build",
  },
  {
    icon: Scissors,
    accent: "text-amber",
    tile: "from-amber/25 to-violet/20",
    category: "Salon & spa",
    name: "Membership + billing",
    body: "Memberships, bookings and billing for salons and studios.",
    preview: [
      { label: "Today", value: "12 bookings" },
      { label: "Members", value: "Gold · 84" },
    ],
    status: "build",
  },
  {
    icon: GraduationCap,
    accent: "text-violet",
    tile: "from-violet/25 to-teal/20",
    category: "Education",
    name: "Coaching & tuition classes",
    body: "Students, batches, attendance and fee collection in one app.",
    preview: [
      { label: "Students", value: "48" },
      { label: "Fees due", value: "5" },
    ],
    status: "build",
  },
  {
    icon: Wrench,
    accent: "text-teal",
    tile: "from-teal/25 to-amber/20",
    category: "Service",
    name: "Repair-shop app",
    body: "Standalone job cards, device tracking and delivery — for repair counters.",
    preview: [
      { label: "Job cards", value: "8 open" },
      { label: "In repair", value: "3" },
    ],
    status: "build",
  },
];

function AppCard({ app }: { app: App }) {
  const inner = (
    <div className="glass group flex h-full flex-col rounded-2xl p-6 transition-colors hover:border-paper/15">
      <div className="flex items-start justify-between">
        <span className={`inline-flex h-11 w-11 items-center justify-center rounded-xl bg-gradient-to-br ${app.tile} ring-1 ring-paper/10 ${app.accent}`}>
          <app.icon className="h-5 w-5" aria-hidden="true" />
        </span>
        {app.status === "live" ? (
          <span className="inline-flex items-center gap-1.5 rounded-full border border-teal/30 bg-teal/10 px-2.5 py-1 text-[11px] font-semibold text-teal">
            <span className="h-1.5 w-1.5 rounded-full bg-teal" /> Live
          </span>
        ) : (
          <span className="rounded-full border border-hairline bg-paper/4 px-2.5 py-1 text-[11px] text-dim">
            Built to order
          </span>
        )}
      </div>

      <p className="mt-5 font-mono text-[11px] uppercase tracking-[0.15em] text-dim">{app.category}</p>
      <h3 className="mt-1.5 flex items-center gap-1.5 font-display text-lg font-semibold text-paper">
        {app.name}
        {app.href && <ArrowUpRight className="h-4 w-4 text-dim transition-colors group-hover:text-paper" />}
      </h3>
      <p className="mt-2 text-sm leading-relaxed text-dim">{app.body}</p>

      {/* representative preview strip so no card reads as blank */}
      <div className="mt-5 grid grid-cols-2 gap-2">
        {app.preview.map((p) => (
          <div key={p.label} className="rounded-lg border border-hairline bg-paper/4 px-3 py-2">
            <p className="text-[10px] uppercase tracking-wide text-dim">{p.label}</p>
            <p className="mt-0.5 font-mono text-sm font-semibold text-paper">{p.value}</p>
          </div>
        ))}
      </div>
    </div>
  );

  return app.href ? (
    <Link href={app.href} className="block h-full">{inner}</Link>
  ) : (
    <div className="h-full">{inner}</div>
  );
}

export default function AppsSuite() {
  return (
    <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
      {APPS.map((app, i) => (
        <Reveal key={app.name} delay={(i % 3) * 0.08} className={app.wide ? "sm:col-span-2 lg:col-span-2" : ""}>
          <AppCard app={app} />
        </Reveal>
      ))}
    </div>
  );
}
