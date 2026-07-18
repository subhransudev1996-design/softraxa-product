/**
 * Living aurora mesh — layered blurred radial blobs that slowly drift,
 * over a faint dotted grid. Purely decorative; sits behind content.
 * Drift animation is disabled under prefers-reduced-motion (see globals.css).
 */
export default function AuroraBg({
  className = "",
  intensity = "full",
}: {
  className?: string;
  intensity?: "full" | "soft";
}) {
  const opacity = intensity === "soft" ? "opacity-40" : "opacity-100";
  return (
    <div className={`pointer-events-none absolute inset-0 overflow-hidden ${className}`} aria-hidden="true">
      <div className="texture-grid absolute inset-0 opacity-60" />
      <div className={`aurora ${opacity}`}>
        <div
          className="aurora-blob drift-a h-[38rem] w-[38rem]"
          style={{ top: "-12%", left: "8%", background: "radial-gradient(circle, var(--violet), transparent 62%)" }}
        />
        <div
          className="aurora-blob drift-b h-[34rem] w-[34rem]"
          style={{ top: "6%", right: "2%", background: "radial-gradient(circle, var(--sky), transparent 60%)" }}
        />
        <div
          className="aurora-blob drift-c h-[30rem] w-[30rem]"
          style={{ bottom: "-14%", left: "34%", background: "radial-gradient(circle, var(--teal), transparent 60%)" }}
        />
      </div>
      {/* fade to base at the bottom so sections below blend in */}
      <div className="absolute inset-x-0 bottom-0 h-40 bg-gradient-to-b from-transparent to-bg" />
    </div>
  );
}
