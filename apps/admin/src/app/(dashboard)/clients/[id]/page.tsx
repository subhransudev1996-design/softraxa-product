"use client";

import { useCallback, useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import {
  Badge, Button, Card, CardBody, Input, Label, Select, Spinner, Toggle,
  subscriptionBadge,
} from "@/components/ui";
import { dateStr, inr } from "@/lib/format";

const FEATURES: [string, string][] = [
  ["gst_billing", "GST billing"],
  ["barcode_scanning", "Barcode scanning"],
  ["excel_import", "Excel import"],
  ["reports", "Reports"],
  ["pdf_invoice", "PDF invoice"],
  ["thermal_print", "Thermal print"],
  ["a4_print", "A4 print"],
  ["offline_billing", "Offline billing"],
  ["expense_module", "Expense module"],
];

/* eslint-disable @typescript-eslint/no-explicit-any */
export default function ClientDetailPage() {
  const { id } = useParams<{ id: string }>();
  const supabase = createClient();

  const [business, setBusiness] = useState<any>(null);
  const [subscription, setSubscription] = useState<any>(null);
  const [flags, setFlags] = useState<any>(null);
  const [plans, setPlans] = useState<any[]>([]);
  const [payments, setPayments] = useState<any[]>([]);
  const [usage, setUsage] = useState<{ products: number; invoices: number } | null>(null);
  const [msg, setMsg] = useState<string | null>(null);

  const load = useCallback(async () => {
    const [biz, sub, ff, pl, pay] = await Promise.all([
      supabase.from("businesses").select("*").eq("id", id).single(),
      supabase.from("subscriptions").select("*, plans(name)").eq("business_id", id)
        .order("created_at", { ascending: false }).limit(1).maybeSingle(),
      supabase.from("feature_flags").select("*").eq("business_id", id).maybeSingle(),
      supabase.from("plans").select("*").eq("is_active", true).order("name"),
      supabase.from("subscription_payments").select("*").eq("business_id", id)
        .order("payment_date", { ascending: false }).limit(20),
    ]);
    setBusiness(biz.data);
    setSubscription(sub.data);
    setFlags(ff.data);
    setPlans(pl.data ?? []);
    setPayments(pay.data ?? []);

    const [prodCount, invCount] = await Promise.all([
      supabase.from("products").select("id", { count: "exact", head: true }).eq("business_id", id),
      supabase.from("invoices").select("id", { count: "exact", head: true }).eq("business_id", id),
    ]);
    setUsage({ products: prodCount.count ?? 0, invoices: invCount.count ?? 0 });
  }, [id]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    load();
  }, [load]);

  function flash(text: string) {
    setMsg(text);
    setTimeout(() => setMsg(null), 2500);
  }

  async function toggleActive() {
    await supabase.from("businesses").update({ is_active: !business.is_active }).eq("id", id);
    await load();
    flash(business.is_active ? "Client suspended" : "Client activated");
  }

  async function saveSubscription(patch: Record<string, unknown>) {
    if (subscription) {
      await supabase.from("subscriptions").update(patch).eq("id", subscription.id);
    } else {
      await supabase.from("subscriptions").insert({
        business_id: id,
        expiry_date: new Date(Date.now() + 30 * 86400000).toISOString().slice(0, 10),
        ...patch,
      });
    }
    await load();
    flash("Subscription updated");
  }

  async function toggleFlag(key: string, value: boolean) {
    await supabase.from("feature_flags")
      .upsert({ business_id: id, [key]: value });
    setFlags((f: any) => ({ ...f, [key]: value }));
  }

  async function addPayment(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    const amount = Number(fd.get("amount"));
    if (!amount) return;
    await supabase.from("subscription_payments").insert({
      business_id: id,
      subscription_id: subscription?.id ?? null,
      amount,
      payment_date: (fd.get("date") as string) || new Date().toISOString().slice(0, 10),
      payment_mode: (fd.get("mode") as string) || "cash",
      note: (fd.get("note") as string) || "",
    });
    (e.target as HTMLFormElement).reset();
    await load();
    flash("Payment recorded");
  }

  if (!business) return <Spinner />;

  return (
    <div className="max-w-4xl space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-zinc-900">{business.name}</h1>
          <p className="text-sm text-zinc-500">
            {business.owner_name} • {business.phone} • <span className="capitalize">{business.business_type}</span>
          </p>
        </div>
        <div className="flex items-center gap-3">
          {msg && <span className="text-sm font-medium text-green-700">{msg}</span>}
          <Button variant={business.is_active ? "danger" : "primary"} onClick={toggleActive}>
            {business.is_active ? "Suspend client" : "Activate client"}
          </Button>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-6">
        {/* business + usage */}
        <Card>
          <CardBody>
            <h2 className="mb-3 text-sm font-semibold text-zinc-700">Business details</h2>
            <dl className="space-y-2 text-sm">
              <div className="flex justify-between"><dt className="text-zinc-500">Email</dt><dd>{business.email || "—"}</dd></div>
              <div className="flex justify-between"><dt className="text-zinc-500">Address</dt><dd className="text-right">{business.address || "—"}</dd></div>
              <div className="flex justify-between"><dt className="text-zinc-500">GSTIN</dt><dd>{business.gst_number || "—"}</dd></div>
              <div className="flex justify-between"><dt className="text-zinc-500">Invoice prefix</dt><dd>{business.invoice_prefix}</dd></div>
              <div className="flex justify-between"><dt className="text-zinc-500">Joined</dt><dd>{dateStr(business.created_at)}</dd></div>
              <div className="flex justify-between"><dt className="text-zinc-500">Products</dt><dd>{usage?.products ?? "…"}</dd></div>
              <div className="flex justify-between"><dt className="text-zinc-500">Invoices (all time)</dt><dd>{usage?.invoices ?? "…"}</dd></div>
            </dl>
          </CardBody>
        </Card>

        {/* subscription */}
        <Card>
          <CardBody>
            <div className="mb-3 flex items-center justify-between">
              <h2 className="text-sm font-semibold text-zinc-700">Subscription</h2>
              <Badge color={subscriptionBadge(subscription?.status)}>
                {subscription?.status ?? "none"}
              </Badge>
            </div>
            <div className="space-y-3">
              <div>
                <Label>Plan</Label>
                <Select
                  value={subscription?.plan_id ?? ""}
                  onChange={(e) => saveSubscription({ plan_id: e.target.value || null })}
                >
                  <option value="">No plan</option>
                  {plans.map((p) => (
                    <option key={p.id} value={p.id}>{p.name}</option>
                  ))}
                </Select>
              </div>
              <div>
                <Label>Status</Label>
                <Select
                  value={subscription?.status ?? "trial"}
                  onChange={(e) => saveSubscription({ status: e.target.value })}
                >
                  <option value="trial">Trial</option>
                  <option value="active">Active (paid)</option>
                  <option value="expired">Expired</option>
                  <option value="suspended">Suspended</option>
                </Select>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <Label>Expiry date</Label>
                  <Input
                    type="date"
                    value={subscription?.expiry_date ?? ""}
                    onChange={(e) => saveSubscription({ expiry_date: e.target.value })}
                  />
                </div>
                <div>
                  <Label>Grace days</Label>
                  <Input
                    type="number"
                    min={0}
                    defaultValue={subscription?.grace_days ?? 0}
                    onBlur={(e) => saveSubscription({ grace_days: Number(e.target.value) || 0 })}
                  />
                </div>
              </div>
              <div className="flex gap-2 pt-1">
                <Button variant="outline" onClick={() => {
                  const base = subscription?.expiry_date
                    ? new Date(subscription.expiry_date) : new Date();
                  base.setMonth(base.getMonth() + 1);
                  saveSubscription({ expiry_date: base.toISOString().slice(0, 10), status: "active" });
                }}>
                  +1 month
                </Button>
                <Button variant="outline" onClick={() => {
                  const base = subscription?.expiry_date
                    ? new Date(subscription.expiry_date) : new Date();
                  base.setFullYear(base.getFullYear() + 1);
                  saveSubscription({ expiry_date: base.toISOString().slice(0, 10), status: "active" });
                }}>
                  +1 year
                </Button>
              </div>
            </div>
          </CardBody>
        </Card>

        {/* feature flags */}
        <Card>
          <CardBody>
            <h2 className="mb-2 text-sm font-semibold text-zinc-700">Feature access</h2>
            {FEATURES.map(([key, label]) => (
              <Toggle
                key={key}
                label={label}
                checked={flags?.[key] ?? true}
                onChange={(v) => toggleFlag(key, v)}
              />
            ))}
          </CardBody>
        </Card>

        {/* payments */}
        <Card>
          <CardBody>
            <h2 className="mb-3 text-sm font-semibold text-zinc-700">Payment records</h2>
            <form onSubmit={addPayment} className="mb-4 space-y-2">
              <div className="grid grid-cols-2 gap-2">
                <Input name="amount" type="number" step="0.01" placeholder="Amount ₹" required />
                <Input name="date" type="date" />
              </div>
              <div className="grid grid-cols-2 gap-2">
                <Select name="mode" defaultValue="cash">
                  <option value="cash">Cash</option>
                  <option value="upi">UPI</option>
                  <option value="card">Card</option>
                  <option value="other">Bank/Other</option>
                </Select>
                <Input name="note" placeholder="Note" />
              </div>
              <Button type="submit" className="w-full justify-center">Record payment</Button>
            </form>
            <ul className="space-y-2 text-sm">
              {payments.map((p) => (
                <li key={p.id} className="flex justify-between border-b border-zinc-100 pb-2">
                  <span>{dateStr(p.payment_date)} • {p.payment_mode}{p.note ? ` • ${p.note}` : ""}</span>
                  <span className="font-semibold">{inr(p.amount)}</span>
                </li>
              ))}
              {payments.length === 0 && <li className="text-zinc-500">No payments recorded.</li>}
            </ul>
          </CardBody>
        </Card>
      </div>
    </div>
  );
}
