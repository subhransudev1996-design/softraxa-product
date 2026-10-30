"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Banknote, Check, Copy, Loader2, LogOut } from "lucide-react";
import { signOut } from "@/lib/shop-session";
import { rupees } from "@/lib/site-info";
import { supabase } from "@/lib/supabase-client";
import { btnGhost, btnPrimary, eyebrow } from "@/lib/ui";

/* dukania.in/partner/me (migration 0107): the signed-in partner's numbers,
   their UPI ID for payouts and their password. Counts and money only. */

type Stats = {
  name: string; code: string; active: boolean; buyer_off_pct: number; rule: string; hold_days: number;
  clicks: number; signups: number; paid_shops: number; earned: number; held: number; payable: number; paid: number;
  upi_id: string; email: string; on_trial: number; trial_ended: number; code_uses: number; min_payout: number;
  payout_request: { amount: number; upi_id: string; at: string } | null;
  last_declined: { amount: number; reason: string; at: string } | null;
  has_pan: boolean; pan_last4: string | null; tds: number;
  purchases: { day: string; kind: string; plan: string; paid: number; commission: number; payable_on: string; status: string }[];
  months: { month: string; clicks: number; signups: number; paid_shops: number; earned: number }[];
  payouts: { paid_on: string; amount: number; tds: number; reference: string }[];
};

const money = (n: number) => (n < 0 ? `−${rupees(Math.abs(n))}` : rupees(n));
const monthName = (d: string) => new Date(`${d}T00:00:00`).toLocaleDateString("en-IN", { month: "short", year: "numeric" });
const dayName = (d: string) => new Date(`${d}T00:00:00`).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" });

