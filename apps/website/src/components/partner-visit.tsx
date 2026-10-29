"use client";

import { useEffect, useSyncExternalStore } from "react";
import { Ticket } from "lucide-react";
import { readPartnerCode, rememberPartner } from "@/components/campaign-capture";
import { supabase } from "@/lib/supabase-client";

/**
 * On a partner's link page: remember the code for 30 days and count the
 * visit once per browser a day (partner_click, migration 0104). Counting
 * here, not on the server, leaves out link previews and crawlers.
 */
export function PartnerVisit({ code }: { code: string }) {
  useEffect(() => {
    rememberPartner(code);
    try {
      const key = `dk_click_${code}`;
      const today = new Date().toISOString().slice(0, 10);
      if (localStorage.getItem(key) === today) return;
      localStorage.setItem(key, today);
    } catch {
      // Storage blocked: count it anyway.
    }
    supabase.rpc("partner_click", { p_code: code }).then(() => undefined);
  }, [code]);
  return null;
}

const noSubscribe = () => () => {};

/** On the download page: the code to enter after signing up, if they came through a partner. */
export function PartnerCodeNote() {
  // Read from the browser after hydration; the server renders nothing.
  const code = useSyncExternalStore(noSubscribe, readPartnerCode, () => null);
  if (!code) return null;
  return (
    <div className="mx-auto mt-10 flex max-w-5xl items-start gap-3 rounded-2xl border border-marigold/50 bg-[#fff8e6] px-5 py-4 text-sm">
      <Ticket className="mt-0.5 h-5 w-5 shrink-0 text-amber" />
      <p className="text-dim">
        Your code <b className="font-mono text-paper">{code}</b> — after you sign up, open <b className="text-paper">Plan</b> in the app and enter it on the{" "}
        <b className="text-paper">Refer a shop</b> card. Your discount is applied when you take a plan.
      </p>
    </div>
  );
}
