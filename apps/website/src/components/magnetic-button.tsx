"use client";

import Link from "next/link";
import { motion, useReducedMotion } from "framer-motion";
import type { ReactNode } from "react";

/**
 * Primary CTA with a springy press. Two variants: a bright solid button and
 * a glass ghost button. Motion collapses to a plain link under reduced-motion.
 */
export default function MagneticButton({
  href,
  children,
  variant = "primary",
  className = "",
}: {
  href: string;
  children: ReactNode;
  variant?: "primary" | "ghost";
  className?: string;
}) {
  const reduced = useReducedMotion();

  const base =
    "inline-flex min-h-11 items-center justify-center gap-2 rounded-lg px-6 py-3 text-sm font-semibold transition-colors";
  const styles =
    variant === "primary"
      ? "bg-paper text-bg hover:bg-paper/90 shadow-lg shadow-black/20"
      : "glass text-paper hover:bg-paper/5";

  const inner = <span className={`${base} ${styles} ${className}`}>{children}</span>;

  if (reduced) {
    return <Link href={href}>{inner}</Link>;
  }

  return (
    <Link href={href}>
      <motion.span
        className="inline-block"
        whileHover={{ scale: 1.03 }}
        whileTap={{ scale: 0.97 }}
        transition={{ type: "spring", stiffness: 400, damping: 17 }}
      >
        {inner}
      </motion.span>
    </Link>
  );
}
