"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Check, Copy, Loader2, LogOut } from "lucide-react";
import { signOut } from "@/lib/shop-session";
import { rupees } from "@/lib/site-info";
import { supabase } from "@/lib/supabase-client";
import { btnGhost, eyebrow } from "@/lib/ui";

/* dukania.in/partner/me (migration 0107): the signed-in partner's numbers,
   their UPI ID for payouts and their password. Counts and money only. */

type Stats = {
  name: string; code: string; active: boolean; buyer_off_pct: number; rule: string; hold_days: number;
  clicks: number; signups: number; paid_shops: number; earned: number; held: number; payable: number; paid: number;
  upi_id: string; email: string;
  months: { month: string; clicks: number; signups: number; paid_shops: number; earned: number }[];
  payouts: { paid_on: string; amount: number; reference: string }[];
};

const money = (n: number) => (n < 0 ? `−${rupees(Math.abs(n))}` : rupees(n));
const monthName = (d: string) => new Date(`${d}T00:00:00`).toLocaleDateString("en-IN", { month: "short", year: "numeric" });
const dayName = (d: string) => new Date(`${d}T00:00:00`).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" });

export default function PartnerMeClient() {
  const router = useRouter();
  const [s, setS] = useState<Stats | null>(null);
  const [upi, setUpi] = useState("");
  const [pass, setPass] = useState("");
  const [note, setNote] = useState<{ ok: boolean; text: string } | null>(null);
  const [copied, setCopied] = useState(false);

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
    setNote(error ? { ok: false, text: error.message } : { ok: true, text: "UPI ID saved. Your next payment goes here." });
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
    ["Paid to you", money(Number(s.paid))],
  ];
  const field = "min-w-0 flex-1 rounded-xl border border-hairline bg-bg/60 px-4 py-2.5 text-sm text-paper outline-none focus:border-brand focus:bg-white";

  return (
    <div>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className={eyebrow}>Dukania partner</p>
          <h1 className="mt-2 font-display text-3xl font-bold tracking-tight sm:text-4xl">Namaste, {s.name}.</h1>
        </div>
        <button onClick={logout} className={btnGhost}><LogOut className="h-4 w-4" /> Log out</button>
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
              <b className="tabular-nums">{money(Number(o.amount))}</b>
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
