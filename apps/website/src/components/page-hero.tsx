import AuroraBg from "./aurora-bg";
import Reveal from "./reveal";

/** Compact interior-page hero with the soft aurora treatment. */
export default function PageHero({
  eyebrow,
  title,
  lead,
}: {
  eyebrow: string;
  title: string;
  lead?: string;
}) {
  return (
    <section className="relative overflow-hidden border-b border-hairline">
      <AuroraBg intensity="soft" />
      <div className="relative mx-auto max-w-7xl px-6 py-20 sm:py-24">
        <Reveal>
          <p className="font-mono text-xs uppercase tracking-[0.2em] text-sky">{eyebrow}</p>
          <h1 className="mt-4 max-w-3xl font-display text-4xl font-bold leading-[1.05] tracking-tight sm:text-5xl">
            {title}
          </h1>
          {lead && <p className="mt-5 max-w-xl text-lg text-dim">{lead}</p>}
        </Reveal>
      </div>
    </section>
  );
}
