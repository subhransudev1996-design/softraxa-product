"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Button, Card, CardBody, Input, Label } from "@/components/ui";
import { Notice } from "@/components/ops";

/**
 * GST on Dukania's own sales (migration 0103): with the GSTIN above, every
 * payment gets a tax invoice numbered PREFIX/26-27/0001, GST included in
 * the price.
 */
export function GstCard() {
  const [f, setF] = useState({ gst_rate: "18", sac_code: "998314", invoice_prefix: "DK" });
  const [gstin, setGstin] = useState("");
  const [ready, setReady] = useState(false);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);

  useEffect(() => {
    createClient().from("platform_settings").select("business_gstin, gst_rate, sac_code, invoice_prefix").eq("id", 1).maybeSingle()
      .then(({ data, error }) => {
        if (error || !data) return;
        setGstin(data.business_gstin ?? "");
        setF({ gst_rate: String(data.gst_rate), sac_code: data.sac_code, invoice_prefix: data.invoice_prefix });
        setReady(true);
      });
  }, []);

  async function save() {
    const { error } = await createClient().rpc("admin_save_gst_settings", {
      p: { gst_rate: Number(f.gst_rate), sac_code: f.sac_code, invoice_prefix: f.invoice_prefix },
    });
    setNotice(error ? { ok: false, text: error.message } : { ok: true, text: "Saved." });
  }

  if (!ready) return null;
  return (
    <Card>
      <CardBody className="space-y-4">
        <div>
          <h2 className="text-base font-bold text-ink">GST invoices for your sales</h2>
          <p className="text-xs text-zinc-500">
            {gstin
              ? `With your GSTIN (${gstin}), every payment gets a tax invoice by itself. Prices you charge include GST.`
              : "Add your GSTIN above (On your receipts) and every payment gets a tax invoice by itself."}
          </p>
        </div>
        <Notice notice={notice} />
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <div>
            <Label>GST rate %</Label>
            <Input type="number" min={0} max={28} value={f.gst_rate} onChange={(e) => setF({ ...f, gst_rate: e.target.value })} />
          </div>
          <div>
            <Label>SAC code</Label>
            <Input value={f.sac_code} onChange={(e) => setF({ ...f, sac_code: e.target.value })} />
          </div>
          <div>
            <Label>Invoice prefix</Label>
            <Input value={f.invoice_prefix} maxLength={8} onChange={(e) => setF({ ...f, invoice_prefix: e.target.value.toUpperCase() })} />
            <p className="mt-1 text-xs text-zinc-500">Invoices: {f.invoice_prefix || "DK"}/26-27/0001</p>
          </div>
        </div>
        <Button variant="outline" onClick={save}>Save GST settings</Button>
      </CardBody>
    </Card>
  );
}
