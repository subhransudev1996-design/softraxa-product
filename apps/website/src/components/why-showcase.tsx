import Image from "next/image";
import {
  Package, Warehouse, Pencil, Plus, Receipt, Boxes, CalendarClock,
  RefreshCw, ScanLine, BarChart3, Wrench, Percent,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import Reveal from "./reveal";

/**
 * The "why use Dukania" showcase — three benefit cards, each with a small
 * illustration built in our dark-glass language. Mirrors the layout on
 * inflowinventory.com (a tall left card + two stacked right cards) but with
 * our own CSS-drawn visuals: a product tile with a price tag + barcode +
 * in-stock chip, an initials avatar stack (no fabricated faces), and a
 * cluster of capability chips. All data is illustrative.
 */

const AVATARS = [
  { name: "Owner 1", image: "/images/avatars/owner-1.png" },
  { name: "Owner 2", image: "/images/avatars/owner-2.png" },
  { name: "Owner 3", image: "/images/avatars/owner-3.png" },
  { name: "Owner 4", image: "/images/avatars/owner-4.png" },
];

const CHIPS: { label: string; icon: LucideIcon; tint: string }[] = [
  { label: "Billing & POS", icon: Receipt, tint: "text-sky bg-sky/10 border-sky/20" },
  { label: "Stock levels", icon: Boxes, tint: "text-teal bg-teal/10 border-teal/20" },
  { label: "Expiry tracking", icon: CalendarClock, tint: "text-amber bg-amber/10 border-amber/20" },
  { label: "Reordering", icon: RefreshCw, tint: "text-violet bg-violet/10 border-violet/20" },
  { label: "Barcoding", icon: ScanLine, tint: "text-sky bg-sky/10 border-sky/20" },
  { label: "Reports", icon: BarChart3, tint: "text-teal bg-teal/10 border-teal/20" },
  { label: "GST", icon: Percent, tint: "text-amber bg-amber/10 border-amber/20" },
  { label: "Job cards", icon: Wrench, tint: "text-violet bg-violet/10 border-violet/20" },
];

export default function WhyShowcase() {
  return (
    <div className="grid gap-6 lg:grid-cols-2">
      {/* Card 1 — Easy to use (tall) */}
      <Reveal className="lg:row-span-2">
        <div className="glass flex h-full flex-col rounded-3xl p-8">
          <h3 className="font-display text-2xl font-bold tracking-tight">Easy enough for anyone</h3>
          <p className="mt-3 max-w-sm text-dim">
            Bills, stock and reports are laid out plainly, so a new hire can run the
            counter on day one — no training week, no manual.
          </p>

          {/* product tile with floating chips */}
          <div className="relative mt-8 flex-1">
            <div className="relative mx-auto aspect-[4/3] w-full max-w-sm rounded-2xl bg-gradient-to-br from-amber/20 to-violet/15 ring-1 ring-paper/10">
              <Package className="absolute left-1/2 top-1/2 h-20 w-20 -translate-x-1/2 -translate-y-1/2 text-amber/70" strokeWidth={1.2} />

              {/* MRP price tag */}
              <div className="absolute right-3 top-3 flex overflow-hidden rounded-lg text-xs font-semibold shadow-lg">
                <span className="bg-violet px-3 py-2 text-white">MRP</span>
                <span className="bg-elevated px-3 py-2 font-mono text-paper">₹32,000</span>
              </div>

              {/* barcode label */}
              <div className="absolute -bottom-3 right-4 rounded-md bg-white p-2 shadow-lg">
                <div className="barcode barcode-dark h-8 w-32" />
                <p className="mt-1 text-center font-mono text-[9px] text-bg">DK-005037</p>
              </div>

              {/* in stock card */}
              <div className="absolute -bottom-4 left-3 rounded-xl border border-hairline bg-elevated p-3 shadow-xl">
                <Warehouse className="h-4 w-4 text-sky" />
                <p className="mt-1 font-display text-2xl font-bold leading-none text-paper">537</p>
                <p className="text-[10px] text-dim">in stock</p>
              </div>
            </div>

            <div className="mt-8 inline-flex h-9 w-9 items-center justify-center rounded-lg border border-hairline bg-paper/4 text-dim">
              <Pencil className="h-4 w-4" />
            </div>
          </div>
        </div>
      </Reveal>

      {/* Card 2 — small & mid (short) */}
      <Reveal delay={0.1}>
        <div className="glass flex h-full flex-col rounded-3xl p-8">
          <h3 className="font-display text-2xl font-bold tracking-tight">Right-sized for small &amp; mid shops</h3>
          <p className="mt-3 max-w-md text-dim">
            From a single counter to a team across a few outlets, Dukania scales to
            fit — you never pay for enterprise features nobody will open.
          </p>
          <div className="mt-8 flex items-center">
            {AVATARS.map((a, i) => (
              <div
                key={a.image}
                className="relative -ml-3 h-11 w-11 overflow-hidden rounded-full border-2 border-bg shadow-md first:ml-0"
                style={{ zIndex: AVATARS.length - i }}
              >
                <Image
                  src={a.image}
                  width={44}
                  height={44}
                  alt={a.name}
                  className="h-full w-full object-cover"
                />
              </div>
            ))}
            <span className="-ml-3 inline-flex h-11 w-11 items-center justify-center rounded-full border border-hairline bg-elevated text-dim ring-2 ring-bg">
              <Plus className="h-4 w-4" />
            </span>
          </div>
        </div>
      </Reveal>

      {/* Card 3 — more than billing */}
      <Reveal delay={0.15}>
        <div className="glass flex h-full flex-col rounded-3xl p-8">
          <h3 className="font-display text-2xl font-bold tracking-tight">More than just billing</h3>
          <p className="mt-3 max-w-md text-dim">
            Stock, expiry, purchases, returns, expenses, service job cards and GST
            reports — the whole shop in one app, not five.
          </p>
          <div className="mt-6 flex flex-wrap gap-2.5">
            {CHIPS.map((c) => (
              <span
                key={c.label}
                className={`inline-flex items-center gap-1.5 rounded-lg border px-3 py-2 text-sm font-medium ${c.tint}`}
              >
                <c.icon className="h-3.5 w-3.5" aria-hidden="true" />
                {c.label}
              </span>
            ))}
          </div>
        </div>
      </Reveal>
    </div>
  );
}
