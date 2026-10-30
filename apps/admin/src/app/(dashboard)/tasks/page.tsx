"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, CardBody, Input, Label, PageHeader, Select, Spinner } from "@/components/ui";
import { Notice } from "@/components/ops";
import { memberName, useMe, useTeam } from "@/components/me";
import { dateStr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */

const iso = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

const KIND_STYLE: Record<string, { label: string; dot: string }> = {
  task: { label: "Task", dot: "bg-brand" },
  lead: { label: "Lead follow-up", dot: "bg-sky-500" },
  call: { label: "Call a shop", dot: "bg-amber-500" },
  renewal: { label: "Renewal / trial end", dot: "bg-red-500" },
};

/** Tasks for the team and a calendar of everything due (migration 0103). */
export default function TasksPage() {
  const [tab, setTab] = useState<"tasks" | "calendar">("tasks");
  return (
    <div className="space-y-6">
      <PageHeader title="Tasks & calendar" subtitle="What to do, who does it, and when." />
      <div className="flex flex-wrap gap-2">
        {([["tasks", "Tasks"], ["calendar", "Calendar"]] as const).map(([key, label]) => (
          <button key={key} onClick={() => setTab(key)} aria-pressed={tab === key}
            className={`cursor-pointer rounded-md px-3 py-1.5 text-sm font-medium ring-1 ring-inset transition-colors ${tab === key ? "bg-brand-tint text-brand-deep ring-brand/30" : "bg-white text-zinc-600 ring-zinc-200 hover:bg-zinc-50"}`}>
            {label}
          </button>
        ))}
      </div>
      {tab === "tasks" ? <Tasks /> : <Calendar />}
    </div>
  );
}

function Tasks() {
  const me = useMe();
  const team = useTeam();
  const [rows, setRows] = useState<any[] | null>(null);
  const [who, setWho] = useState("mine");
  const [showDone, setShowDone] = useState(false);
  const [form, setForm] = useState({ title: "", due_date: "", assigned_to: "", notes: "" });
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [refresh, setRefresh] = useState(0);
  const today = iso(new Date());

  useEffect(() => {
    createClient().from("admin_tasks").select("*, businesses(id, name), leads(id, shop_name)")
      .order("done").order("due_date", { ascending: true, nullsFirst: false }).limit(300)
      .then(({ data, error }) => {
        if (error) setNotice({ ok: false, text: error.message.includes("admin_tasks") ? "Migration 0103 isn't applied to this database yet." : error.message });
        setRows(data ?? []);
      });
  }, [refresh]);

  async function add(e: React.FormEvent) {
    e.preventDefault();
    const { error } = await createClient().from("admin_tasks").insert({
      title: form.title.trim(), notes: form.notes.trim(), due_date: form.due_date || null,
      assigned_to: form.assigned_to || me?.id || null,
    });
    if (error) return setNotice({ ok: false, text: error.message });
    setForm({ title: "", due_date: "", assigned_to: "", notes: "" });
    setRefresh((n) => n + 1);
  }

  async function toggle(t: any) {
    setRows((rs) => (rs ?? []).map((r) => (r.id === t.id ? { ...r, done: !t.done } : r)));
    const { error } = await createClient().from("admin_tasks").update({ done: !t.done }).eq("id", t.id);
    if (error) setNotice({ ok: false, text: error.message });
    setRefresh((n) => n + 1);
  }

  async function remove(t: any) {
    if (!window.confirm(`Delete "${t.title}"?`)) return;
    await createClient().from("admin_tasks").delete().eq("id", t.id);
    setRefresh((n) => n + 1);
  }

  if (!rows) return <Spinner />;
  const shown = rows.filter((t) =>
    (showDone || !t.done) &&
    (who === "all" || (who === "mine" ? t.assigned_to === me?.id : t.assigned_to === who)));
  const groups: [string, any[]][] = [
    ["Overdue", shown.filter((t) => !t.done && t.due_date && t.due_date < today)],
    ["Today", shown.filter((t) => !t.done && t.due_date === today)],
    ["Coming up", shown.filter((t) => !t.done && t.due_date && t.due_date > today)],
    ["No date", shown.filter((t) => !t.done && !t.due_date)],
    ["Done", shown.filter((t) => t.done)],
  ];

  return (
    <div className="space-y-6">
      <Notice notice={notice} />
      <Card>
        <CardBody>
          <form onSubmit={add} className="grid grid-cols-1 gap-3 sm:grid-cols-4">
            <div className="sm:col-span-2">
              <Label>New task</Label>
              <Input required value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} placeholder="e.g. Visit Sharma Stores for training" />
            </div>
            <div>
              <Label>Due</Label>
              <Input type="date" value={form.due_date} onChange={(e) => setForm({ ...form, due_date: e.target.value })} />
            </div>
            <div>
              <Label>For</Label>
              <Select value={form.assigned_to} onChange={(e) => setForm({ ...form, assigned_to: e.target.value })}>
                <option value="">Me</option>
                {team.filter((m) => m.active && m.id !== me?.id).map((m) => <option key={m.id} value={m.id}>{m.name || m.email}</option>)}
              </Select>
            </div>
            <div className="sm:col-span-3">
              <Input value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} placeholder="Notes (optional)" />
            </div>
            <Button type="submit" disabled={!form.title.trim()}>Add task</Button>
          </form>
        </CardBody>
      </Card>

      <div className="flex flex-wrap items-center gap-3">
        <Select value={who} onChange={(e) => setWho(e.target.value)} className="max-w-[12rem]" aria-label="Whose tasks">
          <option value="mine">My tasks</option>
          <option value="all">Everyone&apos;s</option>
          {team.filter((m) => m.active && m.id !== me?.id).map((m) => <option key={m.id} value={m.id}>{m.name || m.email}</option>)}
        </Select>
        <label className="flex items-center gap-2 text-sm text-zinc-600">
          <input type="checkbox" checked={showDone} onChange={(e) => setShowDone(e.target.checked)} /> Show done
        </label>
      </div>

      {groups.filter(([, list]) => list.length).map(([title, list]) => (
        <Card key={title}>
          <CardBody>
            <h2 className={`mb-2 text-sm font-bold ${title === "Overdue" ? "text-red-600" : "text-ink"}`}>{title} <span className="font-medium text-zinc-400">{list.length}</span></h2>
            <ul className="divide-y divide-zinc-100">
              {list.map((t) => (
                <li key={t.id} className="flex items-start gap-3 py-2.5">
                  <input type="checkbox" checked={t.done} onChange={() => toggle(t)} className="mt-1 h-4 w-4 accent-[var(--brand)]" aria-label="Done" />
                  <div className="min-w-0 flex-1">
                    <p className={`text-sm font-medium ${t.done ? "text-zinc-400 line-through" : "text-ink"}`}>{t.title}</p>
                    <p className="text-xs text-zinc-500">
                      {t.due_date ? dateStr(t.due_date) : "No date"}
                      {memberName(team, t.assigned_to) ? ` · ${memberName(team, t.assigned_to)}` : ""}
                      {t.businesses && <> · <Link href={`/clients/${t.businesses.id}`} className="text-brand hover:underline">{t.businesses.name}</Link></>}
                      {t.leads && <> · <Link href={`/leads/${t.leads.id}`} className="text-brand hover:underline">{t.leads.shop_name}</Link></>}
                      {t.notes ? ` · ${t.notes}` : ""}
                    </p>
                  </div>
                  <Button variant="ghost" onClick={() => remove(t)}>Delete</Button>
                </li>
              ))}
            </ul>
          </CardBody>
        </Card>
      ))}
      {shown.length === 0 && <p className="text-sm text-zinc-500">Nothing to do here.</p>}
    </div>
  );
}

