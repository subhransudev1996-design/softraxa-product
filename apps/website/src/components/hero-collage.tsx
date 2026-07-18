import {
  QrCode, Package, Layers, MousePointer2, Settings, MapPin, ChevronRight,
} from "lucide-react";
import type { ReactNode } from "react";

/**
 * Full-bleed marquee collage for the Dukania hero — our take on the montage
 * in inflowinventory.com's product hero, but animated: two rows of cards loop
 * horizontally in opposite directions across the full width of the screen.
 * Rebuilt in our dark glass/aurora language with CSS-drawn cards (no copied
 * stock photos), ₹ amounts and an Indian context. Illustrative data.
 * The loop pauses under prefers-reduced-motion (see globals.css).
 */

const card = "h-36 shrink-0 rounded-2xl p-4 overflow-hidden";

function QRCard() {
  return (
    <div className={`${card} flex w-36 items-center justify-center border border-amber/25 bg-amber/10`}>
      <QrCode className="h-14 w-14 text-amber" strokeWidth={1.4} />
    </div>
  );
}

function ProductCard() {
  return (
    <div className={`${card} relative flex w-44 items-center justify-center border border-amber/25 bg-amber/10`}>
      <span className="absolute right-3 top-3 z-10 inline-flex items-center gap-1 rounded-lg bg-teal/20 px-2 py-1 text-xs font-semibold text-teal">
        +5 <Layers className="h-3.5 w-3.5" />
      </span>
      <div className="flex h-full w-full items-center justify-center rounded-xl bg-gradient-to-br from-amber/25 to-violet/15">
        <Package className="h-11 w-11 text-amber/70" strokeWidth={1.2} />
      </div>
    </div>
  );
}

function OrderCard() {
  return (
    <div className={`${card} flex w-[22rem] items-center gap-3 border border-hairline bg-elevated`}>
      <span className="h-9 w-1 shrink-0 rounded bg-teal" />
      <span className="font-mono text-sm text-paper">SO-000023</span>
      <span className="rounded-lg bg-teal/20 px-3 py-1.5 text-xs font-semibold text-teal">Fulfilled</span>
      <span className="rounded-lg bg-amber/20 px-3 py-1.5 text-xs font-semibold text-amber">₹10,000</span>
    </div>
  );
}

function QuantityCard() {
  return (
    <div className={`${card} flex w-56 items-center justify-between border border-transparent bg-gradient-to-br from-sky to-violet text-white`}>
      <div>
        <p className="text-xs text-white/80">Quantity on hand</p>
        <p className="font-display text-4xl font-bold leading-none">40</p>
      </div>
      <ChevronRight className="h-5 w-5" />
    </div>
  );
}

function ProductsCountCard() {
  return (
    <div className={`${card} flex w-52 items-center gap-3 border border-amber/25 bg-amber/10`}>
      <span className="inline-flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-bg font-display text-base font-bold text-amber">79</span>
      <span className="font-display font-semibold text-paper">Products</span>
    </div>
  );
}

function ScanCard() {
  return (
    <div className={`${card} flex w-56 flex-col border border-amber/25 bg-amber/10`}>
      <span className="inline-flex w-fit items-center rounded-full bg-bg px-3 py-1 text-xs font-semibold text-paper">Scan</span>
      <div className="relative mt-2 flex flex-1 items-center justify-center rounded-xl bg-gradient-to-br from-sky/25 to-violet/20">
        <div className="grid grid-cols-3 gap-1">
          {Array.from({ length: 9 }).map((_, i) => (
            <span key={i} className="h-4 w-6 rounded-sm bg-sky/40" />
          ))}
        </div>
        <MousePointer2 className="absolute bottom-1 right-2 h-6 w-6 fill-bg text-paper" />
      </div>
    </div>
  );
}

