"use client";

import { useEffect, useRef } from "react";
import { animate } from "animejs";

/**
 * Count-up stat, powered by Anime.js. Animates from 0 to `to` when it first
 * scrolls into view (eased with outExpo). Writes straight to the DOM node in
 * onUpdate to avoid a React re-render every frame. Respects reduced-motion.
 */
export default function StatCounter({
  to,
  suffix = "",
  duration = 1600,
  className = "",
}: {
  to: number;
  suffix?: string;
  duration?: number;
  className?: string;
}) {
  const ref = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    const format = (v: number) => v.toLocaleString("en-IN") + suffix;

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      el.textContent = format(to);
      return;
    }

    let started = false;
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (!entry.isIntersecting || started) return;
        started = true;
        observer.disconnect();
        const obj = { v: 0 };
        animate(obj, {
          v: to,
          duration,
          ease: "outExpo",
          onUpdate: () => {
            el.textContent = format(Math.round(obj.v));
          },
        });
      },
      { threshold: 0.5 }
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, [to, suffix, duration]);

  return (
    <span ref={ref} className={className}>
      0{suffix}
    </span>
  );
}
