"use client";

import { ReactNode, useEffect, useState } from "react";
import { createPortal } from "react-dom";
import Link from "next/link";
import { X } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { dateStr, inr } from "@/lib/format";
import { Button, Input, Label, Select } from "@/components/ui";

/* eslint-disable @typescript-eslint/no-explicit-any */

/**
 * Dialog over the whole window. Closes with the × button, Escape, or a
 * click on the dark area. The title bar stays put while the content
 * scrolls.
 *
 * Rendered into <body> (a portal): the page content sits inside an
 * animated wrapper, and a transformed ancestor would trap a
 * `position: fixed` dialog inside it — the top, with the close button,
 * ended up off-screen.
 */
export function Modal({
  title,
  onClose,
  children,
  wide = false,
}: {
  title: string;
  onClose: () => void;
  children: ReactNode;
  wide?: boolean;
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    // The page behind must not scroll while the dialog is open.
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = previous;
    };
  }, [onClose]);

  if (typeof document === "undefined") return null;
  return createPortal(
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-ink/50 backdrop-blur-[2px] sm:items-center sm:p-6"
      onMouseDown={(e) => e.target === e.currentTarget && onClose()}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label={title}
        className={`flex max-h-[92dvh] w-full flex-col overflow-hidden rounded-t-2xl bg-white shadow-2xl sm:max-h-[88dvh] sm:rounded-2xl ${wide ? "sm:max-w-2xl" : "sm:max-w-lg"}`}
      >
        <div className="flex shrink-0 items-center justify-between gap-4 border-b border-zinc-100 px-5 py-4">
          <h2 className="min-w-0 truncate text-lg font-bold text-ink">{title}</h2>
          <button
            onClick={onClose}
            aria-label="Close"
            className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-zinc-100 text-zinc-600 transition hover:bg-zinc-200 hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand"
          >
            <X size={18} strokeWidth={2.4} />
          </button>
        </div>
        <div className="overflow-y-auto px-5 py-4">{children}</div>
      </div>
    </div>,
    document.body,
  );
}

/** A short message after an action: green for done, red for a failure. */
export function Notice({ notice }: { notice: { ok: boolean; text: string } | null }) {
  if (!notice) return null;
  return (
    <div
      role="status"
      className={`rounded-xl px-4 py-3 text-sm font-medium ${notice.ok ? "bg-emerald-50 text-emerald-800" : "bg-red-50 text-red-700"}`}
    >
      {notice.text}
    </div>
  );
}

/** wa.me link for an Indian mobile number (10 digits get the 91 prefix). */
export function waLink(phone: string | null | undefined, text: string) {
  let digits = (phone ?? "").replace(/\D/g, "");
  if (digits.length === 10) digits = `91${digits}`;
  return `https://wa.me/${digits}?text=${encodeURIComponent(text)}`;
}

/** Same rule as admin_renew_subscription: from today or the current expiry, whichever is later. */
function nextExpiry(current: string | null | undefined, period: "month" | "year") {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const cur = current ? new Date(`${current}T00:00:00`) : today;
  const base = cur > today ? cur : today;
  const d = new Date(base);
  if (period === "month") d.setMonth(d.getMonth() + 1);
  else d.setFullYear(d.getFullYear() + 1);
  return d.toISOString().slice(0, 10);
}

export type RenewTarget = {
  businessId: string;
  name: string;
  phone?: string | null;
  planId?: string | null;
  expiry?: string | null;
  /** A shop's "I've paid" claim being verified. */
  claim?: { id: string; amount: number; reference: string } | null;
};

type RenewResult = {
  expiry_date: string;
  previous_expiry: string | null;
  payment_id: string | null;
  receipt_no: string | null;
  still_suspended: boolean;
  plan_name: string | null;
};

/**
 * Record a manual payment AND extend the subscription in one step
 * (admin_renew_subscription, migration 0053). Shows the new expiry before
 * confirming, then offers the receipt and a WhatsApp message.
 */
