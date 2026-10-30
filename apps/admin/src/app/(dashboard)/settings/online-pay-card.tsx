"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Card, CardBody, Toggle } from "@/components/ui";
import { Notice } from "@/components/ops";

/**
 * Online payments on dukania.in/pay through Razorpay (migration 0105). The
 * keys live in the razorpay functions' secrets, never here; this only
 * turns the pay page and the app's "Pay online" button on or off.
 */
export function OnlinePayCard() {
  const [on, setOn] = useState<boolean | null>(null);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);

  useEffect(() => {
    createClient().from("platform_settings").select("online_payments").eq("id", 1).maybeSingle()
      .then(({ data, error }) => !error && data && setOn(Boolean(data.online_payments)));
  }, []);

  async function change(next: boolean) {
    if (next && !window.confirm("Turn on online payments? Shops will see “Pay online” in the app and can pay on dukania.in/pay. Make sure the Razorpay keys and webhook are set up first.")) return;
    const { error } = await createClient().rpc("admin_set_online_payments", { p_on: next });
    if (error) return setNotice({ ok: false, text: error.message });
    setOn(next);
    setNotice({ ok: true, text: next ? "Online payments are on." : "Online payments are off — shops pay you by UPI as before." });
  }

  if (on === null) return null;
  return (
    <Card>
      <CardBody className="space-y-3">
        <div className="flex items-start justify-between gap-4">
          <div>
            <h2 className="text-sm font-semibold text-zinc-800">Online payments (Razorpay)</h2>
            <p className="mt-1 text-xs text-zinc-500">
              Shops pay on dukania.in/pay by UPI, card or netbanking; the plan turns on by itself and the payment
              shows under Payments with Razorpay&apos;s payment ID. The UPI QR above keeps working too.
            </p>
          </div>
          <Toggle checked={on} onChange={change} label={on ? "On" : "Off"} />
        </div>
        <Notice notice={notice} />
      </CardBody>
    </Card>
  );
}
