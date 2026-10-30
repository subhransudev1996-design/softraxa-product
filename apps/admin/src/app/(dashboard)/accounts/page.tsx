"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, CardBody, Input, Label, PageHeader, Select, Spinner, StatCard, Table } from "@/components/ui";
import { Notice } from "@/components/ops";
import { dateStr, inr } from "@/lib/format";
import { CaExport } from "./export";
import { EXPENSE_CATEGORIES, expenseLabel } from "@/lib/accounts";

/* eslint-disable @typescript-eslint/no-explicit-any */

const TABS = [
  ["overview", "Overview"],
  ["invoices", "Invoices & refunds"],
  ["expenses", "Expenses"],
  ["export", "For your CA"],
] as const;


const monthName = (m: string) => new Date(`${m}T00:00:00`).toLocaleDateString("en-IN", { month: "short", year: "2-digit" });

/** Accounts (migration 0103): money in and out, MRR, targets, invoices, refunds, expenses and the CA's files. */
export default function AccountsPage() {
  const [tab, setTab] = useState<string>("overview");
  return (
    <div className="space-y-6">
      <PageHeader title="Accounts" subtitle="Money in and out, recurring income, targets, GST invoices and expenses." />
      <div className="flex flex-wrap gap-2">
        {TABS.map(([key, label]) => (
          <button
            key={key}
            onClick={() => setTab(key)}
            aria-pressed={tab === key}
            className={`cursor-pointer rounded-md px-3 py-1.5 text-sm font-medium ring-1 ring-inset transition-colors ${tab === key ? "bg-brand-tint text-brand-deep ring-brand/30" : "bg-white text-zinc-600 ring-zinc-200 hover:bg-zinc-50"}`}
          >
            {label}
          </button>
        ))}
      </div>
      {tab === "overview" && <Overview />}
      {tab === "invoices" && <Invoices />}
      {tab === "expenses" && <Expenses />}
      {tab === "export" && <CaExport />}
    </div>
  );
}

