import { Check, X, Plus, Minus, ShoppingCart, Image as ImageIcon, MousePointer2 } from "lucide-react";

/**
 * Decorative pricing-plans illustration for the Dukania pricing section — our
 * take on the graphic in inflowinventory.com's pricing block. Rebuilt in CSS
 * in our dark glass/aurora language (no copied assets): three stacked plan
 * cards with masked values, a "Save %" toggle, a "Most popular" bubble and a
 * quantity stepper. Purely illustrative.
 */

function CheckRow() {
  return (
    <div className="flex items-center gap-2">
      <span className="inline-flex h-5 w-5 items-center justify-center rounded-full bg-teal/20 text-teal">
        <Check className="h-3 w-3" />
      </span>
      <span className="h-2 flex-1 rounded bg-paper/10" />
    </div>
  );
}

function CrossRow() {
  return (
    <div className="flex items-center gap-2">
      <span className="inline-flex h-5 w-5 items-center justify-center rounded-full bg-red-500/20 text-red-400">
        <X className="h-3 w-3" />
      </span>
      <span className="h-2 flex-1 rounded bg-paper/6" />
    </div>
  );
}

export default function PricingIllustration() {
  return (
    <div className="relative mx-auto h-[440px] w-full max-w-md">
      {/* Save % toggle */}
      <div className="float-2 absolute left-6 top-2 z-30 flex w-64 items-center rounded-full border border-amber/30 bg-elevated p-1.5">
        <span className="ml-auto inline-flex items-center rounded-full bg-amber px-3 py-1 text-xs font-bold text-bg">Save %</span>
        <span className="ml-2 h-6 w-14 rounded-full bg-paper/6" />
      </div>

      {/* cart + (floating) */}
      <div className="float-1 absolute -left-2 top-24 z-30 inline-flex h-14 w-14 items-center justify-center rounded-2xl bg-teal text-white shadow-xl">
        <ShoppingCart className="h-6 w-6" />
        <span className="absolute -bottom-1 -right-1 inline-flex h-6 w-6 items-center justify-center rounded-full bg-teal ring-2 ring-bg">
          <Plus className="h-3.5 w-3.5" />
        </span>
      </div>

      {/* image tile (floating) */}
      <div className="float-3 absolute right-2 top-6 z-30 inline-flex h-14 w-14 rotate-12 items-center justify-center rounded-2xl bg-amber/80 text-bg shadow-xl">
        <ImageIcon className="h-6 w-6" />
      </div>

      {/* left plan card (dashed, behind) */}
      <div className="absolute left-4 top-24 z-10 w-44 rounded-2xl border border-dashed border-paper/15 bg-surface p-4">
        <span className="inline-flex rounded-md bg-paper/10 px-3 py-1.5 font-mono text-sm font-bold tracking-widest text-dim">**</span>
        <div className="mt-4 space-y-2">
          <span className="block h-2 w-3/4 rounded bg-paper/10" />
          <span className="block h-2 w-1/2 rounded bg-paper/10" />
        </div>
        <div className="mt-4 space-y-2.5">
          <CheckRow /><CrossRow /><CrossRow />
        </div>
      </div>

      {/* right plan card (dashed) */}
      <div className="absolute right-2 top-16 z-10 w-48 rounded-2xl border border-dashed border-paper/15 bg-surface p-4">
        <span className="inline-flex rounded-md bg-paper/10 px-3 py-1.5 font-mono text-sm font-bold tracking-widest text-dim">***</span>
        <div className="mt-4 space-y-2">
          <span className="block h-2 w-3/4 rounded bg-paper/10" />
          <span className="block h-2 w-2/3 rounded bg-paper/10" />
        </div>
        <div className="mt-4 space-y-2.5">
          <CheckRow /><CheckRow />
          <div className="flex items-center gap-2">
            <span className="inline-flex h-5 w-5 items-center justify-center rounded-full bg-amber/20 text-amber">
              <Plus className="h-3 w-3" />
            </span>
            <span className="h-2 flex-1 rounded bg-paper/10" />
          </div>
        </div>
      </div>

      {/* center plan card (highlighted, on top) */}
      <div className="absolute left-1/2 top-28 z-20 w-52 -translate-x-1/2 rounded-2xl border-2 border-amber bg-elevated p-4 shadow-2xl shadow-amber/10">
        <span className="inline-flex rounded-md bg-amber px-3 py-1.5 font-mono text-sm font-bold tracking-widest text-bg">***</span>
        <div className="mt-4 space-y-2">
          <span className="block h-2.5 w-3/4 rounded bg-paper/25" />
          <span className="block h-2.5 w-1/2 rounded bg-paper/15" />
        </div>
        <div className="mt-4 space-y-2.5">
          <CheckRow /><CheckRow /><CrossRow />
        </div>
        {/* Most popular bubble */}
        <div className="absolute -bottom-4 left-1/2 -translate-x-1/2 whitespace-nowrap rounded-lg bg-paper px-3 py-1.5 text-xs font-semibold text-bg shadow-lg">
          Most popular
        </div>
      </div>

      {/* quantity stepper */}
      <div className="float-2 absolute bottom-4 right-2 z-30 flex items-center gap-3 rounded-2xl bg-teal px-4 py-2.5 text-white shadow-xl">
        <Minus className="h-4 w-4" />
        <span className="font-display text-lg font-bold">3</span>
        <Plus className="h-4 w-4" />
        <MousePointer2 className="absolute -bottom-3 -right-3 h-7 w-7 fill-bg text-paper" />
      </div>
    </div>
  );
}
