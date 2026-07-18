import type { CSSProperties } from "react";
import {
  Pencil, Plus, ExternalLink, RefreshCw, X, ShoppingBag, ChevronRight, MousePointer2,
} from "lucide-react";

/**
 * Decorative "on the go" app illustration for the Dukania mobile section — our
 * take on the graphic in inflowinventory.com's mobile block. Rebuilt in CSS in
 * our dark glass/aurora language (no copied assets): a product list card with
 * stock chips and an "Adjust stock" button, a left action rail, an app-icon
 * grid with a highlighted app + cursor, and a barcode. Purely illustrative.
 */

function ProductRow({
  name, sub, tile, bin, qty, delta, deltaTone,
}: {
  name: string; sub: string; tile: string; bin: string; qty: string; delta: string; deltaTone: string;
}) {
  return (
    <div className="flex items-center gap-3 border-b border-hairline py-3 last:border-0">
      <span className={`inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br ${tile}`}>
        <ShoppingBag className="h-5 w-5 text-white/80" />
      </span>
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-semibold text-paper">{name}</p>
        <p className="truncate text-[11px] text-dim">{sub}</p>
      </div>
      <div className="flex items-center gap-1.5">
        <span className="rounded bg-sky/15 px-1.5 py-0.5 font-mono text-[10px] text-sky">{bin}</span>
        <span className="rounded bg-amber/15 px-1.5 py-0.5 font-mono text-[10px] text-amber">{qty}</span>
        <span className={`font-mono text-[11px] font-semibold ${deltaTone}`}>{delta}</span>
      </div>
      <ChevronRight className="h-4 w-4 shrink-0 text-dim" />
    </div>
  );
}

export default function MobileIllustration() {
  return (
    <div className="relative mx-auto h-[440px] w-full max-w-md">
      {/* amber base panel */}
      <div className="absolute inset-0 rounded-3xl border border-amber/20 bg-amber/[0.08]" />

      {/* product list card */}
      <div className="absolute left-16 right-4 top-6 z-10 rounded-2xl border border-hairline bg-elevated p-3 shadow-xl">
        <ProductRow name="Thermal bag — Violet" sub="Insulated food bag for delivery" tile="from-violet/60 to-violet/30" bin="A2" qty="448" delta="-2" deltaTone="text-red-400" />
        <ProductRow name="Thermal bag — Amber" sub="Insulated food bag, large" tile="from-amber/60 to-amber/30" bin="A4" qty="320" delta="+4" deltaTone="text-teal" />
        <button className="mt-3 w-full rounded-lg bg-amber py-2.5 text-sm font-semibold text-bg">Adjust stock</button>
      </div>

      {/* left action rail */}
      <div className="absolute left-2 top-20 z-20 flex flex-col gap-1 rounded-2xl border border-hairline bg-surface p-1.5 shadow-xl">
        {[Pencil, Plus, ExternalLink, RefreshCw].map((Icon, i) => (
          <span key={i} className="inline-flex h-9 w-9 items-center justify-center rounded-lg text-paper hover:bg-paper/5">
            <Icon className="h-4 w-4" />
          </span>
        ))}
        <span className="inline-flex h-9 w-9 items-center justify-center rounded-lg text-red-400">
          <X className="h-4 w-4" />
        </span>
      </div>

      {/* app-icon grid card with highlighted app + cursor */}
      <div className="absolute bottom-4 left-10 right-16 z-20 rounded-2xl border border-hairline bg-surface p-4 shadow-xl">
        <div className="flex items-center justify-between text-[10px] text-dim">
          <span className="font-mono">9:41</span>
          <span className="font-mono">▪ ▪ ▪</span>
        </div>
        <div className="relative mt-3 grid grid-cols-4 gap-2.5">
          {Array.from({ length: 8 }).map((_, i) => (
            <span key={i} className="aspect-square rounded-lg bg-paper/6" />
          ))}
          {/* highlighted Dukania app */}
          <span className="absolute left-[26%] top-1/2 inline-flex h-12 w-12 -translate-y-1/2 items-center justify-center rounded-xl bg-gradient-to-br from-amber to-amber/70 font-display text-lg font-bold text-bg shadow-lg">
            D
          </span>
          <MousePointer2 className="absolute left-[44%] top-[62%] h-7 w-7 fill-bg text-paper" />
        </div>
      </div>

      {/* barcode */}
      <div className="absolute bottom-24 right-1 z-10 rounded-lg border border-dashed border-amber/40 bg-amber/[0.06] p-2">
        <div className="barcode h-10 w-20" style={{ "--bars": "var(--amber)" } as CSSProperties} />
      </div>
    </div>
  );
}
