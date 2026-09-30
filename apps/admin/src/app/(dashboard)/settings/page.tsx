"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Button, Card, CardBody, Input, Label, Spinner } from "@/components/ui";
import { Notice } from "@/components/ops";

const UPI_PATTERN = /^[A-Za-z0-9._-]{2,255}@[A-Za-z][A-Za-z0-9]{1,63}$/;

// What expired shops see in the app to pay SOFTRAXA (migration 0053).
export default function SettingsPage() {
  const [loaded, setLoaded] = useState(false);
  const [upi, setUpi] = useState("");
  const [payee, setPayee] = useState("SOFTRAXA");
  const [whatsapp, setWhatsapp] = useState("");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);

  useEffect(() => {
    createClient()
      .from("platform_settings")
      .select("payment_upi_id, payment_payee_name, support_whatsapp")
      .maybeSingle()
      .then(({ data }) => {
        setUpi(data?.payment_upi_id ?? "");
        setPayee(data?.payment_payee_name ?? "SOFTRAXA");
        setWhatsapp(data?.support_whatsapp ?? "");
        setLoaded(true);
      });
  }, []);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (upi.trim() && !UPI_PATTERN.test(upi.trim())) {
      setNotice({ ok: false, text: "That doesn't look like a UPI ID — it should be like softraxa@okaxis" });
      return;
    }
    setBusy(true);
    const { error } = await createClient()
      .from("platform_settings")
      .update({
        payment_upi_id: upi.trim(),
        payment_payee_name: payee.trim() || "SOFTRAXA",
        support_whatsapp: whatsapp.replace(/[^\d+]/g, ""),
        updated_at: new Date().toISOString(),
      })
      .eq("id", 1);
    setBusy(false);
    setNotice(error ? { ok: false, text: error.message } : { ok: true, text: "Saved — shops see the new details the next time they open the payment screen." });
  }

  if (!loaded) return <Spinner />;

  return (
    <div className="max-w-2xl space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-zinc-900">Settings</h1>
        <p className="text-sm text-zinc-500">How shops pay you and reach you.</p>
      </div>
      <Notice notice={notice} />
      <Card>
        <CardBody>
          <form onSubmit={save} className="space-y-4">
            <div>
              <Label>Your UPI ID *</Label>
              <Input value={upi} onChange={(e) => setUpi(e.target.value)} placeholder="softraxa@okaxis" className="font-mono" />
              <p className="mt-1 text-xs text-zinc-500">
                Shown as a QR code and text on an expired shop&apos;s screen, with the amount for its plan.
              </p>
            </div>
            <div>
              <Label>Payee name</Label>
              <Input value={payee} onChange={(e) => setPayee(e.target.value)} placeholder="SOFTRAXA" />
              <p className="mt-1 text-xs text-zinc-500">The name UPI apps show when the shop scans the QR.</p>
            </div>
            <div>
              <Label>Support WhatsApp number</Label>
              <Input value={whatsapp} onChange={(e) => setWhatsapp(e.target.value)} placeholder="917437988568" />
              <p className="mt-1 text-xs text-zinc-500">
                Where shops send payment screenshots. With country code, no spaces (91 for India).
              </p>
            </div>
            <Button type="submit" disabled={busy}>{busy ? "Saving…" : "Save"}</Button>
          </form>
        </CardBody>
      </Card>
    </div>
  );
}
