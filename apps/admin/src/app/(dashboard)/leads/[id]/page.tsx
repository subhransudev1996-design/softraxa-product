"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { businessTypeLabel } from "@/lib/business-types";
import {
  Badge, Button, Card, CardBody, Input, Label, Select, Spinner,
} from "@/components/ui";
import { dateStr, dateTimeStr, inr } from "@/lib/format";
import {
  ACTIVITY_TYPES, Duplicates, LEAD_SOURCES, STAGES, TEMPERATURES, findDuplicates, isOpenLead,
  leadStatusBadge, stageLabel, stageNote,
} from "@/lib/leads";
import { memberName, useCan, useTeam } from "@/components/me";
import { QuoteCalculator } from "@/components/quote";
import { LostDialog } from "../lost-dialog";

/* eslint-disable @typescript-eslint/no-explicit-any */
export default function LeadDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const supabase = createClient();

  const [lead, setLead] = useState<any>(null);
  const [activities, setActivities] = useState<any[]>([]);
  const [plans, setPlans] = useState<any[]>([]);
  const [discount, setDiscount] = useState(20);
  const [dupes, setDupes] = useState<Duplicates | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const [askLost, setAskLost] = useState(false);
  const team = useTeam();
  // The lowest price is for whoever handles Plans & prices (the owner).
  const showLowest = useCan("plans");

  const load = useCallback(async () => {
    const [l, a, p, s] = await Promise.all([
      supabase.from("leads").select("*, plans:interested_plan_id(name), businesses:converted_business_id(id, name)").eq("id", id).single(),
      supabase.from("lead_activities").select("*").eq("lead_id", id).order("created_at", { ascending: false }),
      supabase.from("plans").select("*").eq("is_active", true).order("name"),
      supabase.from("platform_settings").select("website_discount_pct").maybeSingle(),
    ]);
    setLead(l.data);
    setActivities(a.data ?? []);
    setPlans(p.data ?? []);
    setDiscount(Number(s.data?.website_discount_pct ?? 20));
    if (l.data?.phone) setDupes(await findDuplicates(supabase, l.data.phone, id));
  }, [id]); // eslint-disable-line react-hooks/exhaustive-deps

  // Defer the initial fetch out of the synchronous effect body so its state
  // updates don't run during the effect (react-hooks/set-state-in-effect).
  useEffect(() => {
    let active = true;
    Promise.resolve().then(() => { if (active) load(); });
    return () => { active = false; };
  }, [load]);

  function flash(text: string) {
    setMsg(text);
    setTimeout(() => setMsg(null), 2500);
  }

  async function save(patch: Record<string, unknown>) {
    const { error } = await supabase.from("leads").update(patch).eq("id", id);
    if (error) return flash(error.message);
    await load();
    flash("Saved");
  }

  /** Give the lead to a team member who has Leads (0098), or to nobody. */
  async function assign(userId: string) {
    const { error } = await supabase.rpc("admin_assign", { p_kind: "lead", p_id: id, p_user: userId || null });
    if (error) return flash(error.message);
    await load();
    flash("Saved");
  }

  async function logActivity(activity_type: string, note: string) {
    const { data: { user } } = await supabase.auth.getUser();
    await supabase.from("lead_activities").insert({
      lead_id: id, activity_type, note, created_by: user?.id ?? null,
    });
  }

  // The stage change itself is logged by the database (0100).
  async function setStatus(status: string) {
    if (status === "lost") return setAskLost(true);
    await save({ status });
  }

  async function addActivity(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    const note = (fd.get("note") as string) || "";
    if (!note.trim()) return;
    await logActivity((fd.get("type") as string) || "note", note);
    (e.target as HTMLFormElement).reset();
    await load();
  }

  function convertToClient() {
    // Prefill the existing new-client form; it links back to this lead on success.
    const params = new URLSearchParams({
      leadId: id,
      businessName: lead.shop_name ?? "",
      ownerName: lead.contact_name ?? "",
      phone: lead.phone ?? "",
      type: lead.business_type ?? "other",
      planId: lead.interested_plan_id ?? "",
    });
    router.push(`/clients/new?${params.toString()}`);
  }

  if (!lead) return <Spinner />;

  const isOpen = isOpenLead(lead.status);
  const pricedPlans = plans.filter((p) => Number(p.list_price) > 0);

  return (
    <div className="max-w-5xl space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-3">
            <h1 className="text-2xl font-bold text-zinc-900">{lead.shop_name}</h1>
            <Badge color={leadStatusBadge(lead.status)}>{stageLabel(lead.status)}</Badge>
          </div>
          <p className="text-sm text-zinc-500">
            {lead.contact_name || "—"} • {lead.phone || "no phone"} •{" "}
            <span>{businessTypeLabel(lead.business_type)}</span>
            {lead.city ? ` • ${lead.city}` : ""}
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-3">
          {msg && <span className="text-sm font-medium text-green-700">{msg}</span>}
          {lead.businesses ? (
            <Link href={`/clients/${lead.businesses.id}`}>
              <Button variant="outline">View client → {lead.businesses.name}</Button>
            </Link>
          ) : (
            isOpen && <Button onClick={convertToClient}>Convert to client</Button>
          )}
        </div>
      </div>

      {dupes && (
        <div className="rounded-md bg-amber-50 px-4 py-3 text-sm text-amber-900">
          <b>Same phone number as:</b>{" "}
          {[
            ...dupes.leads.map((l) => (
              <Link key={l.id} href={`/leads/${l.id}`} className="font-semibold underline">lead {l.shop_name} ({stageLabel(l.status)})</Link>
            )),
            ...dupes.clients.map((c) => (
              <Link key={c.id} href={`/clients/${c.id}`} className="font-semibold underline">client {c.name}</Link>
            )),
          ].reduce<React.ReactNode[]>((acc, el, i) => (i ? [...acc, ", ", el] : [el]), [])}
        </div>
      )}

      {/* status pipeline */}
      <Card>
        <CardBody>
          <h2 className="mb-3 text-sm font-semibold text-zinc-700">Pipeline stage</h2>
          <div className="flex flex-wrap gap-2">
            {STAGES.map((s) => (
              <button
                key={s.key}
                onClick={() => s.key !== lead.status && setStatus(s.key)}
                className={`rounded-full px-4 py-1.5 text-sm font-medium transition ${
                  lead.status === s.key
                    ? "bg-brand text-white"
                    : "border border-zinc-200 bg-white text-zinc-600 hover:bg-zinc-50"
                }`}
              >
                {s.label}
              </button>
            ))}
          </div>
          <div className="mt-3 flex flex-wrap items-center gap-2">
            <span className="text-xs font-semibold text-zinc-500">How likely:</span>
            {TEMPERATURES.map((t) => (
              <button
                key={t.key}
                onClick={() => t.key !== lead.temperature && save({ temperature: t.key })}
                className={`flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold transition ${
                  lead.temperature === t.key ? "bg-ink text-white" : "border border-zinc-200 bg-white text-zinc-600 hover:bg-zinc-50"
                }`}
              >
                <span className={`h-2 w-2 rounded-full ${t.dot}`} />
                {t.label}
              </button>
            ))}
            {lead.stage_changed_at && (
              <span className="text-xs text-zinc-500">In this stage since {dateStr(lead.stage_changed_at)}</span>
            )}
          </div>
          {lead.status === "lost" && lead.lost_reason && (
            <p className="mt-2 text-sm text-red-600">Lost: {lead.lost_reason}</p>
          )}
        </CardBody>
      </Card>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        {/* details */}
        <Card>
          <CardBody>
            <h2 className="mb-3 text-sm font-semibold text-zinc-700">Lead details</h2>
            <div className="space-y-3">
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <div>
                  <Label>Contact person</Label>
                  <Input defaultValue={lead.contact_name} onBlur={(e) => e.target.value !== lead.contact_name && save({ contact_name: e.target.value })} />
                </div>
                <div>
                  <Label>Phone</Label>
                  <Input defaultValue={lead.phone} onBlur={(e) => e.target.value !== lead.phone && save({ phone: e.target.value })} />
                </div>
                <div>
                  <Label>City / area</Label>
                  <Input defaultValue={lead.city} onBlur={(e) => e.target.value !== lead.city && save({ city: e.target.value })} />
                </div>
                <div>
                  <Label>Source</Label>
                  <Select value={lead.source} onChange={(e) => save({ source: e.target.value })}>
                    {!LEAD_SOURCES.some(([v]) => v === lead.source) && <option value={lead.source}>{lead.source}</option>}
                    {LEAD_SOURCES.map(([v, l]) => (
                      <option key={v} value={v}>{l}</option>
                    ))}
                  </Select>
                </div>
                <div>
                  <Label>Campaign</Label>
                  <Input defaultValue={lead.campaign} placeholder="e.g. Diwali Facebook ad"
                    onBlur={(e) => e.target.value.trim() !== lead.campaign && save({ campaign: e.target.value.trim() })} />
                </div>
                <div>
                  <Label>Interested plan</Label>
                  <Select value={lead.interested_plan_id ?? ""} onChange={(e) => save({ interested_plan_id: e.target.value || null })}>
                    <option value="">Not sure yet</option>
                    {plans.map((p) => (
                      <option key={p.id} value={p.id}>{p.name}</option>
                    ))}
                  </Select>
                </div>
                <div>
                  <Label>With</Label>
                  <Select value={lead.assigned_to ?? ""} onChange={(e) => assign(e.target.value)}>
                    <option value="">Nobody</option>
                    {team
                      .filter((m) => (m.active && m.areas.includes("leads")) || m.id === lead.assigned_to)
                      .map((m) => (
                        <option key={m.id} value={m.id}>{m.name || m.email}</option>
                      ))}
                  </Select>
                </div>
                <div>
                  <Label>Expected value ₹/yr</Label>
                  <Input
                    type="number" step="0.01" defaultValue={lead.expected_value ?? ""}
                    onBlur={(e) => save({ expected_value: e.target.value ? Number(e.target.value) : null })}
                  />
                </div>
                <div className="sm:col-span-2">
                  <Label>Follow-up date</Label>
                  <Input
                    type="date" defaultValue={lead.follow_up_date ?? ""}
                    onBlur={(e) => save({ follow_up_date: e.target.value || null })}
                  />
                </div>
                <div className="sm:col-span-2">
                  <Label>Notes</Label>
                  <Input defaultValue={lead.notes} onBlur={(e) => e.target.value !== lead.notes && save({ notes: e.target.value })} />
                </div>
              </div>
              <p className="text-xs text-zinc-500">
                Added {dateStr(lead.created_at)}
                {lead.expected_value ? ` • worth ${inr(lead.expected_value)}/yr` : ""}
                {lead.converted_at ? ` • won ${dateStr(lead.converted_at)}` : ""}
              </p>
            </div>
          </CardBody>
        </Card>

        {/* activity log */}
        <Card>
          <CardBody>
            <h2 className="mb-3 text-sm font-semibold text-zinc-700">Activity log</h2>
            <form onSubmit={addActivity} className="mb-4 flex flex-col gap-2 sm:flex-row">
              <Select name="type" defaultValue="call" className="sm:w-36">
                {ACTIVITY_TYPES.map(([v, l]) => (
                  <option key={v} value={v}>{l}</option>
                ))}
              </Select>
              <Input name="note" placeholder="What happened?" />
              <Button type="submit">Add</Button>
            </form>
            <ul className="space-y-3 text-sm">
              {activities.map((a) => (
                <li key={a.id} className="border-b border-zinc-100 pb-2">
                  <div className="flex items-center justify-between gap-2">
                    <Badge color={a.activity_type === "status_change" ? "purple" : a.activity_type === "quote" ? "green" : "blue"}>
                      {a.activity_type === "status_change"
                        ? "stage"
                        : ACTIVITY_TYPES.find(([v]) => v === a.activity_type)?.[1] ?? a.activity_type.replace("_", " ")}
                    </Badge>
                    <span className="text-xs text-zinc-500">
                      {memberName(team, a.created_by) ? `${memberName(team, a.created_by)} · ` : ""}{dateTimeStr(a.created_at)}
                    </span>
                  </div>
                  {a.note && (
                    <p className="mt-1 text-zinc-700">{a.activity_type === "status_change" ? stageNote(a.note) : a.note}</p>
                  )}
                </li>
              ))}
              {activities.length === 0 && <li className="text-zinc-500">No activity yet.</li>}
            </ul>
          </CardBody>
        </Card>
      </div>

      {pricedPlans.length > 0 && lead.status !== "converted" && (
        <QuoteCalculator
          plans={pricedPlans}
          discount={discount}
          showLowest={showLowest}
          phone={lead.phone || undefined}
          greeting={`Namaste${lead.contact_name ? ` ${lead.contact_name}` : ""}! `}
          initialPlanId={lead.interested_plan_id}
          onSent={async (text) => {
            await logActivity("quote", text);
            if (lead.status === "new" || lead.status === "contacted" || lead.status === "demo") {
              await save({ status: "negotiation" });
            } else {
              await load();
            }
          }}
        />
      )}

      {askLost && (
        <LostDialog
          lead={lead}
          onClose={() => setAskLost(false)}
          onLost={async (reason) => {
            setAskLost(false);
            await save({ status: "lost", lost_reason: reason });
          }}
        />
      )}
    </div>
  );
}
