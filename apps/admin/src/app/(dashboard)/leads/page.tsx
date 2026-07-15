"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import {
  Badge, Button, Card, CardBody, Input, Label, Select, Spinner, StatCard, Table,
} from "@/components/ui";
import { dateStr, inr } from "@/lib/format";
import { LEAD_SOURCES, LEAD_STATUSES, leadStatusBadge } from "@/lib/leads";

/* eslint-disable @typescript-eslint/no-explicit-any */
export default function LeadsPage() {
  const supabase = createClient();
  const [rows, setRows] = useState<any[] | null>(null);
  const [plans, setPlans] = useState<any[]>([]);
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState<string>("open");
  const [showForm, setShowForm] = useState(false);
  const [busy, setBusy] = useState(false);

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
      interested_plan_id: (fd.get("plan_id") as string) || null,
      expected_value: fd.get("expected_value") ? Number(fd.get("expected_value")) : null,
      follow_up_date: (fd.get("follow_up_date") as string) || null,
      notes: (fd.get("notes") as string) || "",
      created_by: user?.id ?? null,
    });
    setBusy(false);
    if (!error) {
      setShowForm(false);
      load();
    }
  }

  if (!rows) return <Spinner />;

  // ---- stats ----
  const today = new Date().toISOString().slice(0, 10);
  const monthStart = today.slice(0, 8) + "01";
  const open = rows.filter((r) => ["new", "contacted", "demo"].includes(r.status));
  const overdue = open.filter((r) => r.follow_up_date && r.follow_up_date < today);
  const dueToday = open.filter((r) => r.follow_up_date === today);
  const converted = rows.filter((r) => r.status === "converted");
  const convertedThisMonth = converted.filter((r) => (r.converted_at ?? "").slice(0, 10) >= monthStart);
  const closed = converted.length + rows.filter((r) => r.status === "lost").length;
  const convRate = closed ? Math.round((converted.length / closed) * 100) : null;
  const pipelineValue = open.reduce((s, r) => s + Number(r.expected_value ?? 0), 0);

  // ---- monthly funnel ----
  const createdThisMonth = rows.filter((r) => r.created_at.slice(0, 10) >= monthStart);
  const funnel = [
    ["Leads added", createdThisMonth.length],
    ["Contacted+", createdThisMonth.filter((r) => r.status !== "new").length],
    ["Demo given", createdThisMonth.filter((r) => ["demo", "converted"].includes(r.status)).length],
    ["Converted", createdThisMonth.filter((r) => r.status === "converted").length],
  ] as const;

  const filtered = rows.filter((r) => {
    if (statusFilter === "open" && !["new", "contacted", "demo"].includes(r.status)) return false;
    if (statusFilter !== "all" && statusFilter !== "open" && r.status !== statusFilter) return false;
    if (statusFilter === "overdue" && !(r.follow_up_date && r.follow_up_date < today && ["new", "contacted", "demo"].includes(r.status))) return false;
    const q = search.trim().toLowerCase();
    if (q && ![r.shop_name, r.contact_name, r.phone, r.city].some((v) => (v ?? "").toLowerCase().includes(q))) return false;
    return true;
  });

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-zinc-900">Leads &amp; sales pipeline</h1>
        <Button onClick={() => setShowForm((v) => !v)}>{showForm ? "Close" : "+ New lead"}</Button>
      </div>

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-5">
        <StatCard label="Open leads" value={open.length} hint={`${rows.length} total`} />
        <StatCard label="Follow-ups overdue" value={overdue.length} hint={`${dueToday.length} due today`} />
        <StatCard label="Converted this month" value={convertedThisMonth.length} hint={`${converted.length} all time`} />
        <StatCard label="Conversion rate" value={convRate === null ? "—" : `${convRate}%`} hint="of closed leads" />
        <StatCard label="Pipeline value" value={inr(pipelineValue)} hint="open leads, expected ₹/yr" />
      </div>

      <Card>
        <CardBody>
          <h2 className="mb-3 text-sm font-semibold text-zinc-700">This month&apos;s funnel</h2>
          <div className="flex items-center gap-2">
            {funnel.map(([label, count], i) => (
              <div key={label} className="flex flex-1 items-center gap-2">
                <div className="flex-1 rounded-lg bg-blue-50 px-3 py-2 text-center">
                  <p className="text-lg font-bold text-blue-900">{count}</p>
                  <p className="text-xs text-blue-700">{label}</p>
                </div>
                {i < funnel.length - 1 && <span className="text-zinc-400">→</span>}
              </div>
            ))}
          </div>
        </CardBody>
      </Card>

      {showForm && (
        <Card>
          <CardBody>
            <h2 className="mb-3 text-sm font-semibold text-zinc-700">New lead</h2>
            <form onSubmit={addLead} className="grid grid-cols-3 gap-4">
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
                <Input name="phone" />
              </div>
              <div>
                <Label>City / area</Label>
                <Input name="city" />
              </div>
              <div>
                <Label>Shop type</Label>
                <Select name="business_type" defaultValue="mobile">
                  <option value="mobile">Mobile shop</option>
                  <option value="garment">Garment shop</option>
                  <option value="hardware">Hardware shop</option>
                  <option value="other">Other</option>
                </Select>
              </div>
              <div>
                <Label>Source</Label>
                <Select name="source" defaultValue="field_visit">
                  {LEAD_SOURCES.map(([v, l]) => (
                    <option key={v} value={v}>{l}</option>
                  ))}
                </Select>
              </div>
              <div>
                <Label>Interested plan</Label>
                <Select name="plan_id" defaultValue="">
                  <option value="">Not sure yet</option>
                  {plans.map((p) => (
                    <option key={p.id} value={p.id}>{p.name}</option>
                  ))}
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
              <div className="col-span-3">
                <Label>Notes</Label>
                <Input name="notes" placeholder="What did they say? What do they need?" />
              </div>
              <div className="col-span-3">
                <Button type="submit" disabled={busy}>{busy ? "Saving…" : "Save lead"}</Button>
              </div>
            </form>
          </CardBody>
        </Card>
      )}

      <div className="flex flex-wrap items-center gap-2">
        <Input
          placeholder="Search shop, contact, phone, city…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="max-w-sm"
        />
        {["open", "all", ...LEAD_STATUSES, "overdue"].map((s) => (
          <button
            key={s}
            onClick={() => setStatusFilter(s)}
            className={`rounded-full px-3 py-1 text-xs font-medium capitalize transition ${
              statusFilter === s ? "bg-blue-700 text-white" : "bg-white text-zinc-600 hover:bg-zinc-50 border border-zinc-200"
            }`}
          >
            {s}
          </button>
        ))}
      </div>

      <Card>
        <Table headers={["Shop", "Contact", "Source", "Plan interest", "Expected ₹", "Follow-up", "Status", ""]}>
          {filtered.map((l) => {
            const isOverdue = l.follow_up_date && l.follow_up_date < today && ["new", "contacted", "demo"].includes(l.status);
            return (
              <tr key={l.id} className="hover:bg-zinc-50">
                <td className="px-4 py-3">
                  <p className="font-medium text-zinc-900">{l.shop_name}</p>
                  <p className="text-xs capitalize text-zinc-500">{l.business_type} • {l.city || "—"}</p>
                </td>
                <td className="px-4 py-3">
                  <p>{l.contact_name || "—"}</p>
                  <p className="text-xs text-zinc-500">{l.phone}</p>
                </td>
                <td className="px-4 py-3 text-xs capitalize">{(l.source ?? "").replace("_", " ")}</td>
                <td className="px-4 py-3">{l.plans?.name ?? "—"}</td>
                <td className="px-4 py-3">{l.expected_value ? inr(l.expected_value) : "—"}</td>
                <td className={`px-4 py-3 ${isOverdue ? "font-semibold text-red-600" : ""}`}>
                  {dateStr(l.follow_up_date)}
                  {isOverdue && <span className="ml-1 text-xs">overdue</span>}
                </td>
                <td className="px-4 py-3">
                  <Badge color={leadStatusBadge(l.status)}>{l.status}</Badge>
                </td>
                <td className="px-4 py-3 text-right">
                  <Link href={`/leads/${l.id}`} className="text-sm font-medium text-blue-700 hover:underline">
                    Manage
                  </Link>
                </td>
              </tr>
            );
          })}
          {filtered.length === 0 && (
            <tr><td colSpan={8} className="px-4 py-10 text-center text-zinc-500">No leads match.</td></tr>
          )}
        </Table>
      </Card>
    </div>
  );
}
