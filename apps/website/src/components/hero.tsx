"use client";

import { motion, useReducedMotion } from "framer-motion";
import { ArrowRight } from "lucide-react";
import AuroraBg from "./aurora-bg";
import MagneticButton from "./magnetic-button";
import HeroCollage from "./hero-collage";

const ease = [0.22, 1, 0.36, 1] as const;

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

  const badgeText = content?.badge || "Software agency · India";
  
  // Format title with line break if it contains \n, otherwise render standard
  const titleText = content?.title || "Software that runs\nthe business, not just the browser.";
  const titleParts = titleText.split("\n");

  const descriptionText = content?.description || "Softraxa builds practical, offline-first business software. Our flagship product, Dukania, handles billing, stock and reporting for real shops across India — online or off.";
  const primaryCta = content?.primary_cta || "Book a free demo";
  const secondaryCta = content?.secondary_cta || "See Dukania";

  return (
    <section className="relative overflow-hidden border-b border-hairline">
      <AuroraBg />

      <div className="relative mx-auto max-w-7xl px-6 pt-16 sm:pt-24">
        <motion.div
          variants={container}
          initial="hidden"
          animate="show"
          className="mx-auto max-w-3xl text-center"
        >
          <motion.p
            variants={item}
            className="inline-flex items-center gap-2 rounded-full border border-hairline bg-paper/4 px-3 py-1 font-mono text-xs uppercase tracking-[0.15em] text-sky"
          >
            <span className="h-1.5 w-1.5 rounded-full bg-teal" /> {badgeText}
          </motion.p>

          <motion.h1
            variants={item}
            className="mt-6 font-display text-4xl font-bold leading-[1.05] tracking-tight sm:text-6xl"
          >
            {titleParts.length > 1 ? (
              <>
                <span className="gradient-text">{titleParts[0]}</span>
                <br />
                {titleParts.slice(1).join("\n")}
              </>
            ) : (
              <span className="gradient-text">{titleText}</span>
            )}
          </motion.h1>

          <motion.p variants={item} className="mx-auto mt-6 max-w-xl text-lg text-dim">
            {descriptionText}
          </motion.p>

          <motion.div variants={item} className="mt-9 flex flex-wrap items-center justify-center gap-4">
            <MagneticButton href="/contact">
              {primaryCta} <ArrowRight className="h-4 w-4" />
            </MagneticButton>
            <MagneticButton href="/dukania" variant="ghost">{secondaryCta}</MagneticButton>
          </motion.div>

          <motion.p variants={item} className="mt-4 font-mono text-xs text-dim">
            Free demo · No credit card needed
          </motion.p>
        </motion.div>
      </div>

      {/* Full-width marquee loop of localized cards */}
      <motion.div
        initial={reduced ? false : { opacity: 0, y: 28 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.9, delay: 0.25, ease }}
        className="relative mt-16 w-full pb-20"
      >
        <HeroCollage />
      </motion.div>
    </section>
  );
}
