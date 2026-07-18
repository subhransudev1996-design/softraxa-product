import Link from "next/link";
import {
  Package, Wrench, Scissors, ArrowRight, Check, ScanLine, IdCard, Boxes,
} from "lucide-react";
import Reveal from "./reveal";
import MagneticButton from "./magnetic-button";

/**
 * "Softraxa software" solutions bento — a big flagship card plus two stacked
 * cards, each with a small CSS illustration and its own action, closed by a
 * "which fits you?" bar. Mirrors the layout on inflowinventory.com but rebuilt
 * in our dark palette with tinted glass (no copied illustrations). Honesty:
 * Dukania is Live; the other two are apps we build to order.
 */
export default function SoftwareSolutions() {
  return (
    <div>
      <div className="grid gap-6 lg:grid-cols-2">
        {/* Flagship — Dukania (tall, amber) */}
        <Reveal className="lg:row-span-2">
          <div className="flex h-full flex-col rounded-3xl border border-amber/20 bg-gradient-to-br from-amber/12 to-amber/[0.03] p-8">
            {/* mini product illustration */}
            <div className="rounded-2xl bg-amber/15 p-4">
              <div className="flex items-center gap-3 rounded-xl border border-hairline bg-elevated p-3">
                <div className="relative">
                  <span className="inline-flex h-11 w-11 items-center justify-center rounded-lg bg-gradient-to-br from-violet/30 to-sky/20 text-sky ring-1 ring-paper/10">
                    <Package className="h-5 w-5" />
                  </span>
                  <span className="absolute -bottom-1 -left-1 inline-flex h-5 w-5 items-center justify-center rounded-full bg-sky text-[10px] font-bold text-white ring-2 ring-elevated">4</span>
                </div>
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-semibold text-paper">Neo 10 R</p>
                  <p className="font-mono text-[11px] text-dim">SKU 578392</p>
                </div>
                <span className="rounded-md bg-paper/5 px-2 py-1 font-mono text-[11px] text-dim">12 pcs</span>
              </div>
              <div className="mt-2 flex items-center gap-3 rounded-xl border border-hairline bg-elevated/60 p-3 opacity-70">
                <span className="inline-flex h-6 w-6 items-center justify-center rounded border border-hairline text-teal">
                  <Check className="h-3.5 w-3.5" />
                </span>
                <p className="flex-1 truncate text-sm text-paper">Tempered glass</p>
                <span className="rounded-md bg-amber/15 px-2 py-1 font-mono text-[11px] text-amber">-2 pcs</span>
              </div>
            </div>

            <div className="mt-auto pt-8">
              <span className="inline-flex items-center gap-1.5 rounded-full border border-teal/30 bg-teal/10 px-2.5 py-1 text-[11px] font-semibold text-teal">
                <span className="h-1.5 w-1.5 rounded-full bg-teal" /> Live in production
              </span>
              <h3 className="mt-4 font-display text-2xl font-bold tracking-tight">Dukania — Inventory &amp; POS</h3>
              <p className="mt-3 max-w-sm text-dim">
                Easily manage stock and expiry, bill online or offline, and reorder
                ahead of time — with reports and GST built in.
              </p>
              <div className="mt-6">
                <MagneticButton href="/dukania">Explore Dukania <ArrowRight className="h-4 w-4" /></MagneticButton>
              </div>
            </div>
          </div>
        </Reveal>

        {/* Repair-shop app (sky) */}
        <Reveal delay={0.1}>
          <div className="flex h-full gap-5 rounded-3xl border border-sky/20 bg-gradient-to-br from-sky/12 to-sky/[0.03] p-8">
            <div className="hidden w-40 shrink-0 rounded-2xl bg-sky/10 p-3 sm:block">
              <div className="rounded-lg border border-hairline bg-elevated p-2">
                <span className="inline-flex items-center gap-1 rounded bg-sky/20 px-2 py-1 text-[10px] font-semibold text-sky"><ScanLine className="h-3 w-3" /> Job card</span>
                <div className="mt-2 flex h-16 items-center justify-center rounded bg-gradient-to-br from-teal/20 to-sky/10">
                  <Wrench className="h-7 w-7 text-teal" />
                </div>
                <p className="mt-2 text-center font-mono text-[10px] text-dim">In repair</p>
              </div>
            </div>
            <div className="flex flex-col">
              <h3 className="font-display text-xl font-bold tracking-tight">Repair-shop app</h3>
              <p className="mt-2 text-sm text-dim">
                Standalone job cards, device tracking and delivery — the fastest way to
                run a repair counter.
              </p>
              <div className="mt-auto pt-5">
                <MagneticButton href="/contact" variant="ghost">Talk to us <ArrowRight className="h-4 w-4" /></MagneticButton>
              </div>
            </div>
          </div>
        </Reveal>

        {/* Salon membership (violet) */}
        <Reveal delay={0.15}>
          <div className="flex h-full gap-5 rounded-3xl border border-violet/25 bg-gradient-to-br from-violet/12 to-violet/[0.03] p-8">
            <div className="hidden w-40 shrink-0 rounded-2xl bg-violet/10 p-3 sm:block">
              <div className="rounded-lg border border-hairline bg-gradient-to-br from-violet/25 to-sky/15 p-3">
                <IdCard className="h-6 w-6 text-white/80" />
                <p className="mt-6 font-mono text-[10px] uppercase tracking-widest text-white/70">Gold member</p>
                <p className="font-display text-sm font-bold text-white">₹2,000 credit</p>
              </div>
            </div>
            <div className="flex flex-col">
              <h3 className="font-display text-xl font-bold tracking-tight">Salon membership + billing</h3>
              <p className="mt-2 text-sm text-dim">
                Memberships, bookings and billing for salons and studios — all the
                power of a POS, tuned for appointments.
              </p>
              <div className="mt-auto pt-5">
                <MagneticButton href="/contact" variant="ghost">Talk to us <ArrowRight className="h-4 w-4" /></MagneticButton>
              </div>
            </div>
          </div>
        </Reveal>
      </div>

      {/* which-fits bar */}
      <Reveal delay={0.1}>
        <div className="mt-6 flex flex-col items-start gap-6 rounded-3xl border border-hairline bg-paper/4 p-8 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex items-center gap-4">
            <div className="flex gap-2">
              {[
                { icon: Boxes, bg: "from-violet to-sky" },
                { icon: Wrench, bg: "from-teal to-sky" },
                { icon: Scissors, bg: "from-amber to-violet" },
              ].map((t, i) => (
                <span key={i} className={`inline-flex h-11 w-11 items-center justify-center rounded-xl bg-gradient-to-br ${t.bg} text-white shadow-lg`}>
                  <t.icon className="h-5 w-5" />
                </span>
              ))}
            </div>
            <h3 className="font-display text-xl font-bold tracking-tight sm:text-2xl">
              Which app fits your business?
            </h3>
          </div>
          <Link
            href="/contact"
            className="stamp-press inline-flex min-h-11 items-center gap-2 rounded-lg border border-hairline px-5 text-sm font-semibold text-paper hover:bg-paper/5"
          >
            Book a demo <ArrowRight className="h-4 w-4" />
          </Link>
        </div>
      </Reveal>
    </div>
  );
}
