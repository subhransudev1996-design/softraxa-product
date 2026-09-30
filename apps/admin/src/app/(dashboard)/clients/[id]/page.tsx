"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { businessTypeLabel } from "@/lib/business-types";
import {
  Badge, Button, Card, CardBody, Input, Label, Select, Spinner, Toggle, subscriptionBadge,
} from "@/components/ui";
import { Modal, Notice, RenewDialog, waLink } from "@/components/ops";
import { dateStr, dateTimeStr, inr } from "@/lib/format";

// Plan features the app enforces (app_feature_keys, migration 0033).
const FEATURES: [string, string][] = [
  ["gst_billing", "GST billing"],
  ["reports", "Reports"],
  ["pdf_invoice", "PDF invoice"],
  ["a4_print", "A4 print"],
  ["thermal_print", "Thermal print"],
  ["offline_billing", "Offline billing"],
  ["expense_module", "Expenses"],
  ["excel_import", "Excel import"],
  ["service_module", "Services & job cards"],
];

const ACTION_LABELS: Record<string, string> = {
  "subscription.renewed": "Renewed",
  "subscription.updated": "Subscription corrected",
  "subscription.payment_claimed": "Shop reported a payment",
  "subscription.claim_rejected": "Payment claim rejected",
  "business.suspended": "Suspended",
  "business.activated": "Activated",
  "feature.enabled": "Feature turned on",
  "feature.disabled": "Feature turned off",
  "business.onboarded": "Finished setup",
  "business.exported": "Owner exported data",
  "support.replied": "Replied to a support request",
  "support.status": "Support request status changed",
};

