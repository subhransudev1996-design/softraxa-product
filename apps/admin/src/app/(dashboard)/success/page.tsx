"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, CardBody, Input, PageHeader, Select, Spinner, StatCard, Table } from "@/components/ui";
import { Notice, waLink } from "@/components/ops";
import { memberName, useTeam } from "@/components/me";
import { CONTACT_KINDS, LEVELS, LogContactDialog, ScoreBar, levelOf, outcomeLabel } from "@/components/success";
import { dateStr, dateTimeStr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */

const TABS = [
  ["shops", "Shops"],
  ["calls", "Follow-ups & calls"],
  ["satisfaction", "Satisfaction"],
] as const;

/**
 * Customer success (migration 0102): which shops are doing well, which
 * need a call, what was said, and how happy the shops are.
 */
export default function SuccessPage() {
  const [tab, setTab] = useState<string>("shops");
  const [shops, setShops] = useState<any[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [refresh, setRefresh] = useState(0);

  useEffect(() => {
    createClient().rpc("admin_shop_health").then(({ data, error }) => {
      if (error) setError(error.message.includes("admin_shop_health") ? "Migration 0102 isn't applied to this database yet." : error.message);
      setShops((data as any[]) ?? []);
    });
  }, [refresh]);

  return (
    <div className="space-y-6">
      <PageHeader title="Customer success" subtitle="Keep shops using Dukania — and renewing." />
      {error && <Notice notice={{ ok: false, text: error }} />}
      <div className="flex flex-wrap gap-2">
        {TABS.map(([key, label]) => (
          <button
            key={key}
            onClick={() => setTab(key)}
            aria-pressed={tab === key}
            className={`rounded-xl px-4 py-2 text-sm font-semibold transition ${tab === key ? "bg-brand text-white" : "bg-white text-zinc-600 ring-1 ring-inset ring-zinc-200 hover:bg-zinc-50"}`}
          >
            {label}
          </button>
        ))}
      </div>
      {!shops ? <Spinner /> : (
        <>
          {tab === "shops" && <Shops shops={shops} onChanged={() => setRefresh((n) => n + 1)} />}
          {tab === "calls" && <Calls shops={shops} onChanged={() => setRefresh((n) => n + 1)} />}
          {tab === "satisfaction" && <Satisfaction />}
        </>
      )}
    </div>
  );
}

function Shops({ shops, onChanged }: { shops: any[]; onChanged: () => void }) {
  const [level, setLevel] = useState<string>("risk");
  const [paying, setPaying] = useState<string>("all");
  const [q, setQ] = useState("");
  const [logging, setLogging] = useState<any>(null);

  const shown = shops.filter((s) =>
    (level === "all" || s.level === level) &&
    (paying === "all" || (paying === "paid" ? s.status === "active" : s.status === paying)) &&
    (!q || [s.name, s.owner_name, s.phone].some((v: string) => (v ?? "").toLowerCase().includes(q.toLowerCase()))));
  const count = (l: string) => shops.filter((s) => s.level === l).length;
  const avg = shops.length ? Math.round(shops.reduce((t, s) => t + s.score, 0) / shops.length) : 0;

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="Average health" value={avg} hint={`${shops.length} active shops`} />
        <StatCard label={LEVELS.healthy.label} value={count("healthy")} />
        <StatCard label={LEVELS.watch.label} value={count("watch")} />
        <StatCard label={LEVELS.risk.label} value={count("risk")} />
      </div>
      <div className="flex flex-wrap items-center gap-2">
        {[["risk", "At risk"], ["watch", "Needs attention"], ["healthy", "Healthy"], ["all", "All"]].map(([k, l]) => (
          <button key={k} onClick={() => setLevel(k)}
            className={`rounded-full px-3 py-1 text-xs font-semibold ring-1 ring-inset ${level === k ? "bg-ink text-white ring-ink" : "bg-white text-zinc-600 ring-zinc-200"}`}>
            {l}
          </button>
        ))}
        <Select value={paying} onChange={(e) => setPaying(e.target.value)} className="max-w-[10rem] py-1 text-xs" aria-label="Trial or paid">
          <option value="all">Trial or paid</option>
          <option value="paid">Paid</option>
          <option value="trial">On trial</option>
          <option value="expired">Expired</option>
        </Select>
        <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search…" className="max-w-xs py-1 text-sm" />
      </div>
      <Card>
        <Table headers={["Shop", "Health", "Why", "Getting started", "Last contact", ""]}>
          {shown.map((s) => {
            const steps = s.steps ?? [];
            return (
              <tr key={s.id} className="align-top">
                <td className="px-4 py-3">
                  <Link href={`/clients/${s.id}`} className="font-semibold text-ink hover:underline">{s.name}</Link>
                  <p className="text-xs text-zinc-500">{s.plan_name ?? "no plan"} · {s.status ?? "—"}{s.expiry_date && s.billing !== "lifetime" ? ` · ends ${dateStr(s.expiry_date)}` : ""}</p>
                </td>
                <td className="px-4 py-3"><ScoreBar score={s.score} level={s.level} /></td>
                <td className="max-w-xs px-4 py-3 text-xs text-zinc-600">
                  {s.reasons.length ? s.reasons.join(" · ") : <span className="text-emerald-700">All good</span>}
                </td>
                <td className="px-4 py-3 text-xs">
                  {steps.filter((x: any) => x.done).length}/{steps.length}
                  {steps.find((x: any) => !x.done) && <span className="block text-zinc-500">Next: {steps.find((x: any) => !x.done).label}</span>}
                </td>
                <td className="px-4 py-3 text-xs text-zinc-500">
                  {s.last_contact ? dateStr(s.last_contact) : "Never"}
                  {s.follow_up && <span className="block font-semibold text-amber-700">Follow up {dateStr(s.follow_up)}</span>}
                </td>
                <td className="px-4 py-3">
                  <div className="flex justify-end gap-2">
                    {s.phone && (
                      <a href={waLink(s.phone, `Namaste ${s.owner_name || ""}! This is Dukania. How is Dukania working for ${s.name}? Anything we can help with?`)}
                        target="_blank" rel="noreferrer"><Button variant="outline">WhatsApp</Button></a>
                    )}
                    <Button variant="outline" onClick={() => setLogging(s)}>Log</Button>
                  </div>
                </td>
              </tr>
            );
          })}
          {shown.length === 0 && <tr><td colSpan={6} className="px-4 py-10 text-center text-zinc-500">No shops here.</td></tr>}
        </Table>
      </Card>
      <p className="text-xs text-zinc-500">
        The score starts at 100 and loses points for no or few bills, few products, setup not finished, the plan
        ending or expired, open complaints, low support ratings and a low &quot;would recommend&quot;. 70+ is healthy,
        below 40 is at risk.
      </p>
      {logging && (
        <LogContactDialog shop={logging} onClose={() => setLogging(null)} onSaved={() => { setLogging(null); onChanged(); }} />
      )}
    </div>
  );
}

function Calls({ shops, onChanged }: { shops: any[]; onChanged: () => void }) {
  const [rows, setRows] = useState<any[] | null>(null);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [refresh, setRefresh] = useState(0);
  const team = useTeam();
  const today = new Date().toISOString().slice(0, 10);
  const byId = new Map(shops.map((s) => [s.id, s]));

  useEffect(() => {
    createClient().from("client_contacts").select("*, businesses(name, phone, owner_name)")
      .order("created_at", { ascending: false }).limit(300)
      .then(({ data, error }) => {
        if (error) setNotice({ ok: false, text: error.message });
        setRows(data ?? []);
      });
  }, [refresh]);

  async function closeFollowUp(id: string) {
    const { error } = await createClient().rpc("admin_close_follow_up", { p_id: id });
    if (error) return setNotice({ ok: false, text: error.message });
    setRefresh((n) => n + 1);
    onChanged();
  }

  if (!rows) return <Spinner />;
  const due = rows.filter((c) => c.follow_up_date && !c.follow_up_done)
    .sort((a, b) => a.follow_up_date.localeCompare(b.follow_up_date));

  return (
    <div className="space-y-6">
      <Notice notice={notice} />
      <Card>
        <CardBody>
          <h2 className="mb-3 text-sm font-semibold text-zinc-700">Follow-ups</h2>
          {due.length === 0 ? (
            <p className="text-sm text-zinc-500">No follow-ups waiting.</p>
          ) : (
            <ul className="divide-y divide-zinc-100">
              {due.map((c) => (
                <li key={c.id} className="flex flex-col gap-2 py-3 sm:flex-row sm:items-center sm:justify-between">
                  <div className="min-w-0">
                    <Link href={`/clients/${c.business_id}`} className="font-semibold text-ink hover:underline">{c.businesses?.name}</Link>
                    <p className={`text-xs ${c.follow_up_date < today ? "font-semibold text-red-600" : "text-zinc-500"}`}>
                      {c.follow_up_date < today ? "Overdue — " : ""}{dateStr(c.follow_up_date)} · {c.note || outcomeLabel(c.outcome)}
                    </p>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    {c.businesses?.phone && (
                      <a href={`tel:${c.businesses.phone}`}><Button variant="outline">Call</Button></a>
                    )}
                    <Button variant="ghost" onClick={() => closeFollowUp(c.id)}>Done</Button>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </CardBody>
      </Card>
      <Card>
        <CardBody>
          <h2 className="mb-3 text-sm font-semibold text-zinc-700">All calls and visits</h2>
          <ul className="divide-y divide-zinc-100 text-sm">
            {rows.map((c) => (
              <li key={c.id} className="py-2.5">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <Link href={`/clients/${c.business_id}`} className="font-semibold text-ink hover:underline">{c.businesses?.name}</Link>
                  <span className="text-xs text-zinc-400">
                    {dateTimeStr(c.created_at)}{memberName(team, c.created_by) ? ` · ${memberName(team, c.created_by)}` : ""}
                  </span>
                </div>
                <p className="text-zinc-700">
                  {CONTACT_KINDS.find(([k]) => k === c.kind)?.[1]}
                  {c.outcome && <> · <Badge color={c.outcome === "happy" ? "green" : c.outcome === "unhappy" ? "red" : "zinc"}>{outcomeLabel(c.outcome)}</Badge></>}
                  {c.note ? ` — ${c.note}` : ""}
                </p>
                {byId.get(c.business_id) && (
                  <p className="text-xs text-zinc-400">Health now {byId.get(c.business_id).score} ({levelOf(byId.get(c.business_id).level).label})</p>
                )}
              </li>
            ))}
            {rows.length === 0 && <li className="py-6 text-center text-zinc-500">Nothing logged yet. Use &quot;Log&quot; on a shop.</li>}
          </ul>
        </CardBody>
      </Card>
    </div>
  );
}

function Satisfaction() {
  const [s, setS] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    createClient().rpc("admin_satisfaction").then(({ data, error }) => {
      if (error) setError(error.message);
      setS(data ?? {});
    });
  }, []);

  if (!s) return <Spinner />;
  const answers = Number(s.answers ?? 0);
  const nps = answers ? Math.round(((Number(s.promoters) - Number(s.detractors)) / answers) * 100) : null;

  return (
    <div className="space-y-6">
      {error && <Notice notice={{ ok: false, text: error }} />}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="Would recommend (NPS)" value={nps === null ? "—" : nps} hint={`${answers} shops answered, last 12 months`} />
        <StatCard label="Promoters (9–10)" value={s.promoters ?? 0} />
        <StatCard label="Detractors (0–6)" value={s.detractors ?? 0} hint={`${s.passives ?? 0} passive (7–8)`} />
        <StatCard label="Support rating (90 days)" value={s.support_rating ? `${s.support_rating} ★` : "—"} hint={`${s.support_rated ?? 0} rated`} />
      </div>
      <Card>
        <CardBody>
          <h2 className="mb-3 text-sm font-semibold text-zinc-700">What shops said</h2>
          <p className="mb-3 text-xs text-zinc-500">
            The app asks owners &quot;How likely are you to recommend Dukania?&quot; after 14 days, then every 90 days.
            NPS = % giving 9–10 minus % giving 0–6.
          </p>
          <ul className="divide-y divide-zinc-100 text-sm">
            {(s.recent ?? []).map((r: any) => (
              <li key={r.id} className="flex gap-3 py-2.5">
                <span className={`grid h-8 w-8 shrink-0 place-items-center rounded-full text-sm font-bold text-white ${r.score >= 9 ? "bg-emerald-500" : r.score >= 7 ? "bg-amber-400" : "bg-red-500"}`}>
                  {r.score}
                </span>
                <div className="min-w-0">
                  <Link href={`/clients/${r.business_id}`} className="font-semibold text-ink hover:underline">{r.name}</Link>
                  <span className="ml-2 text-xs text-zinc-400">{dateStr(r.created_at)}</span>
                  {r.comment && <p className="text-zinc-700">&quot;{r.comment}&quot;</p>}
                </div>
              </li>
            ))}
            {(s.recent ?? []).length === 0 && <li className="py-6 text-center text-zinc-500">No answers yet.</li>}
          </ul>
        </CardBody>
      </Card>
    </div>
  );
}
