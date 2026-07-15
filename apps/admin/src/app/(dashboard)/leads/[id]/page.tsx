"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import {
  Badge, Button, Card, CardBody, Input, Label, Select, Spinner,
} from "@/components/ui";
import { dateStr, dateTimeStr, inr } from "@/lib/format";
import { ACTIVITY_TYPES, LEAD_SOURCES, LEAD_STATUSES, leadStatusBadge } from "@/lib/leads";

/* eslint-disable @typescript-eslint/no-explicit-any */
export default function LeadDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const supabase = createClient();

  const [lead, setLead] = useState<any>(null);
  const [activities, setActivities] = useState<any[]>([]);
  const [plans, setPlans] = useState<any[]>([]);
  const [msg, setMsg] = useState<string | null>(null);
  const [lostReason, setLostReason] = useState("");
  const [askLostReason, setAskLostReason] = useState(false);

  const load = useCallback(async () => {
    const [l, a, p] = await Promise.all([
      supabase.from("leads").select("*, plans:interested_plan_id(name), businesses:converted_business_id(id, name)").eq("id", id).single(),
      supabase.from("lead_activities").select("*").eq("lead_id", id).order("created_at", { ascending: false }),
      supabase.from("plans").select("id, name").eq("is_active", true).order("name"),
    ]);
    setLead(l.data);
    setActivities(a.data ?? []);
    setPlans(p.data ?? []);
  }, [id]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => { load(); }, [load]);

  function flash(text: string) {
    setMsg(text);
    setTimeout(() => setMsg(null), 2500);
  }

  async function save(patch: Record<string, unknown>) {
    await supabase.from("leads").update(patch).eq("id", id);
    await load();
    flash("Saved");
  }

  async function logActivity(activity_type: string, note: string) {
    const { data: { user } } = await supabase.auth.getUser();
    await supabase.from("lead_activities").insert({
      lead_id: id, activity_type, note, created_by: user?.id ?? null,
    });
  }

  async function setStatus(status: string) {
    if (status === "lost") {
      setAskLostReason(true);
      return;
    }
    const patch: Record<string, unknown> =
      status === "converted"
        ? { status, converted_at: new Date().toISOString() }
        : { status };
    await logActivity("status_change", `${lead.status} → ${status}`);
    await save(patch);
  }

  async function markLost() {
    await logActivity("status_change", `${lead.status} → lost${lostReason ? ` (${lostReason})` : ""}`);
    await save({ status: "lost", lost_reason: lostReason });
    setAskLostReason(false);
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

  const isOpen = ["new", "contacted", "demo"].includes(lead.status);

  return (
    <div className="max-w-4xl space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <div className="flex items-center gap-3">
            <h1 className="text-2xl font-bold text-zinc-900">{lead.shop_name}</h1>
            <Badge color={leadStatusBadge(lead.status)}>{lead.status}</Badge>
          </div>
          <p className="text-sm text-zinc-500">
            {lead.contact_name || "—"} • {lead.phone || "no phone"} •{" "}
            <span className="capitalize">{lead.business_type}</span>
            {lead.city ? ` • ${lead.city}` : ""}
          </p>
        </div>
        <div className="flex items-center gap-3">
          {msg && <span className="text-sm font-medium text-green-700">{msg}</span>}
          {lead.status === "converted" && lead.businesses ? (
            <Link href={`/clients/${lead.businesses.id}`}>
              <Button variant="outline">View client → {lead.businesses.name}</Button>
            </Link>
          ) : (
            isOpen && <Button onClick={convertToClient}>Convert to client</Button>
          )}
        </div>
      </div>

      {/* status pipeline */}
      <Card>
        <CardBody>
          <h2 className="mb-3 text-sm font-semibold text-zinc-700">Pipeline stage</h2>
          <div className="flex flex-wrap gap-2">
            {LEAD_STATUSES.map((s) => (
              <button
                key={s}
                onClick={() => s !== lead.status && setStatus(s)}
                className={`rounded-full px-4 py-1.5 text-sm font-medium capitalize transition ${
                  lead.status === s
                    ? "bg-brand text-white"
                    : "border border-zinc-200 bg-white text-zinc-600 hover:bg-zinc-50"
                }`}
              >
                {s}
              </button>
            ))}
          </div>
          {askLostReason && (
            <div className="mt-3 flex gap-2">
              <Input
                placeholder="Why was this lead lost? (price, competitor, not interested…)"
                value={lostReason}
                onChange={(e) => setLostReason(e.target.value)}
              />
              <Button variant="danger" onClick={markLost}>Mark lost</Button>
              <Button variant="ghost" onClick={() => setAskLostReason(false)}>Cancel</Button>
            </div>
          )}
          {lead.status === "lost" && lead.lost_reason && (
            <p className="mt-2 text-sm text-red-600">Lost reason: {lead.lost_reason}</p>
          )}
        </CardBody>
      </Card>

      <div className="grid grid-cols-2 gap-6">
        {/* details */}
        <Card>
          <CardBody>
            <h2 className="mb-3 text-sm font-semibold text-zinc-700">Lead details</h2>
            <div className="space-y-3">
              <div className="grid grid-cols-2 gap-3">
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
                    {LEAD_SOURCES.map(([v, l]) => (
                      <option key={v} value={v}>{l}</option>
                    ))}
                  </Select>
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
                  <Label>Expected value ₹/yr</Label>
                  <Input
                    type="number" step="0.01" defaultValue={lead.expected_value ?? ""}
                    onBlur={(e) => save({ expected_value: e.target.value ? Number(e.target.value) : null })}
                  />
                </div>
                <div className="col-span-2">
                  <Label>Follow-up date</Label>
                  <Input
                    type="date" defaultValue={lead.follow_up_date ?? ""}
                    onBlur={(e) => save({ follow_up_date: e.target.value || null })}
                  />
                </div>
                <div className="col-span-2">
                  <Label>Notes</Label>
                  <Input defaultValue={lead.notes} onBlur={(e) => e.target.value !== lead.notes && save({ notes: e.target.value })} />
                </div>
              </div>
              <p className="text-xs text-zinc-400">
                Added {dateStr(lead.created_at)}
                {lead.expected_value ? ` • worth ${inr(lead.expected_value)}/yr` : ""}
              </p>
            </div>
          </CardBody>
        </Card>

        {/* activity log */}
        <Card>
          <CardBody>
            <h2 className="mb-3 text-sm font-semibold text-zinc-700">Activity log</h2>
            <form onSubmit={addActivity} className="mb-4 flex gap-2">
              <Select name="type" defaultValue="call" className="w-36">
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
                  <div className="flex items-center justify-between">
                    <Badge color={a.activity_type === "status_change" ? "purple" : "blue"}>
                      {a.activity_type.replace("_", " ")}
                    </Badge>
                    <span className="text-xs text-zinc-400">{dateTimeStr(a.created_at)}</span>
                  </div>
                  {a.note && <p className="mt-1 text-zinc-700">{a.note}</p>}
                </li>
              ))}
              {activities.length === 0 && <li className="text-zinc-500">No activity yet.</li>}
            </ul>
          </CardBody>
        </Card>
      </div>
    </div>
  );
}
