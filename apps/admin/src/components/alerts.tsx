"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { Bell } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { dateTimeStr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */

const KIND_DOT: Record<string, string> = {
  complaint: "bg-red-500",
  unhappy: "bg-red-400",
  payment: "bg-emerald-500",
  lead: "bg-sky-500",
  signup: "bg-violet-500",
  ticket: "bg-amber-500",
  task: "bg-zinc-500",
};

/**
 * The bell (admin_alerts, migration 0103): what came in over the last 7
 * days for this person's areas; the count is what's new since they last
 * opened it. Checks every minute.
 */
export function AlertsBell({ alignRight = false }: { alignRight?: boolean }) {
  const [data, setData] = useState<{ seen_at: string; items: any[] } | null>(null);
  const [open, setOpen] = useState(false);
  const box = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const load = () =>
      createClient().rpc("admin_alerts").then(({ data, error }) => !error && data && setData(data as any));
    load();
    const id = setInterval(load, 60000);
    return () => clearInterval(id);
  }, []);

  // Close when clicking elsewhere.
  useEffect(() => {
    if (!open) return;
    const close = (e: MouseEvent) => box.current && !box.current.contains(e.target as Node) && setOpen(false);
    window.addEventListener("mousedown", close);
    return () => window.removeEventListener("mousedown", close);
  }, [open]);

  const items = data?.items ?? [];
  const fresh = items.filter((i) => data && new Date(i.at) > new Date(data.seen_at)).length;

  function toggle() {
    const next = !open;
    setOpen(next);
    if (next && fresh > 0) {
      createClient().rpc("admin_mark_alerts_seen").then(() =>
        setData((d) => (d ? { ...d, seen_at: new Date().toISOString() } : d)));
    }
  }

  return (
    <div ref={box} className="relative">
      <button onClick={toggle} aria-label={`Alerts${fresh ? ` (${fresh} new)` : ""}`}
        className="relative grid h-9 w-9 cursor-pointer place-items-center rounded-md text-zinc-500 transition-colors hover:bg-zinc-100 hover:text-ink">
        <Bell size={18} />
        {fresh > 0 && (
          <span className="absolute -right-0.5 -top-0.5 grid h-4 min-w-4 place-items-center rounded-full bg-red-500 px-1 text-[10px] font-bold text-white">
            {fresh > 9 ? "9+" : fresh}
          </span>
        )}
      </button>
      {open && (
        <div className={`absolute ${alignRight ? "right-0" : "left-0"} top-11 z-50 w-80 max-w-[calc(100vw-2rem)] overflow-hidden rounded-lg bg-white shadow-lg ring-1 ring-zinc-200`}>
          <p className="border-b border-zinc-100 px-4 py-3 text-sm font-semibold text-ink">Last 7 days</p>
          <ul className="max-h-96 divide-y divide-zinc-100 overflow-y-auto">
            {items.map((i, n) => (
              <li key={n}>
                <Link href={i.href} onClick={() => setOpen(false)} className="flex gap-3 px-4 py-2.5 hover:bg-zinc-50">
                  <span className={`mt-1.5 h-2 w-2 shrink-0 rounded-full ${KIND_DOT[i.kind] ?? "bg-zinc-400"}`} />
                  <span className="min-w-0">
                    <span className="block text-sm text-ink">{i.title}</span>
                    <span className="text-xs text-zinc-500">{dateTimeStr(i.at)}</span>
                  </span>
                </Link>
              </li>
            ))}
            {items.length === 0 && <li className="px-4 py-6 text-center text-sm text-zinc-500">Nothing new this week.</li>}
          </ul>
        </div>
      )}
    </div>
  );
}
