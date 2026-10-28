"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Button, Input, Label, Select, Spinner } from "@/components/ui";
import { Modal, Notice, waLink } from "@/components/ops";
import { useCan } from "@/components/me";
import { dateStr, inr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */

const MODE_LABEL: Record<string, string> = { upi: "UPI", cash: "Cash", card: "Card", other: "Bank transfer" };

// Indian numbering: 1,23,456 -> "One Lakh Twenty Three Thousand Four Hundred Fifty Six".
function inWords(n: number): string {
  const ones = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven",
    "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen"];
  const tens = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"];
  const two = (x: number) => (x < 20 ? ones[x] : `${tens[Math.floor(x / 10)]}${x % 10 ? ` ${ones[x % 10]}` : ""}`);
  const three = (x: number) =>
    `${x >= 100 ? `${ones[Math.floor(x / 100)]} Hundred${x % 100 ? " " : ""}` : ""}${x % 100 ? two(x % 100) : ""}`;
  let rupees = Math.floor(n);
  const paise = Math.round((n - rupees) * 100);
  if (rupees === 0 && paise === 0) return "Zero";
  const parts: string[] = [];
  const crore = Math.floor(rupees / 10000000); rupees %= 10000000;
  const lakh = Math.floor(rupees / 100000); rupees %= 100000;
  const thousand = Math.floor(rupees / 1000); rupees %= 1000;
  if (crore) parts.push(`${three(crore)} Crore`);
  if (lakh) parts.push(`${two(lakh)} Lakh`);
  if (thousand) parts.push(`${two(thousand)} Thousand`);
  if (rupees) parts.push(three(rupees));
  return `${parts.join(" ")}${paise ? ` and ${two(paise)} Paise` : ""}`;
}

