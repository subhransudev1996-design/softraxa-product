"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { BUSINESS_TYPES, businessTypeLabel } from "@/lib/business-types";
import {
  Badge, Button, Card, Input, Label, Select, Spinner, StatCard, Table,
} from "@/components/ui";
import { Modal, Notice } from "@/components/ops";
import { memberName, useMe, useTeam } from "@/components/me";
import { dateStr, inr } from "@/lib/format";
import {
  Duplicates, LEAD_SOURCES, STAGES, TEMPERATURES, findDuplicates, isOpenLead,
  leadStatusBadge, sourceLabel, stageLabel, temperatureOf,
} from "@/lib/leads";
import { LeadReports } from "./reports";
import { LeadImport } from "./import";
import { LostDialog } from "./lost-dialog";

/* eslint-disable @typescript-eslint/no-explicit-any */

const VIEWS = [
  ["board", "Board"],
  ["list", "List"],
  ["reports", "Reports"],
  ["import", "Import"],
] as const;

export default function LeadsPage() {
  const supabase = createClient();
  const [rows, setRows] = useState<any[] | null>(null);
  const [plans, setPlans] = useState<any[]>([]);
  const [view, setView] = useState<string>("board");
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState<string>("open");
  const [temp, setTemp] = useState<string>("all");
  const [showForm, setShowForm] = useState(false);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  // Whose leads: everyone's, mine, nobody's, or one person's (0098).
  const me = useMe();
  const team = useTeam();
  const [who, setWho] = useState<string>("all");
  // Moving a card to Lost asks why.
  const [losing, setLosing] = useState<any>(null);
  // Won and Lost on the board: the last 30 days from when the page opened.
  const [now] = useState(() => Date.now());

  const load = useCallback(() => {
    supabase
      .from("leads")
      .select("*, plans:interested_plan_id(name)")
      .order("created_at", { ascending: false })
      .then(({ data }) => setRows(data ?? []));
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    load();
    createClient().from("plans").select("id, name").eq("is_active", true).order("name")
      .then(({ data }) => setPlans(data ?? []));
  }, [load]);

  /** Move a lead to another stage; the database logs who moved it (0100). */
  async function move(lead: any, stage: string, lostReason = "") {
    if (lead.status === stage) return;
    if (stage === "lost" && !lostReason) return setLosing(lead);
    setRows((rs) => (rs ?? []).map((r) => (r.id === lead.id ? { ...r, status: stage } : r)));
    const { error } = await supabase.from("leads")
      .update(stage === "lost" ? { status: stage, lost_reason: lostReason } : { status: stage })
      .eq("id", lead.id);
    if (error) setNotice({ ok: false, text: error.message });
    load();
  }

  if (!rows) return <Spinner />;

  const today = new Date().toISOString().slice(0, 10);
  const monthStart = today.slice(0, 8) + "01";
  const monthAgo = new Date(now - 30 * 86400000).toISOString();

  // Filters shared by the board and the list.
  const base = rows.filter((r) => {
    if (who === "mine" && r.assigned_to !== me?.id) return false;
    if (who === "nobody" && r.assigned_to) return false;
    if (!["all", "mine", "nobody"].includes(who) && r.assigned_to !== who) return false;
    if (temp !== "all" && r.temperature !== temp) return false;
    const q = search.trim().toLowerCase();
    if (q && ![r.shop_name, r.contact_name, r.phone, r.city, r.campaign].some((v) => (v ?? "").toLowerCase().includes(q))) return false;
    return true;
  });

  const open = rows.filter((r) => isOpenLead(r.status));
  const overdue = open.filter((r) => r.follow_up_date && r.follow_up_date < today);
  const pipelineValue = open.reduce((s, r) => s + Number(r.expected_value ?? 0), 0);
  const wonThisMonth = rows.filter((r) => r.status === "converted" && (r.converted_at ?? "") >= monthStart);

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-2xl font-bold text-zinc-900">Leads &amp; sales pipeline</h1>
        <Button onClick={() => setShowForm(true)}>+ New lead</Button>
      </div>
      <Notice notice={notice} />

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="Open leads" value={open.length} hint={`${open.filter((r) => r.temperature === "hot").length} hot`} />
        <StatCard label="Follow-ups overdue" value={overdue.length} />
        <StatCard label="Pipeline value" value={inr(pipelineValue)} hint="expected yearly value of open leads" />
        <StatCard label="Won this month" value={wonThisMonth.length} />
      </div>

      <div className="flex flex-wrap gap-2">
        {VIEWS.map(([key, label]) => (
          <button
            key={key}
            onClick={() => setView(key)}
            aria-pressed={view === key}
            className={`cursor-pointer rounded-lg px-3 py-1.5 text-sm font-medium ring-1 ring-inset transition-colors ${view === key ? "bg-brand-tint text-brand-deep ring-brand/30" : "bg-white text-zinc-600 ring-zinc-200 hover:bg-zinc-50"}`}
          >
            {label}
          </button>
        ))}
      </div>

      {(view === "board" || view === "list") && (
        <div className="flex flex-wrap items-center gap-2">
          <Input
            placeholder="Search shop, contact, phone, city, campaign…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="max-w-xs"
          />
          <Select value={who} onChange={(e) => setWho(e.target.value)} className="max-w-[12rem]" aria-label="Whose leads">
            <option value="all">Everyone&apos;s leads</option>
            <option value="mine">My leads</option>
            <option value="nobody">Not assigned</option>
            {team.filter((m) => m.active && m.id !== me?.id).map((m) => (
              <option key={m.id} value={m.id}>{m.name || m.email}</option>
            ))}
          </Select>
          <Select value={temp} onChange={(e) => setTemp(e.target.value)} className="max-w-[9rem]" aria-label="Hot, warm or cold">
            <option value="all">Hot, warm, cold</option>
            {TEMPERATURES.map((t) => <option key={t.key} value={t.key}>{t.label}</option>)}
          </Select>
        </div>
      )}

      {view === "board" && (
        <Board
          rows={base.filter((r) => isOpenLead(r.status) || (r.stage_changed_at ?? r.updated_at) >= monthAgo)}
          team={team}
          today={today}
          onMove={move}
        />
      )}

      {view === "list" && (
        <LeadList rows={base} team={team} today={today} statusFilter={statusFilter} setStatusFilter={setStatusFilter} />
      )}

      {view === "reports" && <LeadReports rows={rows} team={team} />}
      {view === "import" && <LeadImport onDone={load} />}

      {showForm && (
        <NewLead
          plans={plans}
          onClose={() => setShowForm(false)}
          onSaved={() => {
            setShowForm(false);
            load();
          }}
        />
      )}

      {losing && (
        <LostDialog
          lead={losing}
          onClose={() => setLosing(null)}
          onLost={(reason) => {
            const lead = losing;
            setLosing(null);
            move(lead, "lost", reason);
          }}
        />
      )}
    </div>
  );
}

