"use client";

import { useState, useEffect } from "react";
import Image from "next/image";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { ArrowLeft, ArrowRight } from "lucide-react";

/**
 * Testimonials carousel — our take on inflowinventory.com's testimonial block
 * (avatar + quote, prev/next, progress bar, name/role/industry tabs). Rebuilt
 * in our dark aurora language.
 *
 * IMPORTANT: these are PLACEHOLDERS, not real reviews — Softraxa has no
 * customer testimonials yet, and we don't fabricate them. Replace each entry
 * with a real quote (and, if you have them, a real photo) before going live.
 */
type Testimonial = {
  quote: string;
  name: string;
  role: string;
  tag: string;
  image: string;
};

const TESTIMONIALS: Testimonial[] = [
  {
    quote: "Softraxa built a billing system that keeps up with our daily rush. The offline support saved us when our broadband went down on Diwali week.",
    name: "Rahul Sharma",
    role: "Owner · Sharma Grocery",
    tag: "Grocery",
    image: "/images/avatars/customer-grocery.png",
  },
  {
    quote: "Our stock counts are finally correct. The barcode scanner and custom inventory dashboard make reordering simple for my staff.",
    name: "Priya Patel",
    role: "Manager · Patel Electronics",
    tag: "Electronics",
    image: "/images/avatars/customer-electronics.png",
  },
  {
    quote: "With Dukania, we track batch numbers and product expiries easily. It alerts us 30 days before items expire — saving us thousands.",
    name: "Amit Verma",
    role: "Owner · Verma Pharma",
    tag: "Pharmacy",
    image: "/images/avatars/customer-pharmacy.png",
  },
];

export default function Testimonials() {
  const [i, setI] = useState(0);
  const reduced = useReducedMotion();
  const n = TESTIMONIALS.length;
  const t = TESTIMONIALS[i];
  const go = (d: number) => setI((prev) => (prev + d + n) % n);

  // auto-advance (paused for reduced-motion)
  useEffect(() => {
    if (reduced) return;
    const id = setInterval(() => setI((prev) => (prev + 1) % n), 6000);
    return () => clearInterval(id);
  }, [n, reduced]);

  const fade = reduced ? {} : { initial: { opacity: 0, y: 10 }, animate: { opacity: 1, y: 0 }, exit: { opacity: 0, y: -10 }, transition: { duration: 0.35, ease: "easeOut" as const } };

  return (
    <div className="mx-auto max-w-5xl">
      {/* avatar + quote */}
      <div className="grid items-center gap-8 sm:grid-cols-[auto_1fr]">
        <AnimatePresence mode="wait">
          <motion.div
            key={`av-${i}`}
            {...fade}
            className="relative h-28 w-28 overflow-hidden justify-self-center rounded-full border-2 border-amber bg-elevated shadow-lg sm:justify-self-start"
          >
            <Image
              src={t.image}
              width={112}
              height={112}
              alt={t.name}
              className="h-full w-full object-cover"
            />
          </motion.div>
        </AnimatePresence>

        <AnimatePresence mode="wait">
          <motion.blockquote
            key={`q-${i}`}
            {...fade}
            className="text-center font-display text-2xl font-medium leading-snug tracking-tight sm:text-left sm:text-3xl"
          >
            <span className="text-dim">&ldquo;</span>
            {t.quote}
            <span className="text-dim">&rdquo;</span>
          </motion.blockquote>
        </AnimatePresence>
      </div>

      {/* controls + tabs */}
      <div className="mt-12 flex items-center gap-4 sm:gap-8">
        <button
          type="button"
          onClick={() => go(-1)}
          aria-label="Previous testimonial"
          className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-lg border border-hairline text-paper transition-colors hover:bg-paper/5"
        >
          <ArrowLeft className="h-4 w-4" />
        </button>

        <div className="min-w-0 flex-1">
          {/* progress bar */}
          <div className="h-0.5 w-full overflow-hidden rounded-full bg-paper/10">
            <motion.div
              className="h-full rounded-full bg-amber"
              animate={{ width: `${((i + 1) / n) * 100}%` }}
              transition={{ duration: reduced ? 0 : 0.4, ease: "easeOut" }}
            />
          </div>

          {/* name / role / tag tabs */}
          <div className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-3">
            {TESTIMONIALS.map((x, idx) => {
              const active = idx === i;
              return (
                <button
                  key={idx}
                  type="button"
                  onClick={() => setI(idx)}
                  className="text-left transition-opacity"
                >
                  <p className={`font-display font-bold ${active ? "text-paper" : "text-dim/60"}`}>{x.name}</p>
                  <p className={`text-sm ${active ? "text-dim" : "text-dim/40"}`}>{x.role}</p>
                  <span className={`mt-2 inline-flex rounded-md px-3 py-1.5 text-sm font-semibold ${active ? "bg-amber text-bg" : "bg-paper/6 text-dim"}`}>
                    {x.tag}
                  </span>
                </button>
              );
            })}
          </div>
        </div>

        <button
          type="button"
          onClick={() => go(1)}
          aria-label="Next testimonial"
          className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-lg border border-hairline text-paper transition-colors hover:bg-paper/5"
        >
          <ArrowRight className="h-4 w-4" />
        </button>
      </div>
    </div>
  );
}