function Overview() {
  const [f, setF] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);
  const [refresh, setRefresh] = useState(0);
  const [target, setTarget] = useState({ revenue: "", shops: "" });

  useEffect(() => {
    createClient().rpc("admin_finance", { p_months: 12 }).then(({ data, error }) => {
      if (error) setError(error.message.includes("admin_finance") ? "Migration 0103 isn't applied to this database yet." : error.message);
      setF(data ?? { months: [] });
    });
  }, [refresh]);

  if (!f) return <Spinner />;
  const months: any[] = f.months ?? [];
  const now = months[months.length - 1];
  const max = Math.max(1, ...months.map((m) => Math.max(Number(m.money_in), Number(m.money_out))));
  const net = (m: any) => Number(m.money_in) - Number(m.refunds) - Number(m.money_out);
  const year = months.reduce((s, m) => s + Number(m.money_in) - Number(m.refunds), 0);
  const yearOut = months.reduce((s, m) => s + Number(m.money_out), 0);

  async function saveTarget() {
    const { error } = await createClient().rpc("admin_set_target", {
      p_month: now.month, p_revenue: Number(target.revenue || 0), p_new_shops: Number(target.shops || 0),
    });
    if (error) return setError(error.message);
    setTarget({ revenue: "", shops: "" });
    setRefresh((n) => n + 1);
  }

  return (
    <div className="space-y-6">
      {error && <Notice notice={{ ok: false, text: error }} />}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="MRR (monthly recurring)" value={inr(f.mrr ?? 0)} hint={`${f.paying_shops ?? 0} paying shops`} />
        <StatCard label="ARR (yearly)" value={inr(Number(f.mrr ?? 0) * 12)} hint={`+ ${f.lifetime_shops ?? 0} lifetime shops`} />
        <StatCard label="Money in, 12 months" value={inr(year)} hint="after refunds" />
        <StatCard label="Profit, 12 months" value={inr(year - yearOut)} hint={`${inr(yearOut)} spent`} />
      </div>

      {now && (
        <Card>
          <CardBody className="space-y-3">
            <h2 className="text-sm font-semibold text-zinc-700">This month&apos;s target — {monthName(now.month)}</h2>
            {now.target_revenue ? (
              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <Progress label="Money in" value={Number(now.money_in) - Number(now.refunds)} goal={Number(now.target_revenue)} money />
                <Progress label="New paying shops" value={Number(now.new_shops)} goal={Number(now.target_new_shops)} />
              </div>
            ) : (
              <p className="text-sm text-zinc-500">No target set for this month.</p>
            )}
            <div className="flex flex-wrap items-end gap-2">
              <div>
                <Label>Money in ₹</Label>
                <Input type="number" min={0} value={target.revenue} onChange={(e) => setTarget({ ...target, revenue: e.target.value })}
                  placeholder={now.target_revenue ? String(now.target_revenue) : "e.g. 50000"} className="w-36" />
              </div>
              <div>
                <Label>New paying shops</Label>
                <Input type="number" min={0} value={target.shops} onChange={(e) => setTarget({ ...target, shops: e.target.value })}
                  placeholder={now.target_new_shops ? String(now.target_new_shops) : "e.g. 10"} className="w-36" />
              </div>
              <Button variant="outline" onClick={saveTarget} disabled={!target.revenue && !target.shops}>Set target</Button>
            </div>
          </CardBody>
        </Card>
      )}

      <Card>
        <CardBody>
          <h2 className="mb-3 text-sm font-semibold text-zinc-700">By month</h2>
          <div className="overflow-x-auto">
            <div className="flex min-w-max items-end gap-3 pb-2" style={{ height: 160 }}>
              {months.map((m) => (
                <div key={m.month} className="flex w-12 flex-col items-center gap-1">
                  <div className="flex h-32 items-end gap-1">
                    <span title={`In ${inr(m.money_in)}`} className="w-4 rounded-t bg-brand" style={{ height: `${(Number(m.money_in) / max) * 100}%` }} />
                    <span title={`Out ${inr(m.money_out)}`} className="w-4 rounded-t bg-zinc-300" style={{ height: `${(Number(m.money_out) / max) * 100}%` }} />
                  </div>
                  <span className="text-[10px] text-zinc-500">{monthName(m.month)}</span>
                </div>
              ))}
            </div>
          </div>
          <p className="mb-4 flex gap-4 text-xs text-zinc-500">
            <span className="flex items-center gap-1.5"><span className="h-2.5 w-2.5 rounded bg-brand" /> Money in</span>
            <span className="flex items-center gap-1.5"><span className="h-2.5 w-2.5 rounded bg-zinc-300" /> Spent (expenses + campaigns)</span>
          </p>
          <Table headers={["Month", "Money in", "Refunds", "Spent", "Profit", "New shops", "MRR"]}>
            {[...months].reverse().map((m) => (
              <tr key={m.month}>
                <td className="px-4 py-2.5 font-medium">{monthName(m.month)}</td>
                <td className="px-4 py-2.5 tabular-nums">{inr(m.money_in)}</td>
                <td className="px-4 py-2.5 tabular-nums text-red-600">{Number(m.refunds) ? inr(m.refunds) : "—"}</td>
                <td className="px-4 py-2.5 tabular-nums">{inr(m.money_out)}</td>
                <td className={`px-4 py-2.5 font-semibold tabular-nums ${net(m) < 0 ? "text-red-600" : "text-emerald-700"}`}>{inr(net(m))}</td>
                <td className="px-4 py-2.5 tabular-nums">{m.new_shops}{m.target_new_shops ? ` / ${m.target_new_shops}` : ""}</td>
                <td className="px-4 py-2.5 tabular-nums">{inr(m.mrr)}</td>
              </tr>
            ))}
          </Table>
          <p className="mt-2 text-xs text-zinc-500">
            MRR counts each paid year (or period) spread over its months, less refunds; lifetime sales are not recurring.
          </p>
        </CardBody>
      </Card>
    </div>
  );
}

