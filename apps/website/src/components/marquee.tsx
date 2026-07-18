/**
 * Seamless capability ticker. The track holds two identical copies of the
 * items and translates -50%, so the loop is invisible. Edges fade out.
 * Animation is paused under prefers-reduced-motion (see globals.css).
 */
export default function Marquee({ items }: { items: string[] }) {
  const row = (
    <ul className="flex shrink-0 items-center gap-10 pr-10 font-mono text-sm text-dim">
      {items.map((item, i) => (
        <li key={i} className="flex items-center gap-10 whitespace-nowrap">
          <span>{item}</span>
          <span className="text-violet">◆</span>
        </li>
      ))}
    </ul>
  );

  return (
    <div className="relative overflow-hidden border-y border-hairline py-5">
      <div className="marquee-track flex w-max">
        {row}
        {row}
      </div>
      <div className="pointer-events-none absolute inset-y-0 left-0 w-24 bg-gradient-to-r from-bg to-transparent" />
      <div className="pointer-events-none absolute inset-y-0 right-0 w-24 bg-gradient-to-l from-bg to-transparent" />
    </div>
  );
}