/* eslint-disable @typescript-eslint/no-explicit-any */
export default function ClientDetailPage() {
  const { id } = useParams<{ id: string }>();
  const supabase = createClient();

  const [business, setBusiness] = useState<any>(null);
  const [subscription, setSubscription] = useState<any>(null);
  const [flags, setFlags] = useState<any>(null);
  const [plans, setPlans] = useState<any[]>([]);
  const [payments, setPayments] = useState<any[]>([]);
  const [claims, setClaims] = useState<any[]>([]);
  const [history, setHistory] = useState<any[]>([]);
  const [usage, setUsage] = useState<{ products: number; invoices: number; staff: number; lastBill: string | null; bills30: number } | null>(null);
  const [staff, setStaff] = useState<any[]>([]);
  const [tickets, setTickets] = useState<any[]>([]);
  const [issues, setIssues] = useState<any[]>([]);
  const [notes, setNotes] = useState<any[]>([]);
  const [note, setNote] = useState("");
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [renewOpen, setRenewOpen] = useState(false);
  const [correctOpen, setCorrectOpen] = useState(false);
  const [confirmSuspend, setConfirmSuspend] = useState(false);

  const load = useCallback(async () => {
    const [biz, sub, ff, pl, pay, cl, hist] = await Promise.all([
      supabase.from("businesses").select("*").eq("id", id).single(),
      supabase.from("subscriptions").select("*, plans(name, user_limit)").eq("business_id", id)
        .order("created_at", { ascending: false }).limit(1).maybeSingle(),
      supabase.from("feature_flags").select("*").eq("business_id", id).maybeSingle(),
      supabase.from("plans").select("*").eq("is_active", true).order("monthly_price"),
      supabase.from("subscription_payments").select("*").eq("business_id", id)
        .order("payment_date", { ascending: false }).limit(20),
      supabase.from("renewal_claims").select("*").eq("business_id", id).eq("status", "pending"),
      supabase.from("audit_logs").select("*").eq("business_id", id)
        .or("action.like.subscription.%,action.like.business.%,action.like.feature.%,action.like.support.%")
        .order("created_at", { ascending: false }).limit(25),
    ]);
    setBusiness(biz.data);
    setSubscription(sub.data);
    setFlags(ff.data);
    setPlans(pl.data ?? []);
    setPayments(pay.data ?? []);
    setClaims(cl.data ?? []);
    setHistory(hist.data ?? []);

    // Users, tickets, mismatches in the latest nightly check, private notes.
    const since = new Date(Date.now() - 30 * 86400000).toISOString();
    const [people, tk, run, nt, recent] = await Promise.all([
      supabase.from("profiles").select("id, full_name, email, role").eq("business_id", id).order("role"),
      supabase.from("support_tickets").select("id, subject, status, created_at, last_reply_at, last_shop_message_at")
        .eq("business_id", id).order("created_at", { ascending: false }).limit(5),
      supabase.from("reconciliation_runs").select("id").order("started_at", { ascending: false }).limit(1).maybeSingle(),
      supabase.from("admin_notes").select("*").eq("business_id", id).is("ticket_id", null)
        .order("created_at", { ascending: false }).limit(30),
      supabase.from("invoices").select("id", { count: "exact", head: true }).eq("business_id", id).gte("created_at", since),
    ]);
    setStaff(people.data ?? []);
    setTickets(tk.data ?? []);
    setNotes(nt.data ?? []);
    if (run.data?.id) {
      const { data: iss } = await supabase.from("reconciliation_issues").select("*")
        .eq("run_id", run.data.id).eq("business_id", id);
      setIssues(iss ?? []);
    }

    const [prodCount, invCount, staffCount, lastInv] = await Promise.all([
      supabase.from("products").select("id", { count: "exact", head: true }).eq("business_id", id),
      supabase.from("invoices").select("id", { count: "exact", head: true }).eq("business_id", id),
      supabase.from("profiles").select("id", { count: "exact", head: true }).eq("business_id", id),
      supabase.from("invoices").select("created_at").eq("business_id", id)
        .order("created_at", { ascending: false }).limit(1).maybeSingle(),
    ]);
    setUsage({
      products: prodCount.count ?? 0,
      invoices: invCount.count ?? 0,
      staff: staffCount.count ?? 0,
      lastBill: lastInv.data?.created_at ?? null,
      bills30: recent.count ?? 0,
    });
  }, [id]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    let active = true;
    Promise.resolve().then(() => { if (active) load(); });
    return () => { active = false; };
  }, [load]);

  async function toggleActive() {
    const wasActive = business.is_active;
    setConfirmSuspend(false);
    const res = await fetch("/api/clients/toggle-status", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ businessId: id, suspend: wasActive }),
    });
    const json = await res.json().catch(() => ({}));
    if (!res.ok) {
      setNotice({ ok: false, text: json.error || "Couldn't change the client's status" });
      return;
    }
    await load();
    setNotice({ ok: true, text: wasActive ? "Suspended — the shop can't use the app until you activate it." : "Activated — the shop can use the app again." });
  }

  async function toggleFlag(key: string, value: boolean) {
    const { error } = await supabase.rpc("admin_set_feature", { p_business: id, p_key: key, p_on: value });
    if (error) {
      setNotice({ ok: false, text: error.message });
      return;
    }
    setFlags((f: any) => ({ ...f, [key]: value }));
    setNotice({ ok: true, text: `${FEATURES.find((f) => f[0] === key)?.[1]} turned ${value ? "on" : "off"}` });
  }

  async function addNote() {
    if (!note.trim()) return;
    const { data: { user } } = await supabase.auth.getUser();
    const { error } = await supabase.from("admin_notes").insert({ business_id: id, note: note.trim(), created_by: user?.id ?? null });
    if (error) {
      setNotice({ ok: false, text: error.message });
      return;
    }
    setNote("");
    load();
  }

  // A fresh one-time set-password link; if email isn't set up, the link
  // is copied for you to share on WhatsApp.
  async function sendPasswordEmail() {
    const res = await fetch("/api/clients/send-email", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ businessId: id }),
    });
    const json = await res.json().catch(() => ({}));
    if (res.ok && json.sent) {
      setNotice({ ok: true, text: `Set-password email sent to ${json.email}` });
      return;
    }
    if (json.setPasswordLink) {
      try {
        await navigator.clipboard.writeText(json.setPasswordLink);
        setNotice({ ok: true, text: `Email not sent (${json.error ?? "email isn't set up"}). The one-time link is copied — paste it to the owner on WhatsApp.` });
      } catch {
        setNotice({ ok: false, text: `Email not sent. One-time link: ${json.setPasswordLink}` });
      }
      return;
    }
    setNotice({ ok: false, text: json.error || "Couldn't create the link" });
  }

  if (!business) return <Spinner />;

  const expired = subscription && new Date(`${subscription.expiry_date}T23:59:59`) < new Date();
  const status = !business.is_active ? "suspended" : expired ? "expired" : (subscription?.status ?? "none");

  return (
    <div className="max-w-5xl space-y-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <Link href="/clients" className="text-sm text-zinc-500 hover:underline">← Clients</Link>
          <h1 className="text-2xl font-bold text-zinc-900">{business.name}</h1>
          <p className="text-sm text-zinc-500">
            {business.owner_name || "—"} · {businessTypeLabel(business.business_type)} ·{" "}
            {business.onboarding_done === false ? <b className="text-orange-700">setup not finished</b> : "set up"}
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          {business.phone && (
            <>
              <a href={waLink(business.phone, `Namaste ${business.owner_name || ""}! This is SOFTRAXA.`)} target="_blank" rel="noreferrer">
                <Button variant="outline">WhatsApp</Button>
              </a>
              <a href={`tel:${business.phone}`}><Button variant="outline">Call {business.phone}</Button></a>
            </>
          )}
          <Button variant={business.is_active ? "danger" : "primary"} onClick={() => business.is_active ? setConfirmSuspend(true) : toggleActive()}>
            {business.is_active ? "Suspend" : "Activate"}
          </Button>
        </div>
      </div>

      <Notice notice={notice} />

      {claims.length > 0 && (
        <p className="rounded-xl bg-blue-50 px-4 py-3 text-sm text-blue-800">
          This shop reported a payment of {inr(claims[0].amount)} (UTR <span className="font-mono">{claims[0].reference}</span>).
          Verify it on the <Link href="/" className="font-semibold underline">Today</Link> page.
        </p>
      )}

      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <CardBody>
            <div className="mb-3 flex items-center justify-between">
              <h2 className="text-sm font-semibold text-zinc-700">Subscription</h2>
              <Badge color={subscriptionBadge(status)}>{status}</Badge>
            </div>
            <dl className="space-y-2 text-sm">
              <div className="flex justify-between"><dt className="text-zinc-500">Plan</dt><dd>{subscription?.plans?.name ?? "No plan"}</dd></div>
              <div className="flex justify-between"><dt className="text-zinc-500">Expires</dt><dd className={expired ? "font-semibold text-red-600" : ""}>{dateStr(subscription?.expiry_date)}</dd></div>
              <div className="flex justify-between"><dt className="text-zinc-500">Grace days</dt><dd>{subscription?.grace_days ?? 0}</dd></div>
            </dl>
            <div className="mt-4 flex flex-wrap gap-2">
              <Button onClick={() => setRenewOpen(true)}>Renew / record payment</Button>
              <Button variant="outline" onClick={() => setCorrectOpen(true)}>Correct</Button>
            </div>
          </CardBody>
        </Card>

        <Card>
          <CardBody>
            <div className="mb-3 flex items-center justify-between">
              <h2 className="text-sm font-semibold text-zinc-700">Shop</h2>
              <Button variant="ghost" onClick={sendPasswordEmail}>Send set-password link</Button>
            </div>
            <dl className="space-y-2 text-sm">
              <div className="flex justify-between gap-4"><dt className="text-zinc-500">Email</dt><dd className="truncate">{business.email || "—"}</dd></div>
              <div className="flex justify-between gap-4"><dt className="text-zinc-500">GSTIN</dt><dd>{business.gst_number || "—"}</dd></div>
              <div className="flex justify-between gap-4"><dt className="text-zinc-500">Joined</dt><dd>{dateStr(business.created_at)}</dd></div>
              <div className="flex justify-between gap-4"><dt className="text-zinc-500">Last bill</dt><dd>{usage?.lastBill ? dateTimeStr(usage.lastBill) : "never"}</dd></div>
              <div className="flex justify-between gap-4"><dt className="text-zinc-500">Bills in 30 days</dt><dd className={usage && usage.bills30 === 0 ? "font-semibold text-orange-700" : ""}>{usage?.bills30 ?? "…"}</dd></div>
              <div className="flex justify-between gap-4"><dt className="text-zinc-500">Bills / products (all time)</dt><dd>{usage ? `${usage.invoices} / ${usage.products}` : "…"}</dd></div>
              <div className="flex justify-between gap-4"><dt className="text-zinc-500">Users</dt><dd>{usage?.staff ?? "…"} / {subscription?.plans?.user_limit ?? "unlimited"}</dd></div>
            </dl>
          </CardBody>
        </Card>

        <Card>
          <CardBody>
            <h2 className="mb-1 text-sm font-semibold text-zinc-700">Payments</h2>
            <ul className="divide-y divide-zinc-100 text-sm">
              {payments.map((p) => (
                <li key={p.id} className="flex items-center justify-between gap-3 py-2">
                  <span>
                    {dateStr(p.payment_date)} · {p.payment_mode === "other" ? "bank" : p.payment_mode}
                    {p.reference ? <span className="font-mono text-xs text-zinc-500"> · {p.reference}</span> : null}
                  </span>
                  <span className="flex items-center gap-3">
                    <b>{inr(p.amount)}</b>
                    {p.receipt_no && <Link href={`/payments/${p.id}`} className="text-xs font-medium text-brand hover:underline">{p.receipt_no}</Link>}
                  </span>
                </li>
              ))}
              {payments.length === 0 && <li className="py-2 text-zinc-500">No payments yet.</li>}
            </ul>
          </CardBody>
        </Card>

        <Card>
          <CardBody>
            <h2 className="mb-2 text-sm font-semibold text-zinc-700">Features</h2>
            <p className="mb-2 text-xs text-zinc-500">Set by the plan. Change one only as an exception — it&apos;s logged.</p>
            {FEATURES.map(([key, label]) => (
              <Toggle key={key} label={label} checked={flags?.[key] ?? true} onChange={(v) => toggleFlag(key, v)} />
            ))}
          </CardBody>
        </Card>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <CardBody>
            <h2 className="mb-2 text-sm font-semibold text-zinc-700">Your notes — only you see these</h2>
            <div className="mb-3 flex gap-2">
              <Input value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. prefers calls after 8 pm" />
              <Button variant="outline" onClick={addNote} disabled={!note.trim()}>Add</Button>
            </div>
            <ul className="space-y-2 text-sm">
              {notes.map((n) => (
                <li key={n.id}><span className="text-xs text-zinc-400">{dateStr(n.created_at)}</span> · {n.note}</li>
              ))}
              {notes.length === 0 && <li className="text-zinc-500">No notes yet.</li>}
            </ul>
          </CardBody>
        </Card>

        <Card>
          <CardBody>
            <div className="mb-2 flex items-center justify-between">
              <h2 className="text-sm font-semibold text-zinc-700">Support requests</h2>
              <Link href="/support" className="text-xs font-medium text-brand hover:underline">Open support</Link>
            </div>
            <ul className="divide-y divide-zinc-100 text-sm">
              {tickets.map((t) => {
                const waiting = t.status !== "resolved" &&
                  (!t.last_reply_at || new Date(t.last_shop_message_at ?? t.created_at) > new Date(t.last_reply_at));
                return (
                  <li key={t.id} className="flex items-center justify-between gap-3 py-2">
                    <span className="min-w-0 truncate">{t.subject}</span>
                    <Badge color={t.status === "resolved" ? "green" : waiting ? "red" : "orange"}>
                      {t.status === "resolved" ? "resolved" : waiting ? "needs reply" : "waiting on shop"}
                    </Badge>
                  </li>
                );
              })}
              {tickets.length === 0 && <li className="py-2 text-zinc-500">No support requests.</li>}
            </ul>
          </CardBody>
        </Card>

        <Card>
          <CardBody>
            <h2 className="mb-2 text-sm font-semibold text-zinc-700">Users ({staff.length})</h2>
            <ul className="divide-y divide-zinc-100 text-sm">
              {staff.map((p) => (
                <li key={p.id} className="flex items-center justify-between gap-3 py-2">
                  <span className="min-w-0 truncate">{p.full_name || p.email || "—"}</span>
                  <Badge color={p.role === "owner" ? "purple" : "zinc"}>{p.role}</Badge>
                </li>
              ))}
            </ul>
          </CardBody>
        </Card>

        <Card>
          <CardBody>
            <div className="mb-2 flex items-center justify-between">
              <h2 className="text-sm font-semibold text-zinc-700">Stock and balance check</h2>
              <Link href="/reconciliation" className="text-xs font-medium text-brand hover:underline">Reconciliation</Link>
            </div>
            <ul className="divide-y divide-zinc-100 text-sm">
              {issues.map((i) => (
                <li key={i.id} className="py-2">
                  <span className="font-medium">{i.entity_label}</span>
                  <span className="block text-xs text-zinc-500">
                    {i.check_name.replace(/_/g, " ")}: should be {i.expected}, stored {i.actual}
                    {i.explained_note ? " · explained: " + i.explained_note : ""}
                  </span>
                </li>
              ))}
              {issues.length === 0 && <li className="py-2 text-emerald-700">No mismatches in the last nightly check.</li>}
            </ul>
          </CardBody>
        </Card>
      </div>

      <Card>
        <CardBody>
          <h2 className="mb-2 text-sm font-semibold text-zinc-700">History</h2>
          <ul className="divide-y divide-zinc-100 text-sm">
            {history.map((h) => (
              <li key={h.id} className="flex flex-col gap-0.5 py-2 sm:flex-row sm:justify-between">
                <span className="font-medium">{ACTION_LABELS[h.action] ?? h.action}</span>
                <span className="text-xs text-zinc-500">
                  {h.details?.reason ? `${h.details.reason} · ` : ""}
                  {h.details?.to ? `to ${dateStr(h.details.to)} · ` : ""}
                  {h.details?.amount ? `${inr(h.details.amount)} · ` : ""}
                  {dateTimeStr(h.created_at)}
                </span>
              </li>
            ))}
            {history.length === 0 && <li className="py-2 text-zinc-500">No changes recorded yet.</li>}
          </ul>
        </CardBody>
      </Card>

      {renewOpen && (
        <RenewDialog
          target={{ businessId: id, name: business.name, phone: business.phone, planId: subscription?.plan_id, expiry: subscription?.expiry_date }}
          onClose={() => setRenewOpen(false)}
          onDone={load}
        />
      )}
      {correctOpen && (
        <CorrectDialog
          businessId={id}
          subscription={subscription}
          plans={plans}
          onClose={() => setCorrectOpen(false)}
          onDone={(text) => { setCorrectOpen(false); setNotice({ ok: true, text }); load(); }}
        />
      )}
      {confirmSuspend && (
        <Modal title={`Suspend ${business.name}?`} onClose={() => setConfirmSuspend(false)}>
          <p className="mb-4 text-sm text-zinc-600">
            The shop and its staff are blocked from the app at once — they can&apos;t bill. Their data is kept, and the
            owner can still export it. Use this for non-payment after reminders, or abuse.
          </p>
          <div className="flex justify-end gap-2">
            <Button variant="ghost" onClick={() => setConfirmSuspend(false)}>Cancel</Button>
            <Button variant="danger" onClick={toggleActive}>Suspend now</Button>
          </div>
        </Modal>
      )}
    </div>
  );
}

