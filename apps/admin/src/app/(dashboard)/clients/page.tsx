"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, Input, Select, Spinner, Table, subscriptionBadge } from "@/components/ui";
import { businessTypeLabel } from "@/lib/business-types";
import { dateStr } from "@/lib/format";

type Sub = {
  status: string; expiry_date: string; grace_days: number; created_at: string; plan_id: string | null;
  plans: { name: string; billing?: string } | null;
};
type ClientRow = {
  id: string;
  name: string;
  owner_name: string;
  business_type: string;
  phone: string;
  email: string;
  gst_number: string;
  is_active: boolean;
  onboarding_done: boolean;
  created_at: string;
  subscriptions: Sub[];
  feature_flags: { ai_assistant?: boolean } | { ai_assistant?: boolean }[] | null;
};

const aiOn = (c: ClientRow) =>
  Boolean((Array.isArray(c.feature_flags) ? c.feature_flags[0] : c.feature_flags)?.ai_assistant);

const FILTERS = [
  ["all", "All"],
  ["expiring", "Expiring in 7 days"],
  ["expiring30", "Expiring in 30 days"],
  ["expired", "Expired"],
  ["trial", "Trial"],
  ["active", "Paying"],
  ["suspended", "Suspended"],
  ["lifetime", "Lifetime"],
  ["ai", "AI on"],
] as const;

/** The shop's state as the app sees it: suspended, expired (past expiry + grace), else the subscription status. */
function stateOf(c: ClientRow): { state: string; sub: Sub | undefined; daysLeft: number | null } {
  const sub = [...(c.subscriptions ?? [])].sort((a, b) => b.created_at.localeCompare(a.created_at))[0];
  if (!c.is_active || sub?.status === "suspended") return { state: "suspended", sub, daysLeft: null };
  if (!sub) return { state: "none", sub, daysLeft: null };
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const daysLeft = Math.round((new Date(`${sub.expiry_date}T00:00:00`).getTime() - today.getTime()) / 86400000);
  if (sub.status === "expired" || daysLeft + (sub.grace_days ?? 0) < 0) return { state: "expired", sub, daysLeft };
  return { state: sub.status, sub, daysLeft };
}

export default function ClientsPage() {
  const [rows, setRows] = useState<ClientRow[] | null>(null);
  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState<string>("all");
  const [planFilter, setPlanFilter] = useState("");

  useEffect(() => {
    // Arriving from the sidebar search: /clients?q=…
    const q = new URLSearchParams(window.location.search).get("q");
    if (q) Promise.resolve().then(() => setSearch(q));
    createClient()
      .from("businesses")
      .select("id, name, owner_name, business_type, phone, email, gst_number, is_active, onboarding_done, created_at, subscriptions(status, expiry_date, grace_days, created_at, plan_id, plans(name, billing)), feature_flags(ai_assistant)")
      .order("created_at", { ascending: false })
      .then(({ data }) => setRows((data as unknown as ClientRow[]) ?? []));
  }, []);

  const q = search.trim().toLowerCase();
  const shown = (rows ?? [])
    .map((c) => ({ c, ...stateOf(c) }))
    .filter(({ c }) =>
      !q ||
      [c.name, c.owner_name, c.phone, c.email, c.gst_number].some((v) => (v ?? "").toLowerCase().includes(q)))
    .filter(({ c, state, sub, daysLeft }) => {
      const live = state === "active" || state === "trial";
      const lifetime = sub?.plans?.billing === "lifetime";
      if (planFilter && sub?.plan_id !== planFilter) return false;
      switch (filter) {
        case "all": return true;
        case "expiring": return live && !lifetime && daysLeft !== null && daysLeft <= 7;
        case "expiring30": return live && !lifetime && daysLeft !== null && daysLeft <= 30;
        case "lifetime": return lifetime;
        case "ai": return aiOn(c);
        default: return state === filter;
      }
    });

  // The plans clients are on, for the plan picker.
  const planNames = new Map<string, string>();
  for (const c of rows ?? []) {
    const sub = stateOf(c).sub;
    if (sub?.plan_id && sub.plans?.name) planNames.set(sub.plan_id, sub.plans.name);
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-3">
        <h1 className="text-2xl font-bold text-zinc-900">Clients{rows ? <span className="ml-2 text-base font-medium text-zinc-500">{shown.length}</span> : null}</h1>
        <Link href="/clients/new"><Button>+ New client</Button></Link>
      </div>
      <Input
        placeholder="Search name, owner, phone, email or GSTIN…"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        className="max-w-md"
      />
      <div className="flex flex-wrap items-center gap-2">
        <div className="w-44"><Select value={planFilter} onChange={(e) => setPlanFilter(e.target.value)}>
          <option value="">All plans</option>
          {[...planNames].map(([pid, name]) => <option key={pid} value={pid}>{name}</option>)}
        </Select></div>
        {FILTERS.map(([key, label]) => (
          <button
            key={key}
            onClick={() => setFilter(key)}
            aria-pressed={filter === key}
            className={`rounded-full px-3 py-1 text-xs font-semibold ring-1 ring-inset ${filter === key ? "bg-ink text-white ring-ink" : "bg-white text-zinc-600 ring-zinc-200"}`}
          >
            {label}
          </button>
        ))}
      </div>
      {!rows ? (
        <Spinner />
      ) : (
        <Card>
          <Table headers={["Business", "Phone", "Plan", "Status", "Expires", ""]}>
            {shown.map(({ c, state, sub, daysLeft }) => (
              <tr key={c.id} className="hover:bg-zinc-50">
                <td className="px-4 py-3">
                  <Link href={`/clients/${c.id}`} className="font-semibold text-zinc-900 hover:underline">{c.name}</Link>
                  <p className="text-xs text-zinc-500">
                    {c.owner_name || "—"} · {businessTypeLabel(c.business_type)}
                    {c.onboarding_done === false && <span className="text-orange-700"> · setup not finished</span>}
                  </p>
                </td>
                <td className="whitespace-nowrap px-4 py-3">{c.phone || "—"}</td>
                <td className="px-4 py-3">
                  {sub?.plans?.name ?? "—"}
                  {aiOn(c) && <span className="ml-1.5 text-xs font-semibold text-violet-700">AI</span>}
                </td>
                <td className="px-4 py-3"><Badge color={subscriptionBadge(state)}>{state}</Badge></td>
                <td className="whitespace-nowrap px-4 py-3">
                  {sub?.plans?.billing === "lifetime" ? "Lifetime" : dateStr(sub?.expiry_date)}
                  {sub?.plans?.billing !== "lifetime" && daysLeft !== null && daysLeft >= 0 && daysLeft <= 7 && state !== "suspended" && (
                    <span className="block text-xs font-semibold text-orange-700">{daysLeft === 0 ? "today" : `in ${daysLeft} days`}</span>
                  )}
                </td>
                <td className="px-4 py-3 text-right">
                  <Link href={`/clients/${c.id}`} className="text-sm font-medium text-brand hover:underline">Open</Link>
                </td>
              </tr>
            ))}
            {shown.length === 0 && (
              <tr><td colSpan={6} className="px-4 py-10 text-center text-zinc-500">{rows.length === 0 ? "No clients yet." : "No clients match."}</td></tr>
            )}
          </Table>
        </Card>
      )}
    </div>
  );
}
