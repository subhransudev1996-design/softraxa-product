"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Button, Card, Input, Spinner, StatCard, Table } from "@/components/ui";
import { dateStr, inr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */

const MODE_LABEL: Record<string, string> = { upi: "UPI", cash: "Cash", card: "Card", other: "Bank", credit: "Credit" };

function monthRange(month: string) {
  const [y, m] = month.split("-").map(Number);
  const from = `${month}-01`;
  const to = new Date(y, m, 0); // last day of the month
  return { from, to: `${month}-${String(to.getDate()).padStart(2, "0")}` };
}

export default function PaymentsPage() {
  const [month, setMonth] = useState(new Date().toISOString().slice(0, 7));
  const [rows, setRows] = useState<any[] | null>(null);

  useEffect(() => {
    const { from, to } = monthRange(month);
    createClient()
      .from("subscription_payments")
      .select("*, businesses(id, name), plans(name)")
      .gte("payment_date", from)
      .lte("payment_date", to)
      .order("payment_date", { ascending: false })
      .then(({ data }) => setRows(data ?? []));
  }, [month]);

  const total = (rows ?? []).reduce((s, r) => s + Number(r.amount), 0);
  const byMode = (rows ?? []).reduce<Record<string, number>>((acc, r) => {
    acc[r.payment_mode] = (acc[r.payment_mode] ?? 0) + Number(r.amount);
    return acc;
  }, {});

  function exportCsv() {
    const header = ["Date", "Receipt", "Client", "Amount", "Paid by", "Reference", "Plan", "Period from", "Period to", "Note"];
    const cell = (v: unknown) => `"${String(v ?? "").replace(/"/g, '""')}"`;
    const lines = (rows ?? []).map((r) =>
      [r.payment_date, r.receipt_no, r.businesses?.name, r.amount, MODE_LABEL[r.payment_mode] ?? r.payment_mode,
       r.reference, r.plans?.name, r.period_start, r.period_end, r.note].map(cell).join(","));
    const blob = new Blob(["﻿" + [header.map(cell).join(","), ...lines].join("\r\n")], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `SOFTRAXA-payments-${month}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-zinc-900">Subscription payments</h1>
          <p className="text-sm text-zinc-500">Recorded with Renew. Opens in Excel with Export.</p>
        </div>
        <div className="flex items-end gap-2">
          <Input type="month" value={month} onChange={(e) => e.target.value && setMonth(e.target.value)} className="w-44" />
          <Button variant="outline" onClick={exportCsv} disabled={!rows?.length}>Export</Button>
        </div>
      </div>

      {!rows ? (
        <Spinner />
      ) : (
        <>
          <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
            <StatCard label="Collected" value={inr(total)} hint={`${rows.length} payment${rows.length === 1 ? "" : "s"}`} />
            {Object.entries(byMode).map(([mode, amt]) => (
              <StatCard key={mode} label={MODE_LABEL[mode] ?? mode} value={inr(amt)} />
            ))}
          </div>
          <Card>
            <Table headers={["Date", "Client", "Amount", "Paid by", "Reference", "Period", "Receipt"]}>
              {rows.map((p) => (
                <tr key={p.id} className="hover:bg-zinc-50">
                  <td className="whitespace-nowrap px-4 py-3">{dateStr(p.payment_date)}</td>
                  <td className="px-4 py-3">
                    <Link href={`/clients/${p.businesses?.id}`} className="font-medium text-brand hover:underline">
                      {p.businesses?.name ?? "—"}
                    </Link>
                  </td>
                  <td className="px-4 py-3 font-semibold">{inr(p.amount)}</td>
                  <td className="px-4 py-3">{MODE_LABEL[p.payment_mode] ?? p.payment_mode}</td>
                  <td className="px-4 py-3 font-mono text-xs">{p.reference || "—"}</td>
                  <td className="whitespace-nowrap px-4 py-3 text-xs text-zinc-500">
                    {p.period_end ? `${dateStr(p.period_start)} → ${dateStr(p.period_end)}` : p.note || "—"}
                  </td>
                  <td className="px-4 py-3">
                    {p.receipt_no ? (
                      <Link href={`/payments/${p.id}`} className="text-xs font-medium text-brand hover:underline">{p.receipt_no}</Link>
                    ) : "—"}
                  </td>
                </tr>
              ))}
              {rows.length === 0 && (
                <tr><td colSpan={7} className="px-4 py-10 text-center text-zinc-500">No payments in this month.</td></tr>
              )}
            </Table>
          </Card>
        </>
      )}
    </div>
  );
}
