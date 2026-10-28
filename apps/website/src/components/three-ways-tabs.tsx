"use client";

import { useState } from "react";
import Image from "next/image";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { desktopShots, type Shot } from "@/lib/shots";

type Tab = { label: string; title: string; body: string; shot: Shot };

const TABS: Tab[] = [
  {
    label: "See all your bills",
    title: "See all your bills",
    body: "Find any bill in seconds, filter by date, customer or payment method, and share or print it again.",
    shot: desktopShots.invoices,
  },
  {
    label: "Know what's in stock",
    title: "Know what's in stock",
    body: "Live counts with low and out-of-stock flags, and items nearing expiry before they turn into a loss.",
    shot: desktopShots.stock,
  },
  {
    label: "Reorder ahead of time",
    title: "Reorder ahead of time",
    body: "Sales and stock reports show what is moving, so you buy the right amount of the right things.",
    shot: desktopShots.reports,
  },
];

export default function ThreeWaysTabs() {
  const [active, setActive] = useState(0);
  const reduced = useReducedMotion();
  const tab = TABS[active];
  const fade = reduced
    ? {}
    : { initial: { opacity: 0, y: 8 }, animate: { opacity: 1, y: 0 }, exit: { opacity: 0, y: -8 }, transition: { duration: 0.25 } };

  return (
    <div className="h-full rounded-3xl border border-hairline bg-white p-6 shadow-card sm:p-8">
      <p className="text-xs font-bold uppercase tracking-[0.16em] text-brand-2">Three ways Dukania helps</p>
      <div role="tablist" aria-label="Three ways Dukania helps" className="mt-4 flex flex-wrap gap-2">
        {TABS.map((t, i) => (
          <button
            key={t.label}
            role="tab"
            aria-selected={active === i}
            onClick={() => setActive(i)}
            className={`min-h-10 rounded-full px-4 text-sm font-semibold transition-colors ${
              active === i ? "bg-brand text-white" : "bg-elevated text-dim hover:text-paper"
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>
      <AnimatePresence mode="wait">
        <motion.div key={active} {...fade} className="mt-6 grid grid-cols-1 items-center gap-6 sm:grid-cols-[1fr_1.2fr]">
          <div>
            <h3 className="font-display text-xl font-bold tracking-tight">{tab.title}</h3>
            <p className="mt-2 text-sm text-dim">{tab.body}</p>
          </div>
          <div className="overflow-hidden rounded-xl border border-hairline shadow-card">
            <Image src={tab.shot.src} width={tab.shot.width} height={tab.shot.height} alt={tab.shot.alt}
              sizes="(max-width: 640px) 100vw, 360px" className="h-auto w-full" />
          </div>
        </motion.div>
      </AnimatePresence>
    </div>
  );
}