function Progress({ label, value, goal, money = false }: { label: string; value: number; goal: number; money?: boolean }) {
  const pct = goal ? Math.min(100, Math.round((value / goal) * 100)) : 0;
  return (
    <div>
      <div className="flex justify-between text-sm">
        <span className="text-zinc-600">{label}</span>
        <span className="font-semibold tabular-nums">{money ? inr(value) : value} / {money ? inr(goal) : goal}</span>
      </div>
      <div className="mt-1 h-2.5 rounded-full bg-zinc-100">
        <div className={`h-2.5 rounded-full ${pct >= 100 ? "bg-emerald-500" : "bg-brand"}`} style={{ width: `${pct}%` }} />
      </div>
      <p className="mt-0.5 text-xs text-zinc-500">{pct}%</p>
    </div>
  );
}

function Invoices() {
  const [rows, setRows] = useState<any[] | null>(null);
  const [refunds, setRefunds] = useState<any[]>([]);
  const [gstin, setGstin] = useState("");

  useEffect(() => {
    const db = createClient();
    db.from("subscription_payments").select("id, payment_date, amount, receipt_no, invoice_no, tax, businesses(name)")
      .gt("amount", 0).order("payment_date", { ascending: false }).limit(200)
      .then(({ data }) => setRows(data ?? []));
    db.from("subscription_refunds").select("*, businesses(name)").order("refund_date", { ascending: false }).limit(100)
      .then(({ data }) => setRefunds(data ?? []));
    db.from("platform_settings").select("business_gstin").eq("id", 1).maybeSingle()
      .then(({ data }) => setGstin(data?.business_gstin ?? ""));
  }, []);

  if (!rows) return <Spinner />;
  return (
    <div className="space-y-6">
      {!gstin && (
        <p className="rounded-md bg-amber-50 px-4 py-3 text-sm text-amber-900">
          Add Dukania&apos;s GSTIN in <Link href="/settings" className="font-semibold underline">Settings</Link> and every
          payment gets a GST tax invoice by itself. Until then, payments get receipts only.
        </p>
      )}
      <Card>
        <Table headers={["Date", "Client", "Receipt", "Tax invoice", "GST", "Amount"]}>
          {rows.map((p) => {
            const gst = Number(p.tax?.cgst ?? 0) + Number(p.tax?.sgst ?? 0) + Number(p.tax?.igst ?? 0);
            return (
              <tr key={p.id} className="hover:bg-zinc-50">
                <td className="px-4 py-2.5">{dateStr(p.payment_date)}</td>
                <td className="px-4 py-2.5">{p.businesses?.name}</td>
                <td className="px-4 py-2.5"><Link href={`/payments/${p.id}`} className="font-mono text-brand hover:underline">{p.receipt_no ?? "open"}</Link></td>
                <td className="px-4 py-2.5 font-mono">{p.invoice_no ?? <span className="font-sans text-xs text-zinc-500">none</span>}</td>
                <td className="px-4 py-2.5 tabular-nums">{p.invoice_no ? inr(gst) : "—"}</td>
                <td className="px-4 py-2.5 font-semibold tabular-nums">{inr(p.amount)}</td>
              </tr>
            );
          })}
        </Table>
      </Card>
      <Card>
        <CardBody>
          <h2 className="mb-3 text-sm font-semibold text-zinc-700">Refunds</h2>
          {refunds.length === 0 ? (
            <p className="text-sm text-zinc-500">No refunds. Record one from the payment&apos;s receipt page.</p>
          ) : (
            <Table headers={["Date", "Client", "Credit note", "Why", "Amount"]}>
              {refunds.map((r) => (
                <tr key={r.id}>
                  <td className="px-4 py-2.5">{dateStr(r.refund_date)}</td>
                  <td className="px-4 py-2.5">{r.businesses?.name}</td>
                  <td className="px-4 py-2.5 font-mono">{r.credit_note_no ?? "—"}</td>
                  <td className="px-4 py-2.5 text-zinc-600">{r.reason}{r.ended_plan && <> <Badge color="red">plan ended</Badge></>}</td>
                  <td className="px-4 py-2.5 font-semibold tabular-nums text-red-600">{inr(r.amount)}</td>
                </tr>
              ))}
            </Table>
          )}
        </CardBody>
      </Card>
    </div>
  );
}

