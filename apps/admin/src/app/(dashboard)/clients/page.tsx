"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, Input, Spinner, Table, subscriptionBadge } from "@/components/ui";
import { businessTypeLabel } from "@/lib/business-types";
import { dateStr } from "@/lib/format";

type Sub = { status: string; expiry_date: string; grace_days: number; created_at: string; plans: { name: string } | null };
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
};

const FILTERS = [
  ["all", "All"],
  ["expiring", "Expiring in 7 days"],
  ["expired", "Expired"],
  ["trial", "Trial"],
  ["active", "Paying"],
  ["suspended", "Suspended"],
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

  useEffect(() => {
    // Arriving from the sidebar search: /clients?q=…
    const q = new URLSearchParams(window.location.search).get("q");
    if (q) Promise.resolve().then(() => setSearch(q));
    createClient()
      .from("businesses")
      .select("id, name, owner_name, business_type, phone, email, gst_number, is_active, onboarding_done, created_at, subscriptions(status, expiry_date, grace_days, created_at, plans(name))")
      .order("created_at", { ascending: false })
      .then(({ data }) => setRows((data as unknown as ClientRow[]) ?? []));
  }, []);

  const q = search.trim().toLowerCase();
  const shown = (rows ?? [])
    .map((c) => ({ c, ...stateOf(c) }))
    .filter(({ c }) =>
      !q ||
      [c.name, c.owner_name, c.phone, c.email, c.gst_number].some((v) => (v ?? "").toLowerCase().includes(q)))
    .filter(({ state, daysLeft }) =>
      filter === "all" ||
      (filter === "expiring" ? (state === "active" || state === "trial") && daysLeft !== null && daysLeft <= 7 : state === filter));

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-3">
        <h1 className="text-2xl font-bold text-zinc-900">Clients</h1>
        <Link href="/clients/new"><Button>+ New client</Button></Link>
      </div>
      <Input
        placeholder="Search name, owner, phone, email or GSTIN…"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        className="max-w-md"
      />
      <div className="flex flex-wrap gap-2">
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
                <td className="px-4 py-3">{sub?.plans?.name ?? "—"}</td>
                <td className="px-4 py-3"><Badge color={subscriptionBadge(state)}>{state}</Badge></td>
                <td className="whitespace-nowrap px-4 py-3">
                  {dateStr(sub?.expiry_date)}
                  {daysLeft !== null && daysLeft >= 0 && daysLeft <= 7 && state !== "suspended" && (
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