function Calendar() {
  const [month, setMonth] = useState(() => { const d = new Date(); return new Date(d.getFullYear(), d.getMonth(), 1); });
  const [events, setEvents] = useState<any[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [picked, setPicked] = useState<string | null>(null);
  const today = iso(new Date());

  // The grid: Monday-first weeks covering the month.
  const start = new Date(month);
  start.setDate(1 - ((month.getDay() + 6) % 7));
  const days = Array.from({ length: 42 }, (_, i) => { const d = new Date(start); d.setDate(start.getDate() + i); return d; });
  const from = iso(days[0]);
  const to = iso(days[41]);

  useEffect(() => {
    createClient().rpc("admin_calendar", { p_from: from, p_to: to }).then(({ data, error }) => {
      if (error) setError(error.message);
      setEvents((data as any[]) ?? []);
    });
  }, [from, to]);

  const byDay = new Map<string, any[]>();
  for (const e of events ?? []) byDay.set(e.date, [...(byDay.get(e.date) ?? []), e]);
  const shift = (n: number) => { setMonth(new Date(month.getFullYear(), month.getMonth() + n, 1)); setPicked(null); };

  return (
    <div className="space-y-4">
      {error && <Notice notice={{ ok: false, text: error }} />}
      <div className="flex items-center justify-between gap-3">
        <Button variant="outline" onClick={() => shift(-1)}>← Previous</Button>
        <p className="text-base font-bold text-ink">{month.toLocaleDateString("en-IN", { month: "long", year: "numeric" })}</p>
        <Button variant="outline" onClick={() => shift(1)}>Next →</Button>
      </div>
      <div className="flex flex-wrap gap-3 text-xs text-zinc-600">
        {Object.values(KIND_STYLE).map((k) => (
          <span key={k.label} className="flex items-center gap-1.5"><span className={`h-2 w-2 rounded-full ${k.dot}`} />{k.label}</span>
        ))}
      </div>
      {!events ? <Spinner /> : (
        <Card>
          <div className="grid grid-cols-7 border-b border-zinc-100 text-center text-xs font-medium text-zinc-500">
            {["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((d) => <div key={d} className="py-2">{d}</div>)}
          </div>
          <div className="grid grid-cols-7">
            {days.map((d) => {
              const key = iso(d);
              const list = byDay.get(key) ?? [];
              const inMonth = d.getMonth() === month.getMonth();
              return (
                <button key={key} onClick={() => setPicked(key)}
                  className={`min-h-16 border-b border-r border-zinc-100 p-1.5 text-left align-top transition hover:bg-zinc-50 sm:min-h-24 ${picked === key ? "bg-violet-50" : ""}`}>
                  <span className={`inline-grid h-6 w-6 place-items-center rounded-full text-xs ${key === today ? "bg-brand font-bold text-white" : inMonth ? "text-ink" : "text-zinc-300"}`}>
                    {d.getDate()}
                  </span>
                  <span className="mt-1 hidden space-y-0.5 sm:block">
                    {list.slice(0, 3).map((e, i) => (
                      <span key={i} className={`flex items-center gap-1 truncate text-[11px] ${e.done ? "text-zinc-400 line-through" : "text-zinc-700"}`}>
                        <span className={`h-1.5 w-1.5 shrink-0 rounded-full ${KIND_STYLE[e.kind]?.dot}`} />{e.title}
                      </span>
                    ))}
                    {list.length > 3 && <span className="text-[11px] text-zinc-400">+{list.length - 3} more</span>}
                  </span>
                  {list.length > 0 && (
                    <span className="mt-1 flex gap-0.5 sm:hidden">
                      {list.slice(0, 4).map((e, i) => <span key={i} className={`h-1.5 w-1.5 rounded-full ${KIND_STYLE[e.kind]?.dot}`} />)}
                    </span>
                  )}
                </button>
              );
            })}
          </div>
        </Card>
      )}
      {picked && (
        <Card>
          <CardBody>
            <h2 className="mb-2 text-sm font-bold text-ink">{dateStr(picked)}</h2>
            {(byDay.get(picked) ?? []).length === 0 ? (
              <p className="text-sm text-zinc-500">Nothing on this day.</p>
            ) : (
              <ul className="space-y-2">
                {(byDay.get(picked) ?? []).map((e, i) => (
                  <li key={i} className="flex items-center justify-between gap-3 text-sm">
                    <span className="flex items-center gap-2">
                      <span className={`h-2 w-2 rounded-full ${KIND_STYLE[e.kind]?.dot}`} />
                      <span className={e.done ? "text-zinc-400 line-through" : "text-ink"}>{e.title}</span>
                    </span>
                    <span className="flex items-center gap-2">
                      <Badge color="zinc">{KIND_STYLE[e.kind]?.label ?? e.kind}</Badge>
                      <Link href={e.href} className="text-xs font-semibold text-brand hover:underline">Open</Link>
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </CardBody>
        </Card>
      )}
    </div>
  );
}
