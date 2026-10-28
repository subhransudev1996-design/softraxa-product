"use client";

import { useState } from "react";
import { Card, CardBody, Select, StatCard, Table } from "@/components/ui";
import type { TeamMember } from "@/lib/team";
import { STAGES, isOpenLead, sourceLabel } from "@/lib/leads";

/* eslint-disable @typescript-eslint/no-explicit-any */

const PERIODS = [
  ["30", "Last 30 days"],
  ["90", "Last 3 months"],
  ["365", "Last 12 months"],
  ["all", "All time"],
] as const;

const pct = (a: number, b: number) => (b ? `${Math.round((a / b) * 100)}%` : "—");

type Row = { key: string; label: string; leads: number; open: number; won: number; lost: number };

function group(rows: any[], keyOf: (r: any) => string, labelOf: (k: string) => string): Row[] {
  const m = new Map<string, Row>();
  for (const r of rows) {
    const k = keyOf(r);
    const g = m.get(k) ?? { key: k, label: labelOf(k), leads: 0, open: 0, won: 0, lost: 0 };
    g.leads++;
    if (isOpenLead(r.status)) g.open++;
    if (r.status === "converted") g.won++;
    if (r.status === "lost") g.lost++;
    m.set(k, g);
  }
  return [...m.values()].sort((a, b) => b.won - a.won || b.leads - a.leads);
}

/**
 * How the selling is going, from the leads added in the period: where
 * leads come from and which ones close, each person's results, why leads
 * are lost and how long a sale takes.
 */
export function LeadReports({ rows, team }: { rows: any[]; team: TeamMember[] }) {
  const [period, setPeriod] = useState<string>("90");
  const [now] = useState(() => Date.now());
  const since = period === "all" ? "" : new Date(now - Number(period) * 86400000).toISOString();
  const inPeriod = rows.filter((r) => r.created_at >= since);
  const won = inPeriod.filter((r) => r.status === "converted");
  const lost = inPeriod.filter((r) => r.status === "lost");
  const days = won
    .filter((r) => r.converted_at)
    .map((r) => (new Date(r.converted_at).getTime() - new Date(r.created_at).getTime()) / 86400000);
  const avgDays = days.length ? Math.round(days.reduce((s, d) => s + d, 0) / days.length) : null;

  const bySource = group(inPeriod, (r) => r.source || "other", sourceLabel);
  const byCampaign = group(inPeriod.filter((r) => r.campaign), (r) => r.campaign, (k) => k);
  const byPerson = group(
    inPeriod,
    (r) => r.assigned_to ?? "",
    (k) => (k ? team.find((m) => m.id === k)?.name || team.find((m) => m.id === k)?.email || "Removed member" : "Nobody")
  );

  // Lost reasons: the reason picked from the list (before any ": more words").
  const reasons = new Map<string, number>();
  for (const r of lost) {
    const k = (r.lost_reason || "No reason given").split(":")[0].trim();
    reasons.set(k, (reasons.get(k) ?? 0) + 1);
  }
  const reasonRows = [...reasons.entries()].sort((a, b) => b[1] - a[1]);
  const maxReason = reasonRows[0]?.[1] ?? 1;

  const table = (title: string, data: Row[], first: string) => (
    <Card>
      <CardBody>
        <h2 className="mb-3 text-sm font-semibold text-zinc-700">{title}</h2>
        {data.length === 0 ? (
          <p className="text-sm text-zinc-500">Nothing in this period.</p>
        ) : (
          <Table headers={[first, "Leads", "Open", "Won", "Lost", "Win rate"]}>
            {data.map((g) => (
              <tr key={g.key}>
                <td className="px-4 py-2.5 font-medium">{g.label}</td>
                <td className="px-4 py-2.5 tabular-nums">{g.leads}</td>
                <td className="px-4 py-2.5 tabular-nums">{g.open}</td>
                <td className="px-4 py-2.5 tabular-nums text-emerald-700">{g.won}</td>
                <td className="px-4 py-2.5 tabular-nums text-red-600">{g.lost}</td>
                <td className="px-4 py-2.5 font-semibold tabular-nums">{pct(g.won, g.won + g.lost)}</td>
              </tr>
            ))}
          </Table>
        )}
      </CardBody>
    </Card>
  );

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm text-zinc-500">Leads added in the period, where they stand now. Win rate = won ÷ (won + lost).</p>
        <Select value={period} onChange={(e) => setPeriod(e.target.value)} className="max-w-[11rem]" aria-label="Period">
          {PERIODS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
        </Select>
      </div>

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="Leads added" value={inPeriod.length} />
        <StatCard label="Won" value={won.length} hint={`${pct(won.length, won.length + lost.length)} win rate`} />
        <StatCard label="Lost" value={lost.length} />
        <StatCard label="Days to win" value={avgDays === null ? "—" : avgDays} hint="on average, added → won" />
      </div>

      <Card>
        <CardBody>
          <h2 className="mb-3 text-sm font-semibold text-zinc-700">Where they are now</h2>
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-4 lg:grid-cols-7">
            {STAGES.map((s) => (
              <div key={s.key} className="rounded-xl bg-zinc-50 p-3 text-center">
                <p className="text-xl font-extrabold tabular-nums text-ink">{inPeriod.filter((r) => r.status === s.key).length}</p>
                <p className="text-xs text-zinc-500">{s.label}</p>
              </div>
            ))}
          </div>
        </CardBody>
      </Card>

      {table("By source", bySource, "Source")}
      {table("By team member", byPerson, "With")}
      {byCampaign.length > 0 && table("By campaign", byCampaign, "Campaign")}

      <Card>
        <CardBody>
          <h2 className="mb-3 text-sm font-semibold text-zinc-700">Why leads were lost</h2>
          {reasonRows.length === 0 ? (
            <p className="text-sm text-zinc-500">No lost leads in this period.</p>
          ) : (
            <ul className="space-y-2">
              {reasonRows.map(([reason, n]) => (
                <li key={reason} className="grid grid-cols-[minmax(0,12rem)_1fr_2.5rem] items-center gap-3 text-sm">
                  <span className="truncate text-zinc-700">{reason}</span>
                  <span className="h-2.5 rounded-full bg-zinc-100">
                    <span className="block h-2.5 rounded-full bg-red-400" style={{ width: `${(n / maxReason) * 100}%` }} />
                  </span>
                  <span className="text-right font-semibold tabular-nums">{n}</span>
                </li>
              ))}
            </ul>
          )}
        </CardBody>
      </Card>
    </div>
  );
}
