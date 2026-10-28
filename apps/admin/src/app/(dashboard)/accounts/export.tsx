"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Button, Card, CardBody, Input, Label } from "@/components/ui";
import { Notice } from "@/components/ops";
import { inr } from "@/lib/format";
import { download, expenseLabel, toCsv } from "@/lib/accounts";

/* eslint-disable @typescript-eslint/no-explicit-any */

const iso = (d: Date) => d.toISOString().slice(0, 10);

/** The financial year (April–March) that [d] is in. */
function fyOf(d: Date): [string, string] {
  const y = d.getMonth() >= 3 ? d.getFullYear() : d.getFullYear() - 1;
  return [`${y}-04-01`, `${y + 1}-03-31`];
}

/** Last month, this month, the quarter so far, this financial year. */
function presets(): [string, string, string][] {
  const t = new Date();
  const m0 = new Date(t.getFullYear(), t.getMonth(), 1);
  const lastStart = new Date(t.getFullYear(), t.getMonth() - 1, 1);
  const lastEnd = new Date(t.getFullYear(), t.getMonth(), 0);
  const [fyFrom, fyTo] = fyOf(t);
  return [
    ["Last month", iso(lastStart), iso(lastEnd)],
    ["This month", iso(m0), iso(t)],
    ["This financial year", fyFrom, fyTo],
  ];
}

/**
 * Files for the CA (admin_accounts_export, migration 0103): the sales
 * register with GST split, credit notes and expenses, as CSV for Excel.
 */
export function CaExport() {
  const [from, setFrom] = useState(presets()[0][1]);
  const [to, setTo] = useState(presets()[0][2]);
  const [data, setData] = useState<any>(null);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);

  async function load() {
    setBusy(true);
    setNotice(null);
    const { data, error } = await createClient().rpc("admin_accounts_export", { p_from: from, p_to: to });
    setBusy(false);
    if (error) return setNotice({ ok: false, text: error.message });
    setData(data);
  }

  const sum = (rows: any[], k: string) => rows.reduce((s, r) => s + Number(r[k] ?? 0), 0);
  const tag = `${from}_to_${to}`;

  function sales() {
    download(`dukania-sales-${tag}.csv`, toCsv(
      ["Date", "Invoice no", "Receipt no", "Client", "Client GSTIN", "Place of supply", "Taxable", "CGST", "SGST", "IGST", "Total", "Mode", "Reference", "Plan"],
      data.sales.map((r: any) => [r.date, r.invoice_no, r.receipt_no, r.client, r.client_gstin, r.place_of_supply,
        r.taxable, r.cgst, r.sgst, r.igst, r.total, r.mode, r.reference, r.plan])));
  }
  function creditNotes() {
    download(`dukania-credit-notes-${tag}.csv`, toCsv(
      ["Date", "Credit note no", "Against invoice", "Client", "Client GSTIN", "Taxable", "CGST", "SGST", "IGST", "Total", "Mode", "Reference", "Reason"],
      data.credit_notes.map((r: any) => [r.date, r.credit_note_no, r.invoice_no, r.client, r.client_gstin,
        r.taxable, r.cgst, r.sgst, r.igst, r.total, r.mode, r.reference, r.reason])));
  }
  function expenses() {
    download(`dukania-expenses-${tag}.csv`, toCsv(
      ["Date", "Category", "Paid to", "Amount", "GST paid", "Note"],
      data.expenses.map((r: any) => [r.date, expenseLabel(r.category), r.vendor, r.amount, r.gst_paid, r.note])));
  }

  return (
    <div className="space-y-6">
      <Card>
        <CardBody className="space-y-4">
          <div className="flex flex-wrap gap-2">
            {presets().map(([label, f, t]) => (
              <button key={label} onClick={() => { setFrom(f); setTo(t); setData(null); }}
                className={`rounded-full px-3 py-1 text-xs font-semibold ring-1 ring-inset ${from === f && to === t ? "bg-ink text-white ring-ink" : "bg-white text-zinc-600 ring-zinc-200"}`}>
                {label}
              </button>
            ))}
          </div>
          <div className="flex flex-wrap items-end gap-3">
            <div>
              <Label>From</Label>
              <Input type="date" value={from} onChange={(e) => { setFrom(e.target.value); setData(null); }} />
            </div>
            <div>
              <Label>To</Label>
              <Input type="date" value={to} onChange={(e) => { setTo(e.target.value); setData(null); }} />
            </div>
            <Button onClick={load} disabled={busy || !from || !to}>{busy ? "Getting…" : "Get the figures"}</Button>
          </div>
          <Notice notice={notice} />
        </CardBody>
      </Card>

      {data && (
        <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
          <FileCard
            title="Sales register"
            lines={[
              `${data.sales.length} payments · ${inr(sum(data.sales, "total"))}`,
              `Taxable ${inr(sum(data.sales, "taxable"))} · GST ${inr(sum(data.sales, "cgst") + sum(data.sales, "sgst") + sum(data.sales, "igst"))}`,
              `${data.sales.filter((r: any) => !r.invoice_no).length} without a tax invoice`,
            ]}
            onDownload={sales}
            disabled={!data.sales.length}
          />
          <FileCard
            title="Credit notes (refunds)"
            lines={[`${data.credit_notes.length} refunds · ${inr(sum(data.credit_notes, "total"))}`]}
            onDownload={creditNotes}
            disabled={!data.credit_notes.length}
          />
          <FileCard
            title="Expenses"
            lines={[`${data.expenses.length} entries · ${inr(sum(data.expenses, "amount"))}`, `GST paid ${inr(sum(data.expenses, "gst_paid"))} (input credit)`]}
            onDownload={expenses}
            disabled={!data.expenses.length}
          />
        </div>
      )}
      <p className="text-xs text-zinc-500">
        CSV files open in Excel. Payments recorded before Dukania&apos;s GSTIN was set have no tax invoice — issue one from the
        receipt page if your CA needs it.
      </p>
    </div>
  );
}

function FileCard({ title, lines, onDownload, disabled }: { title: string; lines: string[]; onDownload: () => void; disabled: boolean }) {
  return (
    <Card>
      <CardBody className="space-y-2">
        <h3 className="font-bold text-ink">{title}</h3>
        {lines.map((l) => <p key={l} className="text-sm text-zinc-600">{l}</p>)}
        <Button variant="outline" onClick={onDownload} disabled={disabled}>Download CSV</Button>
      </CardBody>
    </Card>
  );
}
