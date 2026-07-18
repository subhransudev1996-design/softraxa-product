import {
  Search, X, ShoppingCart, Minus, Plus, Check, Package, CornerDownRight,
} from "lucide-react";

/**
 * Decorative "catalog & estimates" illustration for the Dukania showroom-style
 * section — our take on the graphic in inflowinventory.com's Showroom block.
 * Rebuilt in CSS in our dark glass/aurora language (no copied product photos):
 * a product catalog grid behind a customize + order card. Purely illustrative;
 * framed in the section copy around Dukania's real catalog + estimates.
 */

const CATALOG: { name: string; price: string; tile: string }[] = [
  { name: "Copper pipe 12'", price: "₹1,650", tile: "from-amber/40 to-amber/20" },
  { name: "Motor 1HP", price: "₹4,200", tile: "from-sky/40 to-sky/20" },
  { name: "Steel pan", price: "₹900", tile: "from-white/15 to-white/[0.05]" },
  { name: "Electrical wire", price: "₹250", tile: "from-violet/40 to-violet/20" },
];

const SWATCHES = ["bg-violet", "bg-sky", "bg-teal", "bg-amber"];

export default function ShowroomIllustration() {
  return (
    <div className="relative mx-auto h-[420px] w-full max-w-xl">
      {/* catalog browser (back) */}
      <div className="absolute left-0 top-10 z-10 w-[68%] rounded-2xl border border-hairline bg-elevated p-3 shadow-xl">
        <div className="flex items-center gap-2 border-b border-hairline pb-2.5">
          <span className="inline-flex h-6 w-6 items-center justify-center rounded bg-teal/20 text-teal"><Search className="h-3 w-3" /></span>
          <span className="h-5 flex-1 rounded bg-paper/5" />
          <span className="h-5 w-10 rounded bg-paper/5" />
        </div>
        <div className="mt-3 grid grid-cols-2 gap-2.5">
          {CATALOG.map((p) => (
            <div key={p.name} className="rounded-lg border border-hairline bg-surface p-2">
              <div className={`flex h-14 items-center justify-center rounded-md bg-gradient-to-br ${p.tile}`}>
                <Package className="h-6 w-6 text-white/70" strokeWidth={1.3} />
              </div>
              <p className="mt-2 truncate text-[11px] font-semibold text-paper">{p.name}</p>
              <div className="mt-1 flex items-center justify-between">
                <span className="font-mono text-[11px] text-dim">{p.price}</span>
                <span className="inline-flex items-center gap-0.5 text-[9px] font-semibold text-teal">
                  <Check className="h-2.5 w-2.5" /> In stock
                </span>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* customize + order (front) */}
      <div className="absolute right-0 top-0 z-20 w-[58%] space-y-3">
        {/* customize header */}
        <div className="flex items-center gap-2">
          <span className="inline-flex items-center rounded-full bg-bg px-4 py-2 text-sm font-bold text-paper">Customize</span>
          <CornerDownRight className="h-5 w-5 text-dim" />
        </div>

        {/* theme / layout */}
        <div className="rounded-2xl border border-hairline bg-elevated p-3 shadow-xl">
          <div className="flex items-center justify-between border-b border-hairline pb-2.5">
            <span className="text-xs font-semibold text-paper">Theme</span>
            <div className="flex gap-1.5">
              {SWATCHES.map((s) => (
                <span key={s} className={`h-5 w-5 rounded-full ${s}`} />
              ))}
            </div>
          </div>
          <div className="flex items-center justify-between pt-2.5 text-xs">
            <span className="font-semibold text-paper">Layout</span>
            <div className="flex items-center gap-3">
              <span className="inline-flex items-center gap-1.5"><span className="h-4 w-4 rounded-full bg-amber" /><span className="text-dim">Grid</span></span>
              <span className="inline-flex items-center gap-1.5"><span className="h-4 w-4 rounded-full bg-paper/10" /><span className="text-dim">List</span></span>
            </div>
          </div>
        </div>

        {/* order / estimate card */}
        <div className="rounded-2xl border border-hairline bg-elevated p-3 shadow-2xl shadow-black/40">
          <div className="flex items-center justify-between border-b border-hairline pb-2.5">
            <span className="inline-flex items-center gap-2 text-sm font-semibold text-paper"><X className="h-4 w-4 text-dim" /> Your estimate</span>
            <span className="relative inline-flex"><ShoppingCart className="h-4 w-4 text-dim" /><span className="absolute -right-1 -top-1 h-2 w-2 rounded-full bg-sky" /></span>
          </div>
          <div className="mt-3 flex items-center gap-3">
            <span className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br from-violet/40 to-violet/20">
              <Package className="h-5 w-5 text-white/80" />
            </span>
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-semibold text-sky">Electrical wire — Black</p>
              <div className="mt-1.5 flex items-center gap-2">
                <span className="inline-flex items-center rounded-md border border-hairline bg-surface">
                  <span className="inline-flex h-6 w-6 items-center justify-center text-dim"><Minus className="h-3 w-3" /></span>
                  <span className="w-5 text-center font-mono text-xs text-paper">6</span>
                  <span className="inline-flex h-6 w-6 items-center justify-center text-sky"><Plus className="h-3 w-3" /></span>
                </span>
                <span className="font-mono text-sm font-semibold text-paper">₹1,500</span>
              </div>
            </div>
          </div>
          <button className="mt-3 w-full rounded-lg bg-gradient-to-r from-violet to-sky py-2.5 text-sm font-semibold text-white">
            Add to estimate
          </button>
        </div>
      </div>
    </div>
  );
}
