import type { ReactNode } from "react";
import Reveal from "./reveal";

/**
 * The top of every inner page, in the homepage's look: a marigold label,
 * a big title whose second line (after "\n") is purple, a lead, optional
 * buttons, and an optional picture on the right.
 */
export default function PageHero({
  eyebrow,
  title,
  lead,
  actions,
  aside,
}: {
  eyebrow: string;
  title: string;
  lead?: string;
  actions?: ReactNode;
  aside?: ReactNode;
}) {
  const [first, ...rest] = title.split("\n");
  return (
    <section className="relative overflow-hidden border-b border-hairline">
      <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(700px_380px_at_85%_20%,rgba(124,58,237,0.12),transparent_70%),radial-gradient(520px_300px_at_5%_100%,rgba(232,163,23,0.12),transparent_70%)]" />
      <div className={`relative mx-auto grid max-w-7xl grid-cols-1 items-center gap-10 px-6 py-14 sm:py-16 ${aside ? "lg:grid-cols-[1.1fr_1fr]" : ""}`}>
        <Reveal>
          <p className="inline-flex rounded-full bg-marigold/20 px-3 py-1 text-xs font-semibold text-paper">{eyebrow}</p>
          <h1 className="mt-5 max-w-3xl font-display text-4xl font-bold leading-[1.05] tracking-tight sm:text-5xl">
            {first}
            {rest.length > 0 && (
              <>
                <br />
                <span className="text-brand">{rest.join(" ")}</span>
              </>
            )}
          </h1>
          {lead && <p className="mt-5 max-w-xl text-lg text-dim">{lead}</p>}
          {actions && <div className="mt-7 flex flex-wrap gap-3">{actions}</div>}
        </Reveal>
        {aside && <Reveal delay={0.1}>{aside}</Reveal>}
      </div>
    </section>
  );
}