function SerialsCard() {
  return (
    <div className={`${card} flex w-72 flex-col justify-center border border-sky/25 bg-sky/10`}>
      <p className="text-center font-display text-sm font-semibold text-sky">2/4 serials selected</p>
      <div className="mt-2 h-1.5 w-full rounded-full bg-white/10">
        <div className="h-1.5 w-1/2 rounded-full bg-sky" />
      </div>
      <div className="mt-3 flex items-center gap-2">
        <Settings className="h-4 w-4 shrink-0 text-dim" />
        <span className="flex-1 rounded-lg border border-hairline bg-elevated px-3 py-1.5 font-mono text-sm tracking-widest text-paper">•••••</span>
        <span className="h-7 w-9 shrink-0 rounded-lg bg-amber" />
      </div>
    </div>
  );
}

function PickedCard() {
  return (
    <div className={`${card} flex w-56 flex-col border border-teal/25 bg-teal/10`}>
      <span className="inline-flex w-fit items-center gap-1 rounded-full bg-teal/20 px-2.5 py-0.5 text-xs font-semibold text-teal">
        <MapPin className="h-3 w-3" /> Pune, MH
      </span>
      <div className="relative mt-2 flex flex-1 items-center justify-center rounded-xl bg-gradient-to-br from-teal/20 to-sky/10">
        <Package className="h-10 w-10 text-teal/70" strokeWidth={1.2} />
        <span className="absolute right-2 top-2 rounded-lg bg-elevated px-2 py-0.5 text-xs font-semibold text-paper shadow">2/7 Picked</span>
      </div>
    </div>
  );
}

function BarcodeCard() {
  return (
    <div className={`${card} flex w-48 flex-col justify-center border border-hairline bg-elevated`}>
      <div className="flex items-center gap-2 text-[11px] text-dim">
        <span className="rounded bg-sky/20 px-1.5 py-0.5 text-sky">name</span>
        <span className="font-mono text-paper">150 W</span>
      </div>
      <div className="barcode barcode-dark mt-2 h-9 w-full rounded bg-white p-1" />
    </div>
  );
}

function KeypadCard() {
  return (
    <div className={`${card} flex w-64 items-center gap-2 border border-sky/25 bg-sky/10`}>
      {Array.from({ length: 5 }).map((_, i) => (
        <span key={i} className="h-16 flex-1 rounded-lg border border-hairline bg-elevated" />
      ))}
    </div>
  );
}

function LowStockCard() {
  return (
    <div className={`${card} flex w-40 flex-col justify-center border border-amber/25 bg-amber/10`}>
      <p className="font-display text-3xl font-bold text-amber">2</p>
      <p className="text-xs text-dim">items low on stock</p>
    </div>
  );
}

const ROW_A: ReactNode[] = [
  <QRCard key="qr" />, <ProductCard key="pr" />, <OrderCard key="so" />,
  <QuantityCard key="qty" />, <ProductsCountCard key="pc" />, <BarcodeCard key="bc" />,
];
const ROW_B: ReactNode[] = [
  <ScanCard key="sc" />, <SerialsCard key="se" />, <KeypadCard key="kp" />,
  <PickedCard key="pk" />, <LowStockCard key="ls" />, <ProductCard key="pr2" />,
];

function Track({ cards, className }: { cards: ReactNode[]; className: string }) {
  const set = <div className="flex shrink-0 gap-4 pr-4">{cards}</div>;
  return (
    <div className={`flex w-max ${className}`}>
      {set}
      {set}
    </div>
  );
}

export default function HeroCollage() {
  return (
    <div className="relative space-y-4 overflow-hidden py-2">
      <Track cards={ROW_A} className="marquee-a" />
      <Track cards={ROW_B} className="marquee-b" />
      {/* edge fades */}
      <div className="pointer-events-none absolute inset-y-0 left-0 w-24 bg-gradient-to-r from-bg to-transparent sm:w-40" />
      <div className="pointer-events-none absolute inset-y-0 right-0 w-24 bg-gradient-to-l from-bg to-transparent sm:w-40" />
    </div>
  );
}
