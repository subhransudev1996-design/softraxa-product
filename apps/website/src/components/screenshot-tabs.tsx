"use client";

import { useState } from "react";
import Image from "next/image";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { Monitor, Smartphone } from "lucide-react";
import { desktopShots, mobileShots, type Shot } from "@/lib/shots";
import { BrowserFrame, PhoneFrame } from "./device-frame";

type TabId = "desktop" | "mobile";

const DESKTOP_VIEWS: { label: string; shot: Shot }[] = [
  { label: "Billing", shot: desktopShots.newBill },
  { label: "Invoices", shot: desktopShots.invoices },
  { label: "Stock", shot: desktopShots.stock },
  { label: "Reports", shot: desktopShots.reports },
  { label: "Expenses", shot: desktopShots.expenses },
  { label: "Service catalog", shot: desktopShots.serviceCatalog },
];

const MOBILE_VIEWS: { label: string; shot: Shot }[] = [
  { label: "Home", shot: mobileShots.dashboard },
  { label: "New bill", shot: mobileShots.newBill },
  { label: "Checkout", shot: mobileShots.checkout },
  { label: "Products", shot: mobileShots.products },
  { label: "Reports", shot: mobileShots.reports },
  { label: "Job card", shot: mobileShots.jobCard },
];

export default function ScreenshotTabs() {
  const [tab, setTab] = useState<TabId>("desktop");
  const [index, setIndex] = useState(0);
  const reduced = useReducedMotion();

  const views = tab === "desktop" ? DESKTOP_VIEWS : MOBILE_VIEWS;
  const current = views[Math.min(index, views.length - 1)];

  function switchTab(next: TabId) {
    setTab(next);
    setIndex(0);
  }

  return (
    <div>
      {/* platform tabs */}
      <div role="tablist" aria-label="Platform" className="mx-auto flex w-fit gap-1 rounded-xl border border-hairline bg-paper/4 p-1">
        {([
          { id: "desktop" as const, label: "Desktop", Icon: Monitor },
          { id: "mobile" as const, label: "Mobile", Icon: Smartphone },
        ]).map(({ id, label, Icon }) => (
          <button
            key={id}
            role="tab"
            aria-selected={tab === id}
            aria-controls={`panel-${id}`}
            id={`tab-${id}`}
            onClick={() => switchTab(id)}
            className={`inline-flex min-h-11 items-center gap-2 rounded-lg px-5 text-sm font-semibold transition-colors ${
              tab === id ? "bg-paper text-bg" : "text-dim hover:text-paper"
            }`}
          >
            <Icon className="h-4 w-4" aria-hidden="true" />
            {label}
          </button>
        ))}
      </div>

      {/* view switcher */}
      <div className="mt-6 flex flex-wrap justify-center gap-2">
        {views.map((v, i) => (
          <button
            key={v.label}
            onClick={() => setIndex(i)}
            aria-pressed={index === i}
            className={`min-h-11 rounded-lg border px-4 text-sm transition-colors ${
              index === i
                ? "border-sky/40 bg-sky/10 text-paper"
                : "border-hairline text-dim hover:text-paper"
            }`}
          >
            {v.label}
          </button>
        ))}
      </div>

      {/* panel */}
      <div
        role="tabpanel"
        id={`panel-${tab}`}
        aria-labelledby={`tab-${tab}`}
        className="mt-10 flex justify-center"
      >
        <AnimatePresence mode="wait">
          <motion.div
            key={`${tab}-${current.label}`}
            initial={reduced ? false : { opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            exit={reduced ? { opacity: 0 } : { opacity: 0, y: -12 }}
            transition={{ duration: 0.25, ease: "easeOut" }}
            className={tab === "desktop" ? "w-full max-w-4xl" : ""}
          >
            {tab === "desktop" ? (
              <BrowserFrame label={`Dukania · ${current.label.toLowerCase()}`}>
                <Image
                  src={current.shot.src}
                  width={current.shot.width}
                  height={current.shot.height}
                  alt={current.shot.alt}
                  sizes="(max-width: 1024px) 100vw, 60vw"
                  className="h-auto w-full rounded-lg"
                />
              </BrowserFrame>
            ) : (
              <PhoneFrame>
                <Image
                  src={current.shot.src}
                  width={current.shot.width}
                  height={current.shot.height}
                  alt={current.shot.alt}
                  sizes="264px"
                  className="h-auto w-full rounded-[1.4rem]"
                />
              </PhoneFrame>
            )}
          </motion.div>
        </AnimatePresence>
      </div>
    </div>
  );
}
