"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Button, Input, Label, Select } from "@/components/ui";
import { Modal, waLink } from "@/components/ops";
import { dateStr, inr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */

export type SaleTarget = {
  businessId: string;
  name: string;
  phone?: string | null;
  planId?: string | null;
  expiry?: string | null;
  status?: string | null;
};

const today = () => new Date().toISOString().slice(0, 10);
const plusYear = (from: string) => {
  const d = new Date(from);
  d.setFullYear(d.getFullYear() + 1);
  return d.toISOString().slice(0, 10);
};

function PayFields({
  mode, setMode, reference, setReference, payDate, setPayDate, note, setNote,
}: {
  mode: string; setMode: (v: string) => void;
  reference: string; setReference: (v: string) => void;
  payDate: string; setPayDate: (v: string) => void;
  note: string; setNote: (v: string) => void;
}) {
  return (
    <>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <div>
          <Label>Paid by</Label>
          <Select value={mode} onChange={(e) => setMode(e.target.value)}>
            <option value="upi">UPI</option>
            <option value="cash">Cash</option>
            <option value="other">Bank transfer</option>
            <option value="card">Card</option>
          </Select>
        </div>
        <div>
          <Label>UPI / bank reference</Label>
          <Input value={reference} onChange={(e) => setReference(e.target.value)} placeholder="12-digit UTR" className="font-mono" />
        </div>
        <div>
          <Label>Payment date</Label>
          <Input type="date" value={payDate} onChange={(e) => setPayDate(e.target.value)} />
        </div>
      </div>
      <div>
        <Label>Note (optional)</Label>
        <Input value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. Diwali offer, paid by owner's son" />
      </div>
    </>
  );
}

/**
 * Sell or renew a plan with its add-ons in one step (admin_record_sale,
 * migration 0096): the plan's list and website prices, your lowest price,
 * and what the shop actually paid.
 */
export function SaleDialog({ target, onClose, onDone }: { target: SaleTarget; onClose: () => void; onDone: () => void }) {
  const [plans, setPlans] = useState<any[]>([]);
  const [discount, setDiscount] = useState(20);
  const [planId, setPlanId] = useState(target.planId ?? "");
  const [staff, setStaff] = useState("0");
  const [ai, setAi] = useState(false);
  const [amount, setAmount] = useState("");
  const [amountTouched, setAmountTouched] = useState(false);
  const [mode, setMode] = useState("upi");
  const [reference, setReference] = useState("");
  const [payDate, setPayDate] = useState(today());
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<any>(null);

  useEffect(() => {
    const db = createClient();
    db.from("plans").select("*").eq("is_active", true).gt("list_price", 0).order("sort_order")
      .then(({ data }) => {
        setPlans(data ?? []);
        if (!(data ?? []).some((p) => p.id === planId)) setPlanId(data?.[0]?.id ?? "");
      });
    db.from("platform_settings").select("website_discount_pct").eq("id", 1).maybeSingle()
      .then(({ data }) => data && setDiscount(Number(data.website_discount_pct)));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const plan = plans.find((p) => p.id === planId);
  const hasAi = Array.isArray(plan?.included_features) && plan.included_features.includes("ai_assistant");
  const aiOffered = plan && !hasAi && Number(plan.ai_addon_price) > 0;
  const nStaff = Math.max(0, Math.floor(Number(staff) || 0));
  const addons = plan ? nStaff * Number(plan.extra_staff_price) + (ai && aiOffered ? Number(plan.ai_addon_price) : 0) : 0;
  const listTotal = plan ? Number(plan.list_price) + addons : 0;
  // The discount is on the plan; add-ons are charged at their price.
  const webTotal = plan ? Math.round(Number(plan.list_price) * (1 - discount / 100)) + addons : 0;
  const lowest = plan ? Number(plan.lowest_price) + addons : 0;
  const shownAmount = amountTouched ? amount : plan ? String(webTotal) : "";
  const amountNum = Number(shownAmount || 0);
  const lifetime = plan?.billing === "lifetime";
  const renewing = target.status === "active" && target.expiry && target.expiry >= today();
  const until = lifetime ? null : plusYear(renewing ? (target.expiry as string) : today());

  async function submit() {
    setError(null);
    if (!plan) return setError("Choose the plan");
    if (!(amountNum >= 0)) return setError("Enter the amount received");
    if (amountNum > 0 && mode !== "cash" && !reference.trim()) {
      return setError("Enter the UPI/bank reference number, so you can match it later");
    }
    if (amountNum > 0 && amountNum < lowest &&
        !window.confirm(`${inr(amountNum)} is below your lowest price of ${inr(lowest)}. Record it anyway?`)) return;
    setBusy(true);
    const { data, error } = await createClient().rpc("admin_record_sale", {
      p_business: target.businessId,
      p: {
        plan_id: plan.id, extra_staff: nStaff, ai_addon: Boolean(ai && aiOffered),
        amount: amountNum, mode, reference: reference.trim(), payment_date: payDate,
        note: [mode === "other" ? "Bank transfer" : "", note.trim()].filter(Boolean).join(" · "),
      },
    });
    setBusy(false);
    if (error) {
      return setError(error.message.includes("admin_record_sale") ? "Migration 0096 isn't applied to this database yet." : error.message);
    }
    setResult(data);
    onDone();
  }

  if (result) {
    const life = result.billing === "lifetime";
    const extras = [
      result.extra_staff > 0 ? `${result.extra_staff} extra staff login${result.extra_staff > 1 ? "s" : ""}` : "",
      result.ai_addon ? "AI assistant" : "",
    ].filter(Boolean).join(" + ");
    const msg =
      `Namaste! Payment of ${inr(amountNum)} received for ${target.name}. ` +
      `Your Dukania plan: ${result.plan}${extras ? ` with ${extras}` : ""}, ` +
      (life ? "for life." : `active until ${dateStr(result.expiry_date)}.`) +
      (result.receipt_no ? ` Receipt ${result.receipt_no}.` : "") +
      " Thank you — Dukania";
    return (
      <Modal title="Sale recorded" onClose={onClose}>
        <div className="space-y-4 text-sm">
          <p>
            <b>{target.name}</b> is on <b>{result.plan}</b>
            {life ? " for life" : <> until <b>{dateStr(result.expiry_date)}</b></>}
            {extras ? ` with ${extras}` : ""}.
          </p>
          <p className="text-zinc-600">
            List {inr(result.list_total)} · paid {inr(result.paid)}
            {Number(result.discount) > 0 ? ` · discount ${inr(result.discount)}` : ""}
          </p>
          {result.below_lowest && (
            <p className="rounded-xl bg-amber-50 px-4 py-3 text-amber-800">Recorded below your lowest price.</p>
          )}
          <div className="flex flex-wrap gap-2">
            <a href={waLink(target.phone, msg)} target="_blank" rel="noreferrer"><Button>Send on WhatsApp</Button></a>
            {result.payment_id && (
              <Link href={`/payments/${result.payment_id}`}><Button variant="outline">Receipt {result.receipt_no}</Button></Link>
            )}
            <Button variant="ghost" onClick={onClose}>Done</Button>
          </div>
        </div>
      </Modal>
    );
  }

  return (
    <Modal title={`Record a sale — ${target.name}`} onClose={onClose} wide>
      <div className="space-y-4">
        {plans.length === 0 ? (
          <p className="text-sm text-zinc-600">
            No plan has a list price yet. Set prices on the <Link href="/plans" className="text-brand hover:underline">Plans</Link> page.
          </p>
        ) : (
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
            {plans.map((p) => (
              <button key={p.id} type="button" onClick={() => { setPlanId(p.id); setAi(false); }}
                className={`rounded-xl border p-3 text-left ${p.id === planId ? "border-brand bg-brand-tint" : "border-zinc-200 hover:bg-zinc-50"}`}>
                <span className="block font-semibold text-ink">{p.name}</span>
                <span className="block text-xs text-zinc-500">
                  {inr(p.list_price)} {p.billing === "lifetime" ? "once" : "a year"} · {p.user_limit ?? "∞"} logins
                </span>
              </button>
            ))}
          </div>
        )}

        {plan && (
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <div>
              <Label>Extra staff logins ({inr(plan.extra_staff_price)} each a year)</Label>
              <Input type="number" min={0} max={50} value={staff} onChange={(e) => setStaff(e.target.value)} />
              <p className="mt-1 text-xs text-zinc-500">
                Plan gives {plan.user_limit ?? "unlimited"} logins (owner + {plan.user_limit ? plan.user_limit - 1 : "any"} staff)
                {nStaff > 0 ? `; with these: ${Number(plan.user_limit) + nStaff}` : ""}.
              </p>
            </div>
            {aiOffered ? (
              <label className="flex items-start gap-2.5 rounded-xl border border-zinc-200 p-3 text-sm">
                <input type="checkbox" checked={ai} onChange={(e) => setAi(e.target.checked)} className="mt-1" />
                <span>
                  <span className="font-semibold text-ink">AI assistant add-on</span>
                  <span className="block text-xs text-zinc-500">{inr(plan.ai_addon_price)} a year (ChatGPT / Claude)</span>
                </span>
              </label>
            ) : (
              <p className="rounded-xl bg-zinc-50 p-3 text-xs text-zinc-500">
                {hasAi ? "AI assistant is included in this plan." : "This plan has no AI add-on."}
              </p>
            )}
          </div>
        )}

        {plan && (
          <div className="grid grid-cols-3 gap-2 rounded-xl bg-zinc-50 p-3 text-center text-sm">
            <div><span className="block text-xs text-zinc-500">List</span><b className="tabular-nums">{inr(listTotal)}</b></div>
            <div><span className="block text-xs text-zinc-500">Website ({discount}% off)</span><b className="tabular-nums text-brand">{inr(webTotal)}</b></div>
            <div><span className="block text-xs text-zinc-500">Your lowest</span><b className="tabular-nums text-amber-700">{inr(lowest)}</b></div>
          </div>
        )}

        <div>
          <Label>Amount received ₹</Label>
          <Input type="number" min={0} step="1" value={shownAmount}
            onChange={(e) => { setAmountTouched(true); setAmount(e.target.value); }} placeholder="0 = free" />
          {plan && amountNum > 0 && amountNum < lowest && (
            <p className="mt-1 text-xs font-semibold text-red-600">Below your lowest price ({inr(lowest)}).</p>
          )}
        </div>
        <PayFields mode={mode} setMode={setMode} reference={reference} setReference={setReference}
          payDate={payDate} setPayDate={setPayDate} note={note} setNote={setNote} />

        {plan && (
          <div className="rounded-xl bg-zinc-50 px-4 py-3 text-sm text-zinc-700">
            {lifetime ? (
              <>Plan <b>for life</b>{(nStaff > 0 || ai) ? <>; add-ons until <b>{dateStr(plusYear(today()))}</b></> : null}.</>
            ) : (
              <>{renewing ? "Renewal" : "New plan"}: active until <b>{dateStr(until)}</b>{(nStaff > 0 || ai) ? ", add-ons too" : ""}.</>
            )}
          </div>
        )}
        {error && <p className="text-sm font-medium text-red-600">{error}</p>}
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button onClick={submit} disabled={busy || !plan}>
            {busy ? "Saving…" : amountNum > 0 ? `Record ${inr(amountNum)}` : "Save without payment"}
          </Button>
        </div>
      </div>
    </Modal>
  );
}

/**
 * One add-on on its own: an extra staff login mid-year, or a year of AI
 * for a lifetime shop (admin_add_addon, migration 0096).
 */
export function AddonDialog({
  target, plan, onClose, onDone,
}: { target: SaleTarget; plan: any | null; onClose: () => void; onDone: (text: string) => void }) {
  const hasAi = Array.isArray(plan?.included_features) && plan.included_features.includes("ai_assistant");
  const [kind, setKind] = useState<"staff" | "ai">("staff");
  const [qty, setQty] = useState("1");
  const [amount, setAmount] = useState("");
  const [touched, setTouched] = useState(false);
  const [mode, setMode] = useState("upi");
  const [reference, setReference] = useState("");
  const [payDate, setPayDate] = useState(today());
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const n = kind === "ai" ? 1 : Math.max(1, Math.floor(Number(qty) || 1));
  const price = kind === "ai" ? Number(plan?.ai_addon_price ?? 0) : n * Number(plan?.extra_staff_price ?? 0);
  const shown = touched ? amount : price > 0 ? String(price) : amount;
  const amountNum = Number(shown || 0);
  const lifetime = plan?.billing === "lifetime";
  const until = lifetime || !target.expiry || target.expiry < today() ? plusYear(today()) : target.expiry;

  async function submit() {
    setError(null);
    if (amountNum > 0 && mode !== "cash" && !reference.trim()) {
      return setError("Enter the UPI/bank reference number, so you can match it later");
    }
    setBusy(true);
    const { data, error } = await createClient().rpc("admin_add_addon", {
      p_business: target.businessId,
      p: {
        kind, quantity: n, amount: amountNum, mode, reference: reference.trim(), payment_date: payDate,
        note: [mode === "other" ? "Bank transfer" : "", note.trim()].filter(Boolean).join(" · "),
      },
    });
    setBusy(false);
    if (error) return setError(error.message);
    onDone(`${kind === "ai" ? "AI assistant" : `${n} staff login${n > 1 ? "s" : ""}`} added until ${dateStr((data as any)?.valid_until)}.`);
  }

  return (
    <Modal title={`Add-on — ${target.name}`} onClose={onClose}>
      <div className="space-y-4">
        <div className="flex gap-2">
          <button type="button" onClick={() => setKind("staff")}
            className={`rounded-xl border px-4 py-2 text-sm font-semibold ${kind === "staff" ? "border-brand bg-brand-tint text-brand" : "border-zinc-200 text-zinc-600"}`}>
            Extra staff login
          </button>
          {!hasAi && (
            <button type="button" onClick={() => setKind("ai")}
              className={`rounded-xl border px-4 py-2 text-sm font-semibold ${kind === "ai" ? "border-brand bg-brand-tint text-brand" : "border-zinc-200 text-zinc-600"}`}>
              AI assistant
            </button>
          )}
        </div>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          {kind === "staff" && (
            <div>
              <Label>How many logins</Label>
              <Input type="number" min={1} max={50} value={qty} onChange={(e) => setQty(e.target.value)} />
            </div>
          )}
          <div>
            <Label>Amount received ₹</Label>
            <Input type="number" min={0} step="1" value={shown}
              onChange={(e) => { setTouched(true); setAmount(e.target.value); }} placeholder="0 = free" />
          </div>
        </div>
        <PayFields mode={mode} setMode={setMode} reference={reference} setReference={setReference}
          payDate={payDate} setPayDate={setPayDate} note={note} setNote={setNote} />
        <p className="rounded-xl bg-zinc-50 px-4 py-3 text-sm text-zinc-700">
          Valid until <b>{dateStr(until)}</b>{lifetime ? " (one year)" : " (with the plan)"}.
        </p>
        {error && <p className="text-sm font-medium text-red-600">{error}</p>}
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button onClick={submit} disabled={busy}>{busy ? "Saving…" : amountNum > 0 ? `Record ${inr(amountNum)}` : "Add free"}</Button>
        </div>
      </div>
    </Modal>
  );
}
