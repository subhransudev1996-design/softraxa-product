"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, CardBody, Spinner, StatCard, Table } from "@/components/ui";
import { waLink } from "@/components/ops";
import { QuoteCalculator, webPrice } from "@/components/quote";
import { dateStr, inr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */

const isoDay = (d: Date) => d.toISOString().slice(0, 10);
const addDays = (n: number) => isoDay(new Date(Date.now() + n * 86400000));

/** 1 April of the financial year we are in. */
function fyStart() {
  const d = new Date();
  const y = d.getMonth() >= 3 ? d.getFullYear() : d.getFullYear() - 1;
  return `${y}-04-01`;
}


/** What a payment paid for: the add-on part at its price, the rest is the plan. */
function splitPayment(p: any) {
  const b = p.breakdown ?? {};
  const paid = Number(p.amount);
  if (b.addon) return { plan: 0, addons: paid };
  const addOnList = Number(b.extra_staff ?? 0) * Number(b.extra_staff_price ?? 0) + Number(b.ai_addon_price ?? 0);
  const addons = Math.min(paid, addOnList);
  return { plan: paid - addons, addons };
}

/**
 * Sales: money in, by plan and add-on, the plan mix, trials that became
 * paying shops, renewals coming up with a WhatsApp quote, and a quick
 * quote for a new shop. Prices come from the Plans page (migration 0096).
 */
export default function SalesPage() {
  const supabase = createClient();
  const [data, setData] = useState<any>(null);
  const [window_, setWindow] = useState<30 | 60>(30);

  useEffect(() => {
    (async () => {
      const [pay, subs, biz, plans, addons, settings] = await Promise.all([
        supabase.from("subscription_payments").select("id, business_id, amount, payment_date, plan_id, breakdown, receipt_no")
          .order("payment_date", { ascending: false }).limit(5000),
        supabase.from("latest_subscriptions").select("business_id, plan_id, status, expiry_date, grace_days"),
        supabase.from("businesses").select("id, name, phone, owner_name, is_active, created_at"),
        supabase.from("plans").select("*").order("sort_order"),
        supabase.from("shop_addons").select("business_id, kind, quantity, valid_until").gte("valid_until", isoDay(new Date())),
        supabase.from("platform_settings").select("website_discount_pct").eq("id", 1).maybeSingle(),
      ]);
      setData({
        payments: pay.data ?? [],
        subs: subs.data ?? [],
        businesses: new Map((biz.data ?? []).map((b: any) => [b.id, b])),
        plans: new Map((plans.data ?? []).map((p: any) => [p.id, p])),
        planList: plans.data ?? [],
        addons: addons.error ? [] : addons.data ?? [],
        discount: Number(settings.data?.website_discount_pct ?? 20),
      });
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const stats = useMemo(() => {
    if (!data) return null;
    const month = isoDay(new Date()).slice(0, 7);
    const fy = fyStart();
    const fyPays = data.payments.filter((p: any) => p.payment_date >= fy);
    const sum = (list: any[]) => list.reduce((n, p) => n + Number(p.amount), 0);
    const byPlan = new Map<string, { name: string; count: number; amount: number }>();
    let addonAmount = 0;
    for (const p of fyPays) {
      const part = splitPayment(p);
      addonAmount += part.addons;
      if (part.plan > 0) {
        const name = data.plans.get(p.plan_id)?.name ?? p.breakdown?.plan ?? "Other";
        const row = byPlan.get(name) ?? { name, count: 0, amount: 0 };
        row.count += 1;
        row.amount += part.plan;
        byPlan.set(name, row);
      }
    }
    const sales = fyPays.filter((p: any) => Number(p.breakdown?.list_total) > 0);
    const avgDiscount = sales.length
      ? sales.reduce((n: number, p: any) => n + Number(p.breakdown.discount ?? 0) / Number(p.breakdown.list_total), 0) / sales.length * 100
      : null;
    const lifetimeSales = data.payments.filter((p: any) => p.breakdown?.billing === "lifetime");

    // Plan mix: shops by their current plan.
    const today = isoDay(new Date());
    const mix = new Map<string, number>();
    let trial = 0;
    for (const s of data.subs) {
      const b = data.businesses.get(s.business_id);
      if (!b?.is_active) continue;
      if (s.status === "trial") { trial += 1; continue; }
      if (s.status !== "active" || s.expiry_date < today) continue;
      const name = data.plans.get(s.plan_id)?.name ?? "No plan";
      mix.set(name, (mix.get(name) ?? 0) + 1);
    }

    // Trials that became paying shops: signed up in the last 90 days.
    const since = addDays(-90);
    const fresh = [...data.businesses.values()].filter((b: any) => b.created_at.slice(0, 10) >= since);
    const paid = new Set(data.payments.map((p: any) => p.business_id));
    const converted = fresh.filter((b: any) => paid.has(b.id)).length;

    return {
      month: sum(data.payments.filter((p: any) => p.payment_date.slice(0, 7) === month)),
      fy: sum(fyPays),
      fyCount: fyPays.length,
      byPlan: [...byPlan.values()].sort((a, b) => b.amount - a.amount),
      addonAmount,
      avgDiscount,
      belowLowest: fyPays.filter((p: any) => p.breakdown?.below_lowest).length,
      lifetimeCount: lifetimeSales.length,
      lifetimeAmount: sum(lifetimeSales),
      mix: [...mix.entries()].sort((a, b) => b[1] - a[1]),
      trial,
      fresh: fresh.length,
      converted,
    };
  }, [data]);

  if (!data || !stats) return <Spinner />;

  // Renewals due: yearly shops whose plan ends in the window.
  const today = isoDay(new Date());
  const until = addDays(window_);
  const due = data.subs
    .filter((s: any) => s.status === "active" && s.expiry_date >= today && s.expiry_date <= until)
    .map((s: any) => {
      const plan = data.plans.get(s.plan_id);
      const b = data.businesses.get(s.business_id);
      const mine = data.addons.filter((a: any) => a.business_id === s.business_id);
      const staff = mine.filter((a: any) => a.kind === "staff").reduce((n: number, a: any) => n + Number(a.quantity), 0);
      const ai = mine.some((a: any) => a.kind === "ai");
      const list = Number(plan?.list_price ?? 0);
      const addons = staff * Number(plan?.extra_staff_price ?? 0) + (ai ? Number(plan?.ai_addon_price ?? 0) : 0);
      return {
        s, b, plan, staff, ai,
        quote: list > 0 ? webPrice(list, data.discount) + addons : null,
        list: list > 0 ? list + addons : null,
      };
    })
    .filter((r: any) => r.b?.is_active && r.plan?.billing !== "lifetime")
    .sort((a: any, b: any) => a.s.expiry_date.localeCompare(b.s.expiry_date));

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-zinc-900">Sales</h1>
        <p className="text-sm text-zinc-500">Money in, renewals coming up and quotes. Financial year from {dateStr(fyStart())}.</p>
      </div>

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="Collected this month" value={inr(stats.month)} />
        <StatCard label="This financial year" value={inr(stats.fy)} hint={`${stats.fyCount} payments`} />
        <StatCard label="Lifetime plans sold" value={stats.lifetimeCount} hint={inr(stats.lifetimeAmount)} />
        <StatCard
          label="Average discount"
          value={stats.avgDiscount == null ? "—" : `${Math.round(stats.avgDiscount)}%`}
          hint={stats.belowLowest > 0 ? `${stats.belowLowest} sale${stats.belowLowest > 1 ? "s" : ""} below your lowest` : "off list price, this year"}
        />
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <CardBody>
            <h2 className="mb-3 text-sm font-semibold text-zinc-700">This year, by plan</h2>
            <Table headers={["Plan", "Sales", "Amount"]}>
              {stats.byPlan.map((r) => (
                <tr key={r.name}>
                  <td className="px-4 py-2.5">{r.name}</td>
                  <td className="px-4 py-2.5 tabular-nums">{r.count}</td>
                  <td className="px-4 py-2.5 tabular-nums">{inr(r.amount)}</td>
                </tr>
              ))}
              <tr>
                <td className="px-4 py-2.5">Add-ons (staff logins, AI)</td>
                <td className="px-4 py-2.5" />
                <td className="px-4 py-2.5 tabular-nums">{inr(stats.addonAmount)}</td>
              </tr>
              {stats.byPlan.length === 0 && stats.addonAmount === 0 && (
                <tr><td colSpan={3} className="px-4 py-6 text-center text-zinc-500">No payments this year yet.</td></tr>
              )}
            </Table>
          </CardBody>
        </Card>

        <Card>
          <CardBody>
            <h2 className="mb-3 text-sm font-semibold text-zinc-700">Shops today</h2>
            <ul className="space-y-2 text-sm">
              {stats.mix.map(([name, n]) => (
                <li key={name} className="flex items-center gap-3">
                  <span className="w-40 shrink-0 truncate">{name}</span>
                  <span className="h-2 rounded-full bg-brand" style={{ width: `${Math.max(4, (n / Math.max(...stats.mix.map((m) => m[1]))) * 60)}%` }} />
                  <span className="tabular-nums text-zinc-600">{n}</span>
                </li>
              ))}
              <li className="flex items-center gap-3 text-zinc-500">
                <span className="w-40 shrink-0">On free trial</span>
                <span className="tabular-nums">{stats.trial}</span>
              </li>
            </ul>
            <p className="mt-4 rounded-lg bg-zinc-50 px-4 py-3 text-sm text-zinc-700">
              Last 90 days: <b>{stats.fresh}</b> new shop{stats.fresh === 1 ? "" : "s"}, <b>{stats.converted}</b> paid
              {stats.fresh > 0 ? ` (${Math.round((stats.converted / stats.fresh) * 100)}%)` : ""}.
            </p>
          </CardBody>
        </Card>
      </div>

      <Card>
        <CardBody>
          <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
            <h2 className="text-sm font-semibold text-zinc-700">Renewals due — {due.length}</h2>
            <div className="flex gap-1.5">
              {([30, 60] as const).map((d) => (
                <button key={d} onClick={() => setWindow(d)}
                  className={`rounded-full px-3 py-1 text-xs font-semibold ring-1 ring-inset ${window_ === d ? "bg-ink text-white ring-ink" : "bg-white text-zinc-600 ring-zinc-200"}`}>
                  Next {d} days
                </button>
              ))}
            </div>
          </div>
          <Table headers={["Shop", "Plan", "Ends", "Quote", ""]}>
            {due.map((r: any) => {
              const msg =
                `Namaste ${r.b?.owner_name || ""}! Your Dukania ${r.plan?.name ?? "plan"} for ${r.b?.name} ends on ${dateStr(r.s.expiry_date)}. ` +
                (r.quote ? `Renewal for one more year: ${inr(r.quote)}${r.list && r.list > r.quote ? ` (list ${inr(r.list)})` : ""}` : "Reply and we'll share the renewal amount") +
                `${r.staff > 0 ? `, with your ${r.staff} extra staff login${r.staff > 1 ? "s" : ""}` : ""}${r.ai ? " and AI" : ""}. ` +
                "Pay by UPI and send us the UTR, or call us. Thank you — Dukania";
              return (
                <tr key={r.s.business_id} className="hover:bg-zinc-50">
                  <td className="px-4 py-2.5">
                    <Link href={`/clients/${r.s.business_id}`} className="font-semibold hover:underline">{r.b?.name}</Link>
                    <span className="block text-xs text-zinc-500">{r.b?.owner_name || "—"} · {r.b?.phone || "no phone"}</span>
                  </td>
                  <td className="px-4 py-2.5">
                    {r.plan?.name ?? "—"}
                    {r.staff > 0 && <span className="block text-xs text-zinc-500">+{r.staff} staff</span>}
                    {r.ai && <Badge color="purple">AI</Badge>}
                  </td>
                  <td className="whitespace-nowrap px-4 py-2.5">{dateStr(r.s.expiry_date)}</td>
                  <td className="px-4 py-2.5 tabular-nums">{r.quote ? inr(r.quote) : <span className="text-zinc-400">old plan</span>}</td>
                  <td className="px-4 py-2.5 text-right">
                    {r.b?.phone && (
                      <a href={waLink(r.b.phone, msg)} target="_blank" rel="noreferrer">
                        <Button variant="outline">WhatsApp quote</Button>
                      </a>
                    )}
                  </td>
                </tr>
              );
            })}
            {due.length === 0 && (
              <tr><td colSpan={5} className="px-4 py-6 text-center text-zinc-500">No renewals in the next {window_} days.</td></tr>
            )}
          </Table>
        </CardBody>
      </Card>

      <QuoteCalculator plans={data.planList.filter((p: any) => p.is_active && Number(p.list_price) > 0)} discount={data.discount} />
    </div>
  );
}

/** A price for a new shop: plan + extra staff + AI, ready to send. */