export default function ReceiptPage() {
  const { id } = useParams<{ id: string }>();
  const [p, setP] = useState<any>(null);
  const [missing, setMissing] = useState(false);
  // Dukania's own details, from Settings (migration 0056).
  const [us, setUs] = useState<any>({});
  // GST invoice, refunds and credit notes (migration 0103).
  const [refunds, setRefunds] = useState<any[]>([]);
  const [refunding, setRefunding] = useState(false);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [refresh, setRefresh] = useState(0);
  const canPay = useCan("payments");

  useEffect(() => {
    createClient().from("platform_settings").select("*").maybeSingle()
      .then(({ data }) => setUs(data ?? {}));
    createClient()
      .from("subscription_payments")
      .select("*, businesses(id, name, owner_name, phone, address, gst_number, state_code), plans(name)")
      .eq("id", id)
      .maybeSingle()
      .then(({ data }) => (data ? setP(data) : setMissing(true)));
    createClient().from("subscription_refunds").select("*").eq("payment_id", id).order("refund_date")
      .then(({ data }) => setRefunds(data ?? []));
  }, [id, refresh]);

  async function issueInvoice() {
    const { data, error } = await createClient().rpc("admin_issue_invoice", { p_payment: id });
    if (error) return setNotice({ ok: false, text: error.message });
    setNotice({ ok: true, text: `Tax invoice ${data} issued.` });
    setRefresh((n) => n + 1);
  }

  if (missing) return <p className="text-zinc-500">Payment not found.</p>;
  if (!p) return <Spinner />;

  const b = p.businesses ?? {};
  const seller = us.business_name || "Dukania";
  const tax = p.invoice_no ? p.tax ?? {} : null;
  const refunded = refunds.reduce((s, r) => s + Number(r.amount), 0);
  const msg =
    `Receipt ${p.receipt_no ?? ""} — ${seller}\n` +
    `Received ${inr(p.amount)} from ${b.name} on ${dateStr(p.payment_date)} (${MODE_LABEL[p.payment_mode] ?? p.payment_mode}` +
    `${p.reference ? `, ref ${p.reference}` : ""}).\n` +
    (p.period_end ? `Dukania${p.plans?.name ? ` ${p.plans.name}` : ""} subscription: ${dateStr(p.period_start)} to ${dateStr(p.period_end)}.\n` : "") +
    "Thank you!";

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2 print:hidden">
        <Link href="/payments" className="text-sm text-zinc-500 hover:underline">← Payments</Link>
        <div className="flex gap-2">
          {canPay && !p.invoice_no && us.business_gstin && Number(p.amount) > 0 && (
            <Button variant="outline" onClick={issueInvoice}>Issue tax invoice</Button>
          )}
          {canPay && Number(p.amount) - refunded > 0 && (
            <Button variant="outline" onClick={() => setRefunding(true)}>Record a refund</Button>
          )}
          <a href={waLink(b.phone, msg)} target="_blank" rel="noreferrer"><Button variant="outline">Send on WhatsApp</Button></a>
          <Button onClick={() => window.print()}>Print</Button>
        </div>
      </div>

      <div className="print:hidden"><Notice notice={notice} /></div>

      <article className="mx-auto max-w-2xl rounded-2xl border border-zinc-200 bg-white p-8 text-sm text-ink print:max-w-none print:rounded-none print:border-0 print:p-0">
        <header className="flex items-start justify-between border-b border-zinc-200 pb-4">
          <div>
            <p className="text-xl font-extrabold">{seller}</p>
            <p className="text-xs text-zinc-500">Dukania — billing and stock software</p>
            {us.business_address && <p className="mt-1 max-w-xs text-xs text-zinc-600">{us.business_address}</p>}
            {(us.business_phone || us.business_email) && (
              <p className="text-xs text-zinc-600">{[us.business_phone, us.business_email].filter(Boolean).join(" · ")}</p>
            )}
            {us.business_gstin && <p className="text-xs text-zinc-600">GSTIN {us.business_gstin}</p>}
          </div>
          <div className="text-right">
            <p className="text-base font-bold uppercase tracking-wide">{tax ? "Tax invoice" : "Payment receipt"}</p>
            <p className="font-mono">{tax ? p.invoice_no : p.receipt_no ?? "—"}</p>
            {tax && p.receipt_no && <p className="text-xs text-zinc-500">Receipt {p.receipt_no}</p>}
            <p className="text-xs text-zinc-500">{dateStr(p.payment_date)}</p>
          </div>
        </header>

        <section className="grid gap-1 py-4">
          <p className="text-xs font-semibold uppercase tracking-wide text-zinc-500">Received from</p>
          <p className="font-semibold">{b.name}</p>
          {b.owner_name && <p>{b.owner_name}</p>}
          {b.address && <p className="text-zinc-600">{b.address}</p>}
          {b.gst_number && <p>GSTIN {b.gst_number}</p>}
          {tax && <p className="text-xs text-zinc-600">Place of supply: state code {tax.place_of_supply}</p>}
        </section>

        <table className="w-full border-y border-zinc-200">
          <tbody>
            <tr><td className="py-2 text-zinc-500">For</td><td className="py-2 text-right">
              Dukania subscription{p.plans?.name ? ` — ${p.plans.name}` : ""}
              {p.period_end ? ` (${dateStr(p.period_start)} to ${dateStr(p.period_end)})` : ""}
            </td></tr>
            <tr><td className="py-2 text-zinc-500">Paid by</td><td className="py-2 text-right">{MODE_LABEL[p.payment_mode] ?? p.payment_mode}</td></tr>
            {p.reference && <tr><td className="py-2 text-zinc-500">Reference</td><td className="py-2 text-right font-mono">{p.reference}</td></tr>}
            {tax && (
              <>
                <tr><td className="py-2 text-zinc-500">SAC</td><td className="py-2 text-right font-mono">{tax.sac}</td></tr>
                <tr><td className="py-2 text-zinc-500">Taxable value</td><td className="py-2 text-right tabular-nums">{inr(tax.taxable)}</td></tr>
                {Number(tax.igst) > 0 ? (
                  <tr><td className="py-2 text-zinc-500">IGST {Number(tax.rate)}%</td><td className="py-2 text-right tabular-nums">{inr(tax.igst)}</td></tr>
                ) : (
                  <>
                    <tr><td className="py-2 text-zinc-500">CGST {Number(tax.rate) / 2}%</td><td className="py-2 text-right tabular-nums">{inr(tax.cgst)}</td></tr>
                    <tr><td className="py-2 text-zinc-500">SGST {Number(tax.rate) / 2}%</td><td className="py-2 text-right tabular-nums">{inr(tax.sgst)}</td></tr>
                  </>
                )}
              </>
            )}
            <tr className="border-t border-zinc-200"><td className="py-3 font-bold">{tax ? "Total (GST included), received" : "Amount received"}</td><td className="py-3 text-right text-lg font-extrabold">{inr(p.amount)}</td></tr>
          </tbody>
        </table>
        <p className="pt-2 text-xs text-zinc-600">Rupees {inWords(Number(p.amount))} only</p>
        {p.note && <p className="pt-2 text-xs text-zinc-500">Note: {p.note}</p>}
        {us.receipt_footer && <p className="pt-6 text-xs text-zinc-600">{us.receipt_footer}</p>}
        {!tax && (
          <p className={`${us.receipt_footer ? "pt-2" : "pt-8"} text-xs text-zinc-400`}>This is a payment receipt, not a tax invoice.</p>
        )}
      </article>

      {refunds.length > 0 && (
        <section className="mx-auto max-w-2xl rounded-2xl border border-red-200 bg-red-50/40 p-5 text-sm print:hidden">
          <p className="mb-2 font-bold text-ink">Refunded {inr(refunded)} of {inr(p.amount)}</p>
          <ul className="space-y-1.5">
            {refunds.map((r) => (
              <li key={r.id}>
                {dateStr(r.refund_date)} · {inr(r.amount)} · {r.reason}
                {r.credit_note_no && <> · credit note <span className="font-mono">{r.credit_note_no}</span>
                  {Number(r.tax?.igst) > 0 ? ` (IGST ${inr(r.tax.igst)})` : r.tax?.cgst ? ` (CGST ${inr(r.tax.cgst)} + SGST ${inr(r.tax.sgst)})` : ""}</>}
                {r.ended_plan && " · plan ended"}
              </li>
            ))}
          </ul>
        </section>
      )}

      {refunding && (
        <RefundDialog
          paymentId={id}
          left={Number(p.amount) - refunded}
          hasInvoice={Boolean(p.invoice_no)}
          onClose={() => setRefunding(false)}
          onDone={(text) => { setRefunding(false); setNotice({ ok: true, text }); setRefresh((n) => n + 1); }}
        />
      )}
    </div>
  );
}

