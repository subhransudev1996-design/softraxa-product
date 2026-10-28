"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Badge, Card, CardBody, Input, PageHeader, Spinner } from "@/components/ui";
import { dateStr, inr } from "@/lib/format";
import { stageLabel } from "@/lib/leads";

/* eslint-disable @typescript-eslint/no-explicit-any */

/**
 * Search everything (admin_search, migration 0103): clients by name, owner,
 * phone, email, GSTIN or referral code; leads; support requests; payments
 * by receipt, invoice or UTR. Each person sees only their areas.
 */
export default function SearchPage() {
  const [q, setQ] = useState("");
  const [res, setRes] = useState<any>(null);
  const [busy, setBusy] = useState(false);
  const input = useRef<HTMLInputElement>(null);

  // ?q= from the sidebar box; Ctrl+K lands here with the box focused.
  useEffect(() => {
    const first = new URLSearchParams(window.location.search).get("q") ?? "";
    if (input.current) {
      input.current.value = first;
      input.current.focus();
    }
    if (first) Promise.resolve().then(() => setQ(first));
  }, []);

  useEffect(() => {
    if (q.trim().length < 2) return;
    const id = setTimeout(async () => {
      setBusy(true);
      const { data } = await createClient().rpc("admin_search", { p_q: q.trim() });
      setRes(data ?? {});
      setBusy(false);
      window.history.replaceState(null, "", `/search?q=${encodeURIComponent(q.trim())}`);
    }, 250);
    return () => clearTimeout(id);
  }, [q]);

  const none = res && !["clients", "leads", "tickets", "payments"].some((k) => (res[k] ?? []).length);

  return (
    <div className="space-y-6">
      <PageHeader title="Search" subtitle="Clients, leads, support requests and payments — Ctrl+K from anywhere." />
      <Input ref={input} placeholder="Name, phone, email, GSTIN, receipt or invoice no., UTR…" onChange={(e) => setQ(e.target.value)} className="text-base" />
      {busy && <Spinner />}
      {none && !busy && <p className="text-sm text-zinc-500">Nothing found for &quot;{q}&quot;.</p>}
      {res && (
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <Group title="Clients" rows={res.clients} render={(c) => (
            <Link href={`/clients/${c.id}`} className="block py-2 hover:bg-zinc-50">
              <span className="font-semibold text-ink">{c.name}</span>
              <span className="block text-xs text-zinc-500">{c.owner_name || "—"} · {c.phone || "no phone"}</span>
            </Link>
          )} />
          <Group title="Leads" rows={res.leads} render={(l) => (
            <Link href={`/leads/${l.id}`} className="flex items-center justify-between py-2 hover:bg-zinc-50">
              <span><span className="font-semibold text-ink">{l.shop_name}</span><span className="block text-xs text-zinc-500">{l.contact_name || "—"}</span></span>
              <Badge color="zinc">{stageLabel(l.status)}</Badge>
            </Link>
          )} />
          <Group title="Support requests" rows={res.tickets} render={(t) => (
            <Link href="/support" className="block py-2 hover:bg-zinc-50">
              <span className="font-semibold text-ink">{t.subject}</span>
              <span className="block text-xs text-zinc-500">{t.name} · {t.status.replace("_", " ")}</span>
            </Link>
          )} />
          <Group title="Payments" rows={res.payments} render={(p) => (
            <Link href={`/payments/${p.id}`} className="flex items-center justify-between py-2 hover:bg-zinc-50">
              <span>
                <span className="font-mono font-semibold text-ink">{p.invoice_no || p.receipt_no || "Payment"}</span>
                <span className="block text-xs text-zinc-500">{p.name} · {dateStr(p.payment_date)}</span>
              </span>
              <b className="tabular-nums">{inr(p.amount)}</b>
            </Link>
          )} />
        </div>
      )}
    </div>
  );
}

function Group({ title, rows, render }: { title: string; rows: any[] | undefined; render: (r: any) => React.ReactNode }) {
  if (!rows?.length) return null;
  return (
    <Card>
      <CardBody>
        <h2 className="mb-1 text-xs font-bold uppercase tracking-wide text-zinc-500">{title}</h2>
        <ul className="divide-y divide-zinc-100">{rows.map((r) => <li key={r.id}>{render(r)}</li>)}</ul>
      </CardBody>
    </Card>
  );
}
