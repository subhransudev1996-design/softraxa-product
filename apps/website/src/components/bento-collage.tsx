import { QrCode, Plus, TrendingUp, MapPin, Wrench, Package, MoreHorizontal } from "lucide-react";
import Reveal from "./reveal";

/**
 * A floating "bento" collage of representative Dukania cards — an energetic,
 * colourful glance at what the app tracks. Inspired by the montage on
 * inflowinventory.com but rebuilt entirely in our dark aurora/glass language
 * with our own CSS-drawn cards (no external product photos). The data is
 * illustrative, not a real customer's.
 */
export default function BentoCollage() {
  return (
    <div className="grid grid-cols-2 gap-4 sm:gap-5 lg:grid-cols-4 lg:auto-rows-[132px]">
      {/* Service rate (amber) */}
      <Reveal className="col-span-1 lg:row-span-2" delay={0.05}>
        <div className="float-1 flex h-full flex-col justify-between rounded-2xl border border-amber/30 bg-amber/10 p-5">
          <div className="flex items-center justify-between">
            <span className="inline-flex h-9 w-9 items-center justify-center rounded-xl bg-amber/20 text-amber">
              <Wrench className="h-4 w-4" />
            </span>
            <span className="h-4 w-8 rounded-full bg-amber/40" />
          </div>
          <div>
            <p className="font-mono text-[11px] uppercase tracking-wide text-amber/80">Service rate</p>
            <p className="mt-1 font-display text-2xl font-bold text-paper">₹1,000</p>
            <p className="text-xs text-dim">Screen replace</p>
          </div>
        </div>
      </Reveal>

      {/* Quantity on hand (big number, gradient) */}
      <Reveal className="col-span-2 lg:row-span-2" delay={0.1}>
        <div className="float-2 relative flex h-full flex-col justify-between overflow-hidden rounded-2xl bg-gradient-to-br from-violet to-sky p-6 text-white">
          <div className="flex items-center justify-between">
            <p className="font-mono text-xs font-semibold uppercase tracking-widest text-white/80">Quantity on hand</p>
            <span className="inline-flex items-center gap-1 rounded-full bg-white/15 px-2.5 py-1 text-xs">
              <MapPin className="h-3 w-3" /> Your shop
            </span>
          </div>

          <div>
            <div className="flex items-end gap-3">
              <p className="font-display text-6xl font-extrabold leading-none tracking-tight">537</p>
              <span className="mb-1 text-sm font-medium text-white/70">units</span>
              <span className="mb-1.5 inline-flex items-center gap-1 rounded-full bg-white/20 px-2 py-0.5 text-xs font-semibold">
                <TrendingUp className="h-3 w-3" /> 12%
              </span>
            </div>
            <p className="mt-2 text-sm text-white/75">across 142 products · ₹2,84,290 value</p>
          </div>

          {/* mini bar sparkline so the card reads as live data, not blank space */}
          <div className="flex items-end gap-1.5" aria-hidden="true">
            {[42, 55, 38, 64, 48, 72, 60, 80, 68, 90].map((h, i) => (
              <div
                key={i}
                className="flex-1 rounded-sm bg-white/40"
                style={{ height: `${h * 0.32}px` }}
              />
            ))}
          </div>
        </div>
      </Reveal>

      {/* Pricing panel (tall) */}
      <Reveal className="col-span-1 lg:row-span-3" delay={0.15}>
        <div className="float-3 flex h-full flex-col rounded-2xl border border-hairline bg-paper/4 p-5">
          <div className="flex gap-1.5">
            <span className="rounded-md bg-sky/20 px-2 py-1 text-[10px] font-semibold text-sky">Overview</span>
            <span className="rounded-md px-2 py-1 text-[10px] text-dim">Stock</span>
            <span className="rounded-md px-2 py-1 text-[10px] text-dim">Pricing</span>
          </div>
          <p className="mt-5 font-display text-base font-semibold text-paper">Pricing &amp; cost</p>
          <div className="mt-4 space-y-2.5 text-xs">
            <Row label="MRP" value="₹32,000" />
            <Row label="Selling" value="₹30,000" />
            <Row label="Purchase" value="₹25,000" />
            <Row label="GST" value="12%" />
          </div>
          <div className="mt-auto pt-4">
            <div className="rounded-lg border border-hairline bg-paper/4 px-3 py-2 text-center font-mono text-sm text-teal">
              Margin ₹5,000
            </div>
          </div>
        </div>
      </Reveal>

      {/* Product row */}
      <Reveal className="col-span-2 lg:col-span-2" delay={0.1}>
        <div className="float-1 flex h-full items-center gap-3 rounded-2xl border border-hairline bg-paper/4 p-4">
          <span className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-violet/25 to-sky/20 text-sky ring-1 ring-paper/10">
            <Package className="h-5 w-5" />
          </span>
          <div className="min-w-0 flex-1">
            <p className="truncate font-semibold text-paper">Neo 10 R</p>
            <p className="font-mono text-xs text-dim">SKU 578392 · ₹30,000</p>
          </div>
          <MoreHorizontal className="h-4 w-4 shrink-0 text-dim" />
        </div>
      </Reveal>

      {/* Scan card */}
      <Reveal className="col-span-1" delay={0.15}>
        <div className="float-2 flex h-full flex-col items-center justify-center gap-2 rounded-2xl border border-hairline bg-paper/4 p-4 text-center">
          <QrCode className="h-9 w-9 text-paper" />
          <p className="font-mono text-[11px] text-dim">Scan to bill</p>
        </div>
      </Reveal>

      {/* In stock */}
      <Reveal className="col-span-1" delay={0.2}>
        <div className="float-3 relative flex h-full flex-col justify-between rounded-2xl border border-hairline bg-paper/4 p-4">
          <div className="flex items-start justify-between">
            <span className="inline-flex h-8 w-8 items-center justify-center rounded-lg border border-hairline bg-paper/4 text-paper">
              <Plus className="h-4 w-4" />
            </span>
            <span className="rounded-full bg-teal/20 px-2.5 py-1 text-[11px] font-semibold text-teal">12 in stock</span>
          </div>
          <p className="font-semibold text-paper">Cooking oil 1L</p>
        </div>
      </Reveal>

      {/* Barcode product */}
      <Reveal className="col-span-2 lg:col-span-3" delay={0.15}>
        <div className="float-1 flex h-full items-center justify-between gap-4 rounded-2xl border border-hairline bg-paper/4 p-5">
          <div>
            <p className="font-semibold text-paper">Product name</p>
            <p className="font-mono text-xs text-dim">SKU-000 · ₹—</p>
          </div>
          <div className="barcode h-10 w-40 rounded opacity-80" aria-hidden="true" />
        </div>
      </Reveal>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-dim">{label}</span>
      <span className="font-mono text-paper">{value}</span>
    </div>
  );
}