function Expenses() {
  const [rows, setRows] = useState<any[] | null>(null);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [refresh, setRefresh] = useState(0);
  const [form, setForm] = useState({ spent_on: "", category: "software", amount: "", gst_paid: "", vendor: "", note: "" });

  useEffect(() => {
    createClient().from("business_expenses").select("*").order("spent_on", { ascending: false }).limit(300)
      .then(({ data, error }) => {
        if (error) setNotice({ ok: false, text: error.message });
        setRows(data ?? []);
      });
  }, [refresh]);

  async function add(e: React.FormEvent) {
    e.preventDefault();
    const { error } = await createClient().from("business_expenses").insert({
      spent_on: form.spent_on || new Date().toISOString().slice(0, 10), category: form.category,
      amount: Number(form.amount), gst_paid: Number(form.gst_paid || 0), vendor: form.vendor.trim(), note: form.note.trim(),
    });
    if (error) return setNotice({ ok: false, text: error.message });
    setForm({ ...form, amount: "", gst_paid: "", vendor: "", note: "" });
    setRefresh((n) => n + 1);
  }

  async function remove(r: any) {
    if (!window.confirm(`Delete ${inr(r.amount)} (${r.vendor || r.category})?`)) return;
    const { error } = await createClient().from("business_expenses").delete().eq("id", r.id);
    if (error) return setNotice({ ok: false, text: error.message });
    setRefresh((n) => n + 1);
  }

  if (!rows) return <Spinner />;
  return (
    <div className="space-y-6">
      <Notice notice={notice} />
      <Card>
        <CardBody>
          <h2 className="mb-3 text-sm font-semibold text-zinc-700">Add an expense</h2>
          <form onSubmit={add} className="grid grid-cols-1 gap-3 sm:grid-cols-3">
            <div>
              <Label>Date</Label>
              <Input type="date" value={form.spent_on} onChange={(e) => setForm({ ...form, spent_on: e.target.value })} />
            </div>
            <div>
              <Label>What for</Label>
              <Select value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })}>
                {EXPENSE_CATEGORIES.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
              </Select>
            </div>
            <div>
              <Label>Paid to</Label>
              <Input value={form.vendor} onChange={(e) => setForm({ ...form, vendor: e.target.value })} placeholder="e.g. Supabase" />
            </div>
            <div>
              <Label>Amount ₹ (with GST)</Label>
              <Input required type="number" min={0} step="0.01" value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value })} />
            </div>
            <div>
              <Label>GST in it ₹ (for input credit)</Label>
              <Input type="number" min={0} step="0.01" value={form.gst_paid} onChange={(e) => setForm({ ...form, gst_paid: e.target.value })} />
            </div>
            <div>
              <Label>Note</Label>
              <Input value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} />
            </div>
            <div className="sm:col-span-3">
              <Button type="submit" disabled={!form.amount}>Add expense</Button>
              <span className="ml-3 text-xs text-zinc-500">Ad spend goes on Marketing → Campaigns; it counts here too.</span>
            </div>
          </form>
        </CardBody>
      </Card>
      <Card>
        <Table headers={["Date", "What for", "Paid to", "GST", "Amount", ""]}>
          {rows.map((r) => (
            <tr key={r.id}>
              <td className="px-4 py-2.5">{dateStr(r.spent_on)}</td>
              <td className="px-4 py-2.5">{expenseLabel(r.category)}</td>
              <td className="px-4 py-2.5">{r.vendor || "—"}{r.note && <span className="block text-xs text-zinc-500">{r.note}</span>}</td>
              <td className="px-4 py-2.5 tabular-nums">{Number(r.gst_paid) ? inr(r.gst_paid) : "—"}</td>
              <td className="px-4 py-2.5 font-semibold tabular-nums">{inr(r.amount)}</td>
              <td className="px-4 py-2.5 text-right"><Button variant="ghost" onClick={() => remove(r)}>Delete</Button></td>
            </tr>
          ))}
          {rows.length === 0 && <tr><td colSpan={6} className="px-4 py-10 text-center text-zinc-500">No expenses yet.</td></tr>}
        </Table>
      </Card>
    </div>
  );
}