export function RenewDialog({
  target,
  onClose,
  onDone,
}: {
  target: RenewTarget;
  onClose: () => void;
  onDone: () => void;
}) {
  const [plans, setPlans] = useState<any[]>([]);
  const [planId, setPlanId] = useState(target.planId ?? "");
  const [period, setPeriod] = useState<"month" | "year" | "custom">("month");
  const [until, setUntil] = useState("");
  const [amount, setAmount] = useState(target.claim ? String(target.claim.amount) : "");
  const [mode, setMode] = useState("upi");
  const [reference, setReference] = useState(target.claim?.reference ?? "");
  const [payDate, setPayDate] = useState(new Date().toISOString().slice(0, 10));
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<RenewResult | null>(null);
  const [amountTouched, setAmountTouched] = useState(Boolean(target.claim));

  useEffect(() => {
    createClient()
      .from("plans")
      .select("id, name, monthly_price, yearly_price")
      .eq("is_active", true)
      .order("monthly_price")
      .then(({ data }) => setPlans(data ?? []));
  }, []);

  const plan = plans.find((p) => p.id === planId);
  // Suggest the plan's price for the chosen period until the admin types one.
  const suggested = plan ? (period === "year" ? plan.yearly_price : period === "month" ? plan.monthly_price : null) : null;
  const shownAmount = amountTouched ? amount : suggested != null && Number(suggested) > 0 ? String(suggested) : amount;
  const newExpiry = period === "custom" ? until : nextExpiry(target.expiry, period);
  const amountNum = Number(shownAmount || 0);

  async function submit() {
    setError(null);
    if (period === "custom" && !until) return setError("Choose the new expiry date");
    if (!(amountNum >= 0)) return setError("Enter the amount received");
    if (amountNum > 0 && mode !== "cash" && !reference.trim() && !target.claim) {
      return setError("Enter the UPI/bank reference number, so you can match it later");
    }
    setBusy(true);
    const { data, error } = await createClient().rpc("admin_renew_subscription", {
      p_business: target.businessId,
      p_plan: planId || null,
      p_period: period,
      p_until: period === "custom" ? until : null,
      p_amount: amountNum,
      p_mode: mode,
      p_reference: reference.trim(),
      p_payment_date: payDate,
      p_note: note.trim(),
      p_claim: target.claim?.id ?? null,
    });
    setBusy(false);
    if (error) return setError(error.message);
    setResult(data as RenewResult);
    onDone();
  }

  if (result) {
    const msg =
      `Namaste! Payment of ${inr(amountNum)} received for ${target.name}. ` +
      `Your Dukania subscription${result.plan_name ? ` (${result.plan_name})` : ""} is active until ${dateStr(result.expiry_date)}.` +
      (result.receipt_no ? ` Receipt ${result.receipt_no}.` : "") +
      " Thank you — SOFTRAXA";
    return (
      <Modal title="Renewed" onClose={onClose}>
        <div className="space-y-4 text-sm">
          <p>
            <b>{target.name}</b> is active until <b>{dateStr(result.expiry_date)}</b>
            {result.previous_expiry ? ` (was ${dateStr(result.previous_expiry)})` : ""}.
          </p>
          {result.still_suspended && (
            <p className="rounded-xl bg-orange-50 px-4 py-3 text-orange-800">
              This shop is still <b>suspended</b>. Activate it from the client page if they should use the app again.
            </p>
          )}
          <div className="flex flex-wrap gap-2">
            <a href={waLink(target.phone, msg)} target="_blank" rel="noreferrer">
              <Button>Send on WhatsApp</Button>
            </a>
            {result.payment_id && (
              <Link href={`/payments/${result.payment_id}`}>
                <Button variant="outline">Receipt {result.receipt_no}</Button>
              </Link>
            )}
            <Button variant="ghost" onClick={onClose}>Done</Button>
          </div>
        </div>
      </Modal>
    );
  }

  return (
    <Modal title={`Renew — ${target.name}`} onClose={onClose}>
      <div className="space-y-4">
        {target.claim && (
          <p className="rounded-xl bg-blue-50 px-4 py-3 text-sm text-blue-800">
            The shop says it paid <b>{inr(target.claim.amount)}</b> with UPI reference <b className="font-mono">{target.claim.reference}</b>.
            Check your UPI app for this payment before renewing.
          </p>
        )}
        <div>
          <Label>Plan</Label>
          <Select value={planId} onChange={(e) => setPlanId(e.target.value)}>
            <option value="">Keep current plan</option>
            {plans.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name} — {inr(p.monthly_price)}/month, {inr(p.yearly_price)}/year
              </option>
            ))}
          </Select>
        </div>
        <div>
          <Label>Extend by</Label>
          <div className="flex flex-wrap gap-2">
            {(["month", "year", "custom"] as const).map((p) => (
              <button
                key={p}
                type="button"
                onClick={() => setPeriod(p)}
                aria-pressed={period === p}
                className={`rounded-xl border px-4 py-2 text-sm font-semibold ${period === p ? "border-brand bg-brand-tint text-brand" : "border-zinc-200 text-zinc-600"}`}
              >
                {p === "month" ? "1 month" : p === "year" ? "1 year" : "Choose date"}
              </button>
            ))}
          </div>
          {period === "custom" && (
            <Input type="date" value={until} onChange={(e) => setUntil(e.target.value)} className="mt-2" />
          )}
        </div>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div>
            <Label>Amount received ₹</Label>
            <Input
              type="number"
              min={0}
              step="0.01"
              value={shownAmount}
              onChange={(e) => {
                setAmountTouched(true);
                setAmount(e.target.value);
              }}
              placeholder="0 = free extension"
            />
          </div>
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
          <Input value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. paid by owner's son" />
        </div>
        <div className="rounded-xl bg-zinc-50 px-4 py-3 text-sm text-zinc-700">
          Now expires <b>{dateStr(target.expiry)}</b> → will expire <b>{newExpiry ? dateStr(newExpiry) : "—"}</b>
          {amountNum === 0 && <span className="block text-xs text-zinc-500">No payment will be recorded (free extension).</span>}
        </div>
        {error && <p className="text-sm font-medium text-red-600">{error}</p>}
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button onClick={submit} disabled={busy || !newExpiry}>
            {busy ? "Saving…" : amountNum > 0 ? `Record ${inr(amountNum)} & extend` : "Extend"}
          </Button>
        </div>
      </div>
    </Modal>
  );
}