export default function PartnerMeClient() {
  const router = useRouter();
  const [s, setS] = useState<Stats | null>(null);
  const [upi, setUpi] = useState("");
  const [pass, setPass] = useState("");
  const [pan, setPan] = useState("");
  const [note, setNote] = useState<{ ok: boolean; text: string } | null>(null);
  const [copied, setCopied] = useState(false);
  const [asking, setAsking] = useState(false);
  const [payoutError, setPayoutError] = useState<string | null>(null);

  useEffect(() => {
    let live = true;
    supabase.rpc("my_partner").then(({ data }) => {
      if (!live) return;
      if (!data) return router.replace("/partner/login");
      setS(data as Stats);
      setUpi((data as Stats).upi_id ?? "");
    });
    return () => { live = false; };
  }, [router]);

  if (!s) return <p className="flex items-center gap-2 text-sm text-dim"><Loader2 className="h-4 w-4 animate-spin" /> Loading your numbers…</p>;
  const link = `https://www.dukania.in/r/${s.code}`;

  async function saveUpi(e: React.FormEvent) {
    e.preventDefault();
    const { error } = await supabase.rpc("my_partner_set_upi", { p_upi: upi });
    if (!error && s) setS({ ...s, upi_id: upi.trim() });
    setNote(error ? { ok: false, text: error.message } : { ok: true, text: "UPI ID saved. Your next payment goes here." });
  }

  async function savePan(e: React.FormEvent) {
    e.preventDefault();
    const { data, error } = await supabase.rpc("my_partner_set_pan", { p_pan: pan });
    if (!error && s) {
      setS({ ...s, has_pan: true, pan_last4: String(data) });
      setPan("");
    }
    setNote(error ? { ok: false, text: error.message } : { ok: true, text: "PAN saved." });
  }

  async function requestPayout() {
    setAsking(true);
    setPayoutError(null);
    const { data, error } = await supabase.rpc("my_partner_request_payout");
    setAsking(false);
    if (error) return setPayoutError(error.message);
    if (s) setS({ ...s, last_declined: null, payout_request: { ...(data as { amount: number; upi_id: string }), at: new Date().toISOString() } });
  }

  async function savePassword(e: React.FormEvent) {
    e.preventDefault();
    if (pass.length < 8) return setNote({ ok: false, text: "Use at least 8 characters for your password." });
    const { error } = await supabase.auth.updateUser({ password: pass });
    if (!error) setPass("");
    setNote(error ? { ok: false, text: error.message } : { ok: true, text: "Password changed." });
  }

  async function copy() {
    try {
      await navigator.clipboard.writeText(link);
      setCopied(true);
    } catch {
      setCopied(false);
    }
  }

  async function logout() {
    await signOut();
    router.replace("/partner/login");
  }

  const cards: [string, string, string?][] = [
    ["Link clicks", String(s.clicks)],
    ["Shops joined", String(s.signups), "with your link or code"],
    ["Shops that paid", String(s.paid_shops)],
    ["Earned", money(Number(s.earned))],
    ["To be paid", money(Number(s.payable)), Number(s.held) > 0 ? `+ ${money(Number(s.held))} after the ${s.hold_days}-day wait` : undefined],
    ["Paid to you", money(Number(s.paid)), Number(s.tds) > 0 ? `includes ${money(Number(s.tds))} TDS` : undefined],
  ];
  const payable = Number(s.payable);
  const minPayout = Number(s.min_payout ?? 500);
  const today = new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Kolkata" });
  const funnel: [string, number, string][] = [
    ["Clicks", s.clicks, "on your link"],
    ["Joined", s.signups, "with your link or code"],
    ["On trial now", s.on_trial, "may still buy"],
    ["Purchased", s.paid_shops, "took a plan"],
    ["Trial ended", s.trial_ended, "didn't buy yet"],
  ];
  const field = "min-w-0 flex-1 rounded-xl border border-hairline bg-bg/60 px-4 py-2.5 text-sm text-paper outline-none focus:border-brand focus:bg-white";

  return (
    <div>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className={eyebrow}>Dukania partner</p>
          <h1 className="mt-2 font-display text-3xl font-bold tracking-tight sm:text-4xl">Namaste, {s.name}.</h1>
        </div>
        <button onClick={logout} className={`${btnGhost} sm:hidden`}><LogOut className="h-4 w-4" /> Log out</button>
      </div>
      <p className="mt-3 text-dim">
        Your code <b className="font-mono text-paper">{s.code}</b>
        {Number(s.buyer_off_pct) > 0 ? <> gives shops {Number(s.buyer_off_pct)}% off</> : null}. You earn {s.rule}, paid {s.hold_days > 0 ? `${s.hold_days} days after the shop pays` : "after the shop pays"}.
        {!s.active && <b className="text-red-700"> Your code is switched off right now.</b>}
      </p>
      <button onClick={copy} className="mt-3 inline-flex max-w-full items-center gap-2 rounded-xl border border-hairline bg-white px-3 py-2 text-sm font-semibold text-paper hover:border-brand/40">
        {copied ? <Check className="h-4 w-4 text-emerald-700" /> : <Copy className="h-4 w-4 text-brand" />}
        <span className="truncate">{link.replace("https://www.", "")}</span>
      </button>

      <ul className="mt-8 grid grid-cols-2 gap-4 md:grid-cols-3">
        {cards.map(([label, value, hint]) => (
          <li key={label} className="rounded-2xl border border-hairline bg-white p-5 shadow-card">
            <p className="text-xs font-semibold uppercase tracking-wider text-dim">{label}</p>
            <p className="mt-1 font-display text-2xl font-bold text-paper sm:text-3xl">{value}</p>
            {hint && <p className="mt-1 text-xs text-dim">{hint}</p>}
          </li>
        ))}
      </ul>

      {/* Asking to be paid */}
      <div className="mt-6 rounded-2xl border border-hairline bg-white p-5 shadow-card">
        {s.last_declined && (
          <p className="mb-4 rounded-xl bg-red-50 px-4 py-3 text-sm text-red-800">
            <b>Your request for {money(Number(s.last_declined.amount))} wasn&apos;t paid:</b> {s.last_declined.reason}. Your money is still here, and you can ask again.
          </p>
        )}
        {s.payout_request ? (
          <p className="flex items-start gap-3 text-sm text-paper">
            <Check className="mt-0.5 h-5 w-5 shrink-0 text-emerald-700" />
            <span><b>Payout requested: {money(Number(s.payout_request.amount))}</b> to <span className="font-mono">{s.payout_request.upi_id}</span>. Dukania will pay you soon, and it will show under Payments to you.</span>
          </p>
        ) : (
          <div className="flex flex-wrap items-center justify-between gap-4">
            <div>
              <p className="font-semibold text-paper">{payable >= minPayout && payable > 0 ? `${money(payable)} is ready for you` : "Payout"}</p>
              <p className="text-sm text-dim">
                {!s.upi_id ? "Add your UPI ID below first." : payable >= minPayout && payable > 0 ? `We'll pay it to ${s.upi_id}.` : `You can ask once ${rupees(minPayout)} or more is ready to be paid.`}
              </p>
              {payoutError && <p className="mt-1 text-sm font-medium text-red-700">{payoutError}</p>}
            </div>
            <button onClick={requestPayout} disabled={asking || !s.upi_id || payable <= 0 || payable < minPayout}
              className={`${btnPrimary} disabled:cursor-not-allowed disabled:opacity-50`}>
              {asking ? <Loader2 className="h-4 w-4 animate-spin" /> : <Banknote className="h-4 w-4" />} Request payout
            </button>
          </div>
        )}
      </div>

      {/* The funnel */}
      <h2 className="mt-12 font-display text-xl font-bold">From click to sale</h2>
      <ol className="mt-4 grid grid-cols-2 gap-px overflow-hidden rounded-2xl border border-hairline bg-hairline shadow-card sm:grid-cols-3 lg:grid-cols-5">
        {funnel.map(([label, value, hint]) => (
          <li key={label} className="bg-white p-4 last:col-span-2 lg:last:col-span-1">
            <p className="font-display text-2xl font-bold tabular-nums text-paper">{value}</p>
            <p className="text-sm font-semibold text-paper">{label}</p>
            <p className="text-xs text-dim">{hint}</p>
          </li>
        ))}
      </ol>
      <p className="mt-2 text-xs text-dim">Your code was used on {s.code_uses} payment{Number(s.code_uses) === 1 ? "" : "s"}. Clicks count one person once a day.</p>

      {/* Each sale */}
      <h2 className="mt-12 font-display text-xl font-bold">Your sales</h2>
      {s.purchases.length === 0 ? (
        <p className="mt-3 text-sm text-dim">No sales yet. They show here as soon as a shop pays.</p>
      ) : (
        <ul className="mt-4 divide-y divide-hairline rounded-2xl border border-hairline bg-white shadow-card">
          {s.purchases.map((c, i) => {
            const label = c.status === "paid" ? "Paid to you" : c.status === "cancelled" ? "Refunded" : c.payable_on > today ? `Payable from ${dayName(c.payable_on)}` : "Ready to pay";
            return (
              <li key={i} className="flex items-start justify-between gap-4 px-4 py-3 text-sm">
                <span>
                  <span className="block font-medium text-paper">{c.kind === "refund" ? `Refund · ${c.plan}` : c.plan || "Plan"}</span>
                  <span className="block text-xs text-dim">{dayName(c.day)} · shop paid {money(Number(c.paid))} · {label}</span>
                </span>
                <b className={`tabular-nums ${Number(c.commission) < 0 || c.status === "cancelled" ? "text-red-700" : "text-paper"}`}>{money(Number(c.commission))}</b>
              </li>
            );
          })}
        </ul>
      )}

      <h2 className="mt-12 font-display text-xl font-bold">Last 6 months</h2>
      <div className="mt-4 overflow-x-auto rounded-2xl border border-hairline bg-white shadow-card">
        <table className="w-full min-w-[480px] text-sm">
          <thead className="bg-elevated/60 text-left text-xs uppercase tracking-wider text-dim">
            <tr><th className="px-4 py-3">Month</th><th className="px-4 py-3">Clicks</th><th className="px-4 py-3">Joined</th><th className="px-4 py-3">Paid</th><th className="px-4 py-3">Earned</th></tr>
          </thead>
          <tbody className="divide-y divide-hairline">
            {s.months.map((m) => (
              <tr key={m.month}>
                <td className="px-4 py-3 font-semibold">{monthName(m.month)}</td>
                <td className="px-4 py-3 tabular-nums">{m.clicks}</td>
                <td className="px-4 py-3 tabular-nums">{m.signups}</td>
                <td className="px-4 py-3 tabular-nums">{m.paid_shops}</td>
                <td className="px-4 py-3 tabular-nums">{money(Number(m.earned))}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h2 className="mt-12 font-display text-xl font-bold">Payments to you</h2>
      {s.payouts.length === 0 ? (
        <p className="mt-3 text-sm text-dim">No payments yet.</p>
      ) : (
        <ul className="mt-4 divide-y divide-hairline rounded-2xl border border-hairline bg-white shadow-card">
          {s.payouts.map((o, i) => (
            <li key={i} className="flex justify-between px-4 py-3 text-sm">
              <span>{dayName(o.paid_on)}{o.reference ? <span className="text-dim"> · ref …{o.reference}</span> : null}</span>
              <span className="text-right">
                <b className="tabular-nums">{money(Number(o.amount) - Number(o.tds ?? 0))}</b>
                {Number(o.tds) > 0 && <span className="block text-xs text-dim">{money(Number(o.amount))} less {money(Number(o.tds))} TDS</span>}
              </span>
            </li>
          ))}
        </ul>
      )}

      <h2 className="mt-12 font-display text-xl font-bold">Your details</h2>
      {note && <p className={`mt-3 text-sm font-medium ${note.ok ? "text-emerald-700" : "text-red-700"}`}>{note.text}</p>}
      <div className="mt-4 grid grid-cols-1 gap-4 md:grid-cols-2">
        <form onSubmit={saveUpi} className="rounded-2xl border border-hairline bg-white p-5 shadow-card">
          <p className="font-semibold text-paper">UPI ID for your payments</p>
          <div className="mt-3 flex gap-2">
            <input value={upi} onChange={(e) => setUpi(e.target.value)} placeholder="name@okaxis" aria-label="UPI ID" className={field} />
            <button type="submit" className="rounded-xl bg-brand px-4 text-sm font-semibold text-white hover:bg-brand-2">Save</button>
          </div>
        </form>
        <form onSubmit={savePan} className="rounded-2xl border border-hairline bg-white p-5 shadow-card">
          <p className="font-semibold text-paper">PAN</p>
          <p className="text-xs text-dim">{s.has_pan ? `Saved, ending ${s.pan_last4}. Enter it again to change it.` : "Needed for tax. Without it, more TDS may be held once your earnings are high enough."}</p>
          <div className="mt-3 flex gap-2">
            <input value={pan} onChange={(e) => setPan(e.target.value.toUpperCase())} maxLength={10} placeholder="ABCDE1234F" aria-label="PAN" className={`${field} font-mono`} />
            <button type="submit" disabled={!pan.trim()} className="rounded-xl bg-brand px-4 text-sm font-semibold text-white hover:bg-brand-2 disabled:opacity-50">Save</button>
          </div>
        </form>
        <form onSubmit={savePassword} className="rounded-2xl border border-hairline bg-white p-5 shadow-card">
          <p className="font-semibold text-paper">Change password</p>
          <p className="text-xs text-dim">{s.email}</p>
          <div className="mt-3 flex gap-2">
            <input type="password" autoComplete="new-password" value={pass} onChange={(e) => setPass(e.target.value)} placeholder="New password" aria-label="New password" className={field} />
            <button type="submit" className="rounded-xl bg-brand px-4 text-sm font-semibold text-white hover:bg-brand-2">Save</button>
          </div>
        </form>
      </div>
    </div>
  );
}
