import Reveal from "./reveal";

/**
 * Consistent section header: a mono eyebrow, a display title, and an
 * optional lead paragraph. `align` controls text alignment.
 */
export default function SectionHeading({
  eyebrow,
  title,
  lead,
  align = "left",
}: {
  eyebrow: string;
  title: string;
  lead?: string;
  align?: "left" | "center";
}) {
  const alignment = align === "center" ? "text-center mx-auto" : "";
  return (
    <Reveal className={`max-w-2xl ${alignment}`}>
      <p className="font-mono text-xs uppercase tracking-[0.2em] text-sky">{eyebrow}</p>
      <h2 className="mt-3 font-display text-3xl font-bold tracking-tight sm:text-4xl">{title}</h2>
      {lead && <p className="mt-4 text-lg text-dim">{lead}</p>}
    </Reveal>
  );
}
