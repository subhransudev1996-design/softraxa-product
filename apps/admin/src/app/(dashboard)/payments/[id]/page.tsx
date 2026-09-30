"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Button, Spinner } from "@/components/ui";
import { waLink } from "@/components/ops";
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
  // SOFTRAXA's own details, from Settings (migration 0056).
  const [us, setUs] = useState<any>({});

  useEffect(() => {
    createClient().from("platform_settings").select("*").maybeSingle()
      .then(({ data }) => setUs(data ?? {}));
    createClient()
      .from("subscription_payments")
      .select("*, businesses(id, name, owner_name, phone, address, gst_number), plans(name)")
      .eq("id", id)
      .maybeSingle()
      .then(({ data }) => (data ? setP(data) : setMissing(true)));
  }, [id]);

  if (missing) return <p className="text-zinc-500">Payment not found.</p>;
  if (!p) return <Spinner />;

  const b = p.businesses ?? {};
  const seller = us.business_name || "SOFTRAXA";
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
          <a href={waLink(b.phone, msg)} target="_blank" rel="noreferrer"><Button variant="outline">Send on WhatsApp</Button></a>
          <Button onClick={() => window.print()}>Print</Button>
        </div>
      </div>

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
            <p className="text-base font-bold uppercase tracking-wide">Payment receipt</p>
            <p className="font-mono">{p.receipt_no ?? "—"}</p>
            <p className="text-xs text-zinc-500">{dateStr(p.payment_date)}</p>
          </div>
        </header>

        <section className="grid gap-1 py-4">
          <p className="text-xs font-semibold uppercase tracking-wide text-zinc-500">Received from</p>
          <p className="font-semibold">{b.name}</p>
          {b.owner_name && <p>{b.owner_name}</p>}
          {b.address && <p className="text-zinc-600">{b.address}</p>}
          {b.gst_number && <p>GSTIN {b.gst_number}</p>}
        </section>

        <table className="w-full border-y border-zinc-200">
          <tbody>
            <tr><td className="py-2 text-zinc-500">For</td><td className="py-2 text-right">
              Dukania subscription{p.plans?.name ? ` — ${p.plans.name}` : ""}
              {p.period_end ? ` (${dateStr(p.period_start)} to ${dateStr(p.period_end)})` : ""}
            </td></tr>
            <tr><td className="py-2 text-zinc-500">Paid by</td><td className="py-2 text-right">{MODE_LABEL[p.payment_mode] ?? p.payment_mode}</td></tr>
            {p.reference && <tr><td className="py-2 text-zinc-500">Reference</td><td className="py-2 text-right font-mono">{p.reference}</td></tr>}
            <tr className="border-t border-zinc-200"><td className="py-3 font-bold">Amount received</td><td className="py-3 text-right text-lg font-extrabold">{inr(p.amount)}</td></tr>
          </tbody>
        </table>
        <p className="pt-2 text-xs text-zinc-600">Rupees {inWords(Number(p.amount))} only</p>
        {p.note && <p className="pt-2 text-xs text-zinc-500">Note: {p.note}</p>}
        {us.receipt_footer && <p className="pt-6 text-xs text-zinc-600">{us.receipt_footer}</p>}
        <p className={`${us.receipt_footer ? "pt-2" : "pt-8"} text-xs text-zinc-400`}>This is a payment receipt, not a tax invoice.</p>
      </article>
    </div>
  );
}
