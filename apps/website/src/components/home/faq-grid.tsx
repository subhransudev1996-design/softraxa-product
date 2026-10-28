"use client";

import { useState } from "react";
import { ChevronDown } from "lucide-react";

/** FAQ in two columns of closed questions; one opens at a time. */
export default function FaqGrid({ items }: { items: { q: string; a: string }[] }) {
  const [open, setOpen] = useState<number | null>(null);
  return (
    <div className="grid items-start gap-3 md:grid-cols-2">
      {items.map((item, i) => {
        const isOpen = open === i;
        return (
          <div key={item.q} className="rounded-2xl border border-hairline bg-white shadow-card">
            <button
              type="button"
              onClick={() => setOpen(isOpen ? null : i)}
              aria-expanded={isOpen}
              className="flex min-h-14 w-full items-center justify-between gap-4 px-5 text-left text-sm font-semibold text-paper"
            >
              {item.q}
              <ChevronDown className={`h-5 w-5 shrink-0 text-dim transition-transform ${isOpen ? "rotate-180 text-brand" : ""}`} />
            </button>
            {isOpen && <p className="px-5 pb-5 text-sm leading-relaxed text-dim">{item.a}</p>}
          </div>
        );
      })}
    </div>
  );
}
