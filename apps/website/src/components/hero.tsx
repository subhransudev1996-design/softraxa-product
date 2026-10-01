"use client";

import { motion, useReducedMotion } from "framer-motion";
import { ArrowRight, WifiOff, ReceiptText, Smartphone, Monitor } from "lucide-react";
import AuroraBg from "./aurora-bg";
import MagneticButton from "./magnetic-button";
import { DesktopShot, MobileShot } from "./app-shot";
import { desktopShots, mobileShots } from "@/lib/shots";

const ease = [0.22, 1, 0.36, 1] as const;

const POINTS = [
  { icon: WifiOff, label: "Works without internet" },
  { icon: ReceiptText, label: "GST-ready billing" },
  { icon: Smartphone, label: "Android app" },
  { icon: Monitor, label: "Windows software" },
];

/**
 * Home hero: who Softraxa is in one short, two-line headline, then the
 * product it makes — the real Dukania screens rise into view above the fold.
 * The headline's second line (after "\n") is the coloured one.
 */
export default function Hero({ content }: { content?: { badge?: string; title?: string; description?: string; primary_cta?: string; secondary_cta?: string } }) {
  const reduced = useReducedMotion();

  const container = {
    hidden: {},
    show: { transition: { staggerChildren: 0.08, delayChildren: 0.05 } },
  };
  const item = reduced
    ? { hidden: { opacity: 1, y: 0 }, show: { opacity: 1, y: 0 } }
    : {
        hidden: { opacity: 0, y: 20 },
        show: { opacity: 1, y: 0, transition: { duration: 0.6, ease } },
      };

  const badgeText = content?.badge || "Made in India · for Indian shops";
  const titleText = content?.title || "Software that runs\nyour shop, online or off.";
  const [firstLine, ...rest] = titleText.split("\n");
  const descriptionText =
    content?.description ||
    "Softraxa makes Dukania — billing, stock and GST software that keeps working when the internet doesn't. On the phone you already have and the counter PC.";
  const primaryCta = content?.primary_cta || "Explore Dukania";
  const secondaryCta = content?.secondary_cta || "Book a free demo";

  return (
    <section className="relative overflow-hidden border-b border-hairline">
      <AuroraBg />

      <div className="relative mx-auto max-w-7xl px-6 pt-14 sm:pt-20">
        <motion.div variants={container} initial="hidden" animate="show" className="mx-auto max-w-4xl text-center">
          <motion.p
            variants={item}
            className="inline-flex items-center gap-2 rounded-full border border-hairline bg-paper/4 px-3 py-1 font-mono text-[11px] uppercase tracking-[0.15em] text-sky"
          >
            <span className="h-1.5 w-1.5 rounded-full bg-teal" /> {badgeText}
          </motion.p>

          <motion.h1
            variants={item}
            className="mt-6 text-balance font-display text-4xl font-bold leading-[1.06] tracking-tight sm:text-6xl lg:text-[4.1rem]"
          >
            {rest.length ? (
              <>
                {firstLine}
                <br />
                <span className="gradient-text">{rest.join(" ")}</span>
              </>
            ) : (
              <span className="gradient-text">{titleText}</span>
            )}
          </motion.h1>

          <motion.p variants={item} className="mx-auto mt-6 max-w-2xl text-pretty text-lg text-dim">
            {descriptionText}
          </motion.p>

          <motion.div variants={item} className="mt-8 flex flex-wrap items-center justify-center gap-3">
            <MagneticButton href="/dukania">
              {primaryCta} <ArrowRight className="h-4 w-4" />
            </MagneticButton>
            <MagneticButton href="/contact" variant="ghost">{secondaryCta}</MagneticButton>
          </motion.div>

          <motion.ul variants={item} className="mx-auto mt-8 flex max-w-2xl flex-wrap items-center justify-center gap-x-6 gap-y-3 text-sm text-dim">
            {POINTS.map(({ icon: Icon, label }) => (
              <li key={label} className="inline-flex items-center gap-2">
                <Icon className="h-4 w-4 text-teal" aria-hidden="true" /> {label}
              </li>
            ))}
          </motion.ul>
        </motion.div>
      </div>

      {/* The real app rises into view: tilted back, fading into the page. */}
      <motion.div
        initial={reduced ? false : { opacity: 0, y: 40 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.9, delay: 0.3, ease }}
        className="relative mx-auto mt-12 max-h-[300px] w-full max-w-6xl overflow-hidden px-6 pt-2 sm:mt-14 sm:max-h-[520px] lg:max-h-[600px]"
      >
        <div className="[perspective:2200px]">
          <div className="relative origin-top [transform:rotateX(9deg)]">
            <DesktopShot shot={desktopShots.newBill} label="Dukania · New Bill" priority />
            <div className="absolute -right-2 top-[18%] hidden w-[22%] max-w-[230px] sm:block lg:right-2">
              <MobileShot shot={mobileShots.dashboard} priority />
            </div>
          </div>
        </div>
        {/* fade the bottom of the screenshots into the page */}
        <div className="pointer-events-none absolute inset-x-0 bottom-0 h-40 bg-gradient-to-t from-bg via-bg/80 to-transparent" />
      </motion.div>
    </section>
  );
}