/** Drag a card to another column (or use its menu on a phone). Won and Lost show the last 30 days. */
function Board({ rows, team, today, onMove }: {
  rows: any[]; team: any[]; today: string; onMove: (lead: any, stage: string) => void;
}) {
  const [over, setOver] = useState<string | null>(null);
  return (
    <div className="-mx-4 overflow-x-auto px-4 pb-2 sm:mx-0 sm:px-0">
      <div className="flex min-w-max gap-3">
        {STAGES.map((stage) => {
          const cards = rows.filter((r) => r.status === stage.key);
          const value = cards.reduce((s, r) => s + Number(r.expected_value ?? 0), 0);
          return (
            <div
              key={stage.key}
              onDragOver={(e) => {
                e.preventDefault();
                setOver(stage.key);
              }}
              onDragLeave={() => setOver((o) => (o === stage.key ? null : o))}
              onDrop={(e) => {
                e.preventDefault();
                setOver(null);
                const lead = rows.find((r) => r.id === e.dataTransfer.getData("text/plain"));
                if (lead) onMove(lead, stage.key);
              }}
              className={`w-64 shrink-0 rounded-lg p-2 transition ${over === stage.key ? "bg-violet-100" : "bg-zinc-100/70"}`}
            >
              <div className="flex items-center justify-between px-2 pb-2 pt-1">
                <div className="flex items-center gap-2">
                  <Badge color={stage.color}>{stage.label}</Badge>
                  <span className="text-xs font-semibold text-zinc-500">{cards.length}</span>
                </div>
                {value > 0 && <span className="text-[11px] font-medium text-zinc-500">{inr(value)}</span>}
              </div>
              <div className="space-y-2">
                {cards.map((l) => {
                  const t = temperatureOf(l.temperature);
                  const late = isOpenLead(l.status) && l.follow_up_date && l.follow_up_date < today;
                  return (
                    <div
                      key={l.id}
                      draggable
                      onDragStart={(e) => e.dataTransfer.setData("text/plain", l.id)}
                      className="cursor-grab rounded-lg bg-white p-3 shadow-sm ring-1 ring-zinc-200 active:cursor-grabbing"
                    >
                      <Link href={`/leads/${l.id}`} className="block">
                        <div className="flex items-start gap-2">
                          <span className={`mt-1.5 h-2 w-2 shrink-0 rounded-full ${t.dot}`} title={t.label} />
                          <p className="min-w-0 font-semibold leading-5 text-ink">{l.shop_name}</p>
                        </div>
                        <p className="mt-1 truncate text-xs text-zinc-500">
                          {l.contact_name || "—"}{l.city ? ` · ${l.city}` : ""}
                        </p>
                        <div className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-[11px]">
                          {l.follow_up_date && (
                            <span className={late ? "font-semibold text-red-600" : "text-zinc-500"}>
                              {late ? "Overdue " : "Follow up "}{dateStr(l.follow_up_date)}
                            </span>
                          )}
                          {l.expected_value ? <span className="text-zinc-500">{inr(l.expected_value)}</span> : null}
                          {memberName(team, l.assigned_to) && (
                            <span className="text-zinc-400">{memberName(team, l.assigned_to)}</span>
                          )}
                        </div>
                      </Link>
                      <select
                        value={l.status}
                        onChange={(e) => onMove(l, e.target.value)}
                        aria-label="Move to"
                        className="mt-2 w-full rounded-lg border border-zinc-200 bg-zinc-50 px-2 py-1 text-xs text-zinc-600 lg:hidden"
                      >
                        {STAGES.map((s) => <option key={s.key} value={s.key}>Move to: {s.label}</option>)}
                      </select>
                    </div>
                  );
                })}
                {cards.length === 0 && <p className="px-2 py-4 text-center text-xs text-zinc-500">Drop a lead here</p>}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function LeadList({ rows, team, today, statusFilter, setStatusFilter }: {
  rows: any[]; team: any[]; today: string; statusFilter: string; setStatusFilter: (s: string) => void;
}) {
  const filtered = rows.filter((r) => {
    if (statusFilter === "open") return isOpenLead(r.status);
    if (statusFilter === "overdue") return isOpenLead(r.status) && r.follow_up_date && r.follow_up_date < today;
    return statusFilter === "all" || r.status === statusFilter;
  });
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2">
        {[["open", "Open"], ["all", "All"], ...STAGES.map((s) => [s.key, s.label]), ["overdue", "Overdue"]].map(([key, label]) => (
          <button
            key={key}
            onClick={() => setStatusFilter(key)}
            className={`rounded-full px-3 py-1 text-xs font-medium transition ${
              statusFilter === key ? "bg-brand text-white" : "border border-zinc-200 bg-white text-zinc-600 hover:bg-zinc-50"
            }`}
          >
            {label}
          </button>
        ))}
      </div>
      <Card>
        <Table headers={["Shop", "Contact", "Source", "Plan interest", "Expected ₹", "Follow-up", "Stage", "With", ""]}>
          {filtered.map((l) => {
            const isOverdue = isOpenLead(l.status) && l.follow_up_date && l.follow_up_date < today;
            const t = temperatureOf(l.temperature);
            return (
              <tr key={l.id} className="hover:bg-zinc-50">
                <td className="px-4 py-3">
                  <p className="flex items-center gap-2 font-medium text-zinc-900">
                    <span className={`h-2 w-2 shrink-0 rounded-full ${t.dot}`} title={t.label} />
                    {l.shop_name}
                  </p>
                  <p className="text-xs text-zinc-500">{businessTypeLabel(l.business_type)} • {l.city || "—"}</p>
                </td>
                <td className="px-4 py-3">
                  <p>{l.contact_name || "—"}</p>
                  <p className="text-xs text-zinc-500">{l.phone}</p>
                </td>
                <td className="px-4 py-3 text-xs">
                  {sourceLabel(l.source)}
                  {l.campaign && <span className="block text-zinc-400">{l.campaign}</span>}
                </td>
                <td className="px-4 py-3">{l.plans?.name ?? "—"}</td>
                <td className="px-4 py-3">{l.expected_value ? inr(l.expected_value) : "—"}</td>
                <td className={`px-4 py-3 ${isOverdue ? "font-semibold text-red-600" : ""}`}>
                  {dateStr(l.follow_up_date)}
                  {isOverdue && <span className="ml-1 text-xs">overdue</span>}
                </td>
                <td className="px-4 py-3">
                  <Badge color={leadStatusBadge(l.status)}>{stageLabel(l.status)}</Badge>
                </td>
                <td className="px-4 py-3 text-xs">{memberName(team, l.assigned_to) ?? <span className="text-zinc-400">Nobody</span>}</td>
                <td className="px-4 py-3 text-right">
                  <Link href={`/leads/${l.id}`} className="text-sm font-medium text-brand hover:underline">Manage</Link>
                </td>
              </tr>
            );
          })}
          {filtered.length === 0 && (
            <tr><td colSpan={9} className="px-4 py-10 text-center text-zinc-500">No leads match.</td></tr>
          )}
        </Table>
      </Card>
    </div>
  );
}

/** Add a lead; warns when the phone number is already a lead or a client. */
function NewLead({ plans, onClose, onSaved }: { plans: any[]; onClose: () => void; onSaved: () => void }) {
  const supabase = createClient();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [dupes, setDupes] = useState<Duplicates | null>(null);

  async function addLead(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setBusy(true);
    const fd = new FormData(e.currentTarget);
    const { data: { user } } = await supabase.auth.getUser();
    const { error } = await supabase.from("leads").insert({
      shop_name: fd.get("shop_name") as string,
      contact_name: (fd.get("contact_name") as string) || "",
      phone: (fd.get("phone") as string) || "",
      city: (fd.get("city") as string) || "",
      business_type: (fd.get("business_type") as string) || "other",
      source: (fd.get("source") as string) || "other",
      temperature: (fd.get("temperature") as string) || "warm",
      campaign: ((fd.get("campaign") as string) || "").trim(),
      interested_plan_id: (fd.get("plan_id") as string) || null,
      expected_value: fd.get("expected_value") ? Number(fd.get("expected_value")) : null,
      follow_up_date: (fd.get("follow_up_date") as string) || null,
      notes: (fd.get("notes") as string) || "",
      created_by: user?.id ?? null,
    });
    setBusy(false);
    if (error) return setError(error.message);
    onSaved();
  }

  return (
    <Modal title="New lead" onClose={onClose} wide>
      <form onSubmit={addLead} className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div>
          <Label>Shop name *</Label>
          <Input name="shop_name" required />
        </div>
        <div>
          <Label>Contact person</Label>
          <Input name="contact_name" />
        </div>
        <div>
          <Label>Phone</Label>
          <Input name="phone" inputMode="tel" onBlur={async (e) => setDupes(await findDuplicates(supabase, e.target.value))} />
        </div>
        <div>
          <Label>City / area</Label>
          <Input name="city" />
        </div>
        {dupes && (
          <div className="rounded-lg bg-amber-50 px-4 py-3 text-sm text-amber-900 sm:col-span-2">
            <p className="font-semibold">This phone number is already known:</p>
            <ul className="mt-1 list-disc pl-5">
              {dupes.leads.map((l) => (
                <li key={l.id}>
                  Lead <Link href={`/leads/${l.id}`} className="font-semibold underline">{l.shop_name}</Link> ({stageLabel(l.status)})
                </li>
              ))}
              {dupes.clients.map((c) => (
                <li key={c.id}>
                  Client <Link href={`/clients/${c.id}`} className="font-semibold underline">{c.name}</Link>
                </li>
              ))}
            </ul>
            <p className="mt-1 text-xs">You can still add it if it&apos;s a different shop.</p>
          </div>
        )}
        <div>
          <Label>Business type</Label>
          <Select name="business_type" defaultValue="other">
            {BUSINESS_TYPES.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}
          </Select>
        </div>
        <div>
          <Label>Source</Label>
          <Select name="source" defaultValue="field_visit">
            {LEAD_SOURCES.filter(([v]) => !["app_signup", "import"].includes(v)).map(([v, l]) => (
              <option key={v} value={v}>{l}</option>
            ))}
          </Select>
        </div>
        <div>
          <Label>Hot, warm or cold</Label>
          <Select name="temperature" defaultValue="warm">
            {TEMPERATURES.map((t) => <option key={t.key} value={t.key}>{t.label}</option>)}
          </Select>
        </div>
        <div>
          <Label>Campaign (optional)</Label>
          <Input name="campaign" placeholder="e.g. Diwali Facebook ad" />
        </div>
        <div>
          <Label>Interested plan</Label>
          <Select name="plan_id" defaultValue="">
            <option value="">Not sure yet</option>
            {plans.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </Select>
        </div>
        <div>
          <Label>Expected value ₹/yr</Label>
          <Input name="expected_value" type="number" step="0.01" />
        </div>
        <div>
          <Label>Follow-up date</Label>
          <Input name="follow_up_date" type="date" />
        </div>
        <div>
          <Label>Notes</Label>
          <Input name="notes" placeholder="What did they say? What do they need?" />
        </div>
        {error && <p className="text-sm text-red-600 sm:col-span-2">{error}</p>}
        <div className="flex justify-end gap-2 sm:col-span-2">
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button type="submit" disabled={busy}>{busy ? "Saving…" : "Save lead"}</Button>
        </div>
      </form>
    </Modal>
  );
}
