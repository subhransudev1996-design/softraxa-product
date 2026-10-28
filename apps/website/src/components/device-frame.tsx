import type { ReactNode } from "react";

/** Phone chrome. Holds a real screenshot edge-to-edge. */
export function PhoneFrame({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <div className={`w-full max-w-[264px] ${className}`}>
      <div className="shadow-float rounded-[2.2rem] bg-[#1d2a23] p-2 ring-1 ring-black/20">
        <div className="relative overflow-hidden rounded-[1.7rem] bg-white">{children}</div>
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
    <div className={`shadow-float w-full overflow-hidden rounded-xl border border-hairline bg-white ${className}`}>
      <div className="flex items-center gap-2 border-b border-hairline bg-elevated/60 px-3 py-2.5">
        <span className="h-2.5 w-2.5 rounded-full bg-red-400/70" />
        <span className="h-2.5 w-2.5 rounded-full bg-marigold/80" />
        <span className="h-2.5 w-2.5 rounded-full bg-teal/70" />
        <span className="ml-3 rounded-md bg-white px-3 py-1 font-mono text-[10px] text-dim">{label}</span>
      </div>
      <div className="p-1.5">{children}</div>
    </div>
  );
}

/** A laptop: the screen in a dark bezel above a thin silver base. */
export function LaptopFrame({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <div className={`w-full ${className}`}>
      <div className="rounded-t-2xl bg-[#1d2a23] p-2 pb-3 shadow-float">
        <div className="overflow-hidden rounded-md bg-white">{children}</div>
      </div>
      <div className="mx-auto h-3 w-[108%] -translate-x-[3.7%] rounded-b-2xl bg-gradient-to-b from-[#d9dcd8] to-[#b9bdb8]" />
    </div>
  );
}
