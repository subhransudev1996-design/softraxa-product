"use client";

import { useState } from "react";
import Image from "next/image";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { desktopShots, type Shot } from "@/lib/shots";

type Tab = {
  label: string;
  blocks: { h: string; p: string }[];
  shot: Shot;
};

const TABS: Tab[] = [
  {
    label: "See all your bills",
    blocks: [
      { h: "Triage bills by status", p: "Filter by paid, partial, credit, estimates or cash memos, so you always know what needs chasing and what's settled." },
      { h: "All your money in one place", p: "Dukania isn't just billing. Track the cost of each purchase and see the profit on every sale — the whole shop's money in one list." },
    ],
    shot: desktopShots.invoices,
  },
  {
    label: "Know what's in stock",
    blocks: [
      { h: "See stock levels at a glance", p: "Live counts with low and out-of-stock flags, so you never oversell a customer or double-order from a supplier." },
      { h: "Track expiry too", p: "Items nearing their expiry date surface automatically inside a 30-day window — before they turn into dead stock." },
    ],
    shot: desktopShots.stock,
  },
  {
    label: "Reorder ahead of time",
    blocks: [
      { h: "Get notified ahead of time", p: "A push alert the moment something runs low or nears expiry — so you reorder before it costs you a sale." },
      { h: "Reports that guide reordering", p: "Product-wise sales and stock reports show exactly what's moving, so you buy the right amount of the right things." },
    ],
    shot: desktopShots.reports,
  },
];

export default function ThreeWaysTabs() {
  const [active, setActive] = useState(0);
  const reduced = useReducedMotion();
  const tab = TABS[active];

  const fade = reduced
    ? {}
    : { initial: { opacity: 0, y: 12 }, animate: { opacity: 1, y: 0 }, exit: { opacity: 0, y: -12 }, transition: { duration: 0.3, ease: "easeOut" as const } };

  return (
    <div>
      {/* tab switcher */}
      <div role="tablist" aria-label="Ways to speed up work" className="mx-auto flex w-fit flex-wrap justify-center gap-1 rounded-full border border-hairline bg-paper/4 p-1.5">
        {TABS.map((t, i) => (
          <button
            key={t.label}
            role="tab"
            aria-selected={active === i}
            onClick={() => setActive(i)}
            className={`min-h-11 rounded-full px-5 text-sm font-semibold transition-colors ${
              active === i ? "bg-paper text-bg" : "text-dim hover:text-paper"
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      {/* content */}
      <div className="mt-14 grid items-center gap-12 lg:grid-cols-2">
        <AnimatePresence mode="wait">
          <motion.div key={`txt-${active}`} {...fade} className="space-y-8">
            {tab.blocks.map((b) => (
              <div key={b.h}>
                <h3 className="font-display text-2xl font-bold tracking-tight">{b.h}</h3>
                <p className="mt-3 max-w-md text-dim">{b.p}</p>
              </div>
            ))}
          </motion.div>
        </AnimatePresence>

        <AnimatePresence mode="wait">
          <motion.div key={`img-${active}`} {...fade} className="overflow-hidden rounded-2xl border border-hairline shadow-2xl shadow-black/50">
            <Image
              src={tab.shot.src}
              width={tab.shot.width}
              height={tab.shot.height}
              alt={tab.shot.alt}
              sizes="(max-width: 1024px) 100vw, 55vw"
              className="h-auto w-full"
            />
          </motion.div>
        </AnimatePresence>
      </div>
    </div>
  );
}
