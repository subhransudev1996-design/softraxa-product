import type { ReactNode } from "react";

/** Phone chrome. Holds a real screenshot edge-to-edge. */
export function PhoneFrame({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <div className={`w-full max-w-[264px] ${className}`}>
      <div className="rounded-[2.2rem] border border-white/10 bg-elevated p-2 shadow-2xl shadow-black/50 ring-1 ring-black/40">
        <div className="relative overflow-hidden rounded-[1.7rem] border border-hairline bg-surface">
          {children}
        </div>
      </div>
    </div>
  );
}

/** Desktop browser chrome with a title-bar strip above the screenshot. */
export function BrowserFrame({
  children,
  label = "Dukania",
  className = "",
}: {
  children: ReactNode;
  label?: string;
  className?: string;
}) {
  return (
    <div className={`w-full overflow-hidden rounded-xl border border-hairline bg-surface shadow-2xl shadow-black/50 ${className}`}>
      <div className="flex items-center gap-2 border-b border-hairline bg-paper/2 px-3 py-2.5">
        <span className="h-2.5 w-2.5 rounded-full bg-red-400/70" />
        <span className="h-2.5 w-2.5 rounded-full bg-amber/70" />
        <span className="h-2.5 w-2.5 rounded-full bg-teal/70" />
        <span className="ml-3 rounded-md bg-paper/4 px-3 py-1 font-mono text-[10px] text-dim">{label}</span>
      </div>
      <div className="p-1.5">{children}</div>
    </div>
  );
}