/** Money given back on this payment; a credit note when it had a tax invoice. */
function RefundDialog({ paymentId, left, hasInvoice, onClose, onDone }: {
  paymentId: string; left: number; hasInvoice: boolean; onClose: () => void; onDone: (text: string) => void;
}) {
  const [amount, setAmount] = useState(String(left));
  const [reason, setReason] = useState("");
  const [mode, setMode] = useState("upi");
  const [reference, setReference] = useState("");
  const [endPlan, setEndPlan] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save() {
    setBusy(true);
    const { data, error } = await createClient().rpc("admin_record_refund", {
      p_payment: paymentId,
      p: { amount: Number(amount), reason, mode, reference, end_plan: endPlan },
    });
    setBusy(false);
    if (error) return setError(error.message);
    const cn = (data as any)?.credit_note_no;
    onDone(`Refund of ${inr(Number(amount))} recorded${cn ? ` — credit note ${cn}` : ""}${endPlan ? "; the plan has ended" : ""}.`);
  }

  return (
    <Modal title="Record a refund" onClose={onClose}>
      <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); save(); }}>
        <div className="grid grid-cols-2 gap-3">
          <div>
            <Label>Amount ₹ (up to {inr(left)})</Label>
            <Input required type="number" min={1} max={left} step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} />
          </div>
          <div>
            <Label>Paid back by</Label>
            <Select value={mode} onChange={(e) => setMode(e.target.value)}>
              <option value="upi">UPI</option>
              <option value="cash">Cash</option>
              <option value="other">Bank transfer</option>
            </Select>
          </div>
        </div>
        <div>
          <Label>Reference</Label>
          <Input value={reference} onChange={(e) => setReference(e.target.value)} placeholder="UTR / transaction no." />
        </div>
        <div>
          <Label>Why</Label>
          <Input required value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Paid twice; closed the shop" />
        </div>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={endPlan} onChange={(e) => setEndPlan(e.target.checked)} /> End the shop&apos;s plan today
        </label>
        {hasInvoice && <p className="text-xs text-zinc-500">A GST credit note is made against this payment&apos;s tax invoice.</p>}
        {error && <p className="text-sm text-red-600">{error}</p>}
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button type="submit" variant="danger" disabled={busy || !reason.trim() || !(Number(amount) > 0)}>
            {busy ? "Saving…" : "Record refund"}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
