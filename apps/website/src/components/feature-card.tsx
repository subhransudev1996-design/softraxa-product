"use client";

import Link from "next/link";
import { motion, useReducedMotion } from "framer-motion";
import type { ReactNode } from "react";

/**
 * Glass feature/service card with a subtle hover-tilt-and-lift. Takes a
 * pre-rendered icon element (not a component) so it can be used from server
 * components without crossing the function-prop boundary. Motion collapses
 * to a static card under reduced-motion.
 */
export default function FeatureCard({
  icon,
  title,
  body,
  href,
}: {
  icon: ReactNode;
  title: string;
  body: string;
  href?: string;
}) {
  const reduced = useReducedMotion();

  const content = (
    <div className="glass group h-full rounded-2xl p-6 transition-colors hover:border-paper/15">
      <div className="inline-flex h-11 w-11 items-center justify-center rounded-xl bg-gradient-to-br from-violet/25 to-sky/20 ring-1 ring-paper/10">
        {icon}
      </div>
      <h3 className="mt-5 font-display text-lg font-semibold text-paper">{title}</h3>
      <p className="mt-2 text-sm leading-relaxed text-dim">{body}</p>
    </div>
  );

  const wrapped = reduced ? (
    content
  ) : (
    <motion.div
      whileHover={{ y: -6 }}
      transition={{ type: "spring", stiffness: 300, damping: 20 }}
      className="h-full"
    >
      {content}
    </motion.div>
  );

  return href ? (
    <Link href={href} className="block h-full">
      {wrapped}
    </Link>
  ) : (
    wrapped
  );
}