/** Fix a mistake in the subscription (not a renewal) — needs a reason. */
function CorrectDialog({
  businessId, subscription, plans, onClose, onDone,
}: {
  businessId: string;
  subscription: any;
  plans: any[];
  onClose: () => void;
  onDone: (text: string) => void;
}) {
  const [planId, setPlanId] = useState(subscription?.plan_id ?? "");
  const [status, setStatus] = useState(subscription?.status === "suspended" ? "active" : subscription?.status ?? "trial");
  const [expiry, setExpiry] = useState(subscription?.expiry_date ?? "");
  const [grace, setGrace] = useState(String(subscription?.grace_days ?? 0));
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function save() {
    setBusy(true);
    setError(null);
    const { error } = await createClient().rpc("admin_update_subscription", {
      p_business: businessId,
      p_plan: planId || null,
      p_status: status,
      p_expiry: expiry,
      p_grace: Number(grace) || 0,
      p_reason: reason.trim(),
    });
    setBusy(false);
    if (error) return setError(error.message);
    onDone("Subscription corrected — the change and your reason are in History.");
  }

  return (
    <Modal title="Correct subscription" onClose={onClose}>
      <div className="space-y-3">
        <p className="text-sm text-zinc-500">For fixing mistakes. To take a payment, use Renew instead.</p>
        <div>
          <Label>Plan</Label>
          <Select value={planId} onChange={(e) => setPlanId(e.target.value)}>
            <option value="">No plan</option>
            {plans.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </Select>
        </div>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <div>
            <Label>Status</Label>
            <Select value={status} onChange={(e) => setStatus(e.target.value)}>
              <option value="trial">Trial</option>
              <option value="active">Active (paid)</option>
              <option value="expired">Expired</option>
            </Select>
          </div>
          <div>
            <Label>Expiry</Label>
            <Input type="date" value={expiry} onChange={(e) => setExpiry(e.target.value)} />
          </div>
          <div>
            <Label>Grace days</Label>
            <Input type="number" min={0} max={90} value={grace} onChange={(e) => setGrace(e.target.value)} />
          </div>
        </div>
        <div>
          <Label>Reason *</Label>
          <Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. entered the wrong year" />
        </div>
        {error && <p className="text-sm font-medium text-red-600">{error}</p>}
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button onClick={save} disabled={busy || !reason.trim() || !expiry}>{busy ? "Saving…" : "Save correction"}</Button>
        </div>
      </div>
    </Modal>
  );
}
