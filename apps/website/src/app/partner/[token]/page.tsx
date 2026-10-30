import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { rupees } from "@/lib/site-info";
import { supabase } from "@/lib/supabase-client";
import { eyebrow } from "@/lib/ui";

// Fresh numbers on every visit.
export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Your Dukania partner numbers",
  robots: { index: false, follow: false },
};

type Stats = {
  name: string; code: string; active: boolean; buyer_off_pct: number; rule: string; hold_days: number;
  clicks: number; signups: number; paid_shops: number; earned: number; held: number; payable: number; paid: number;
  months: { month: string; clicks: number; signups: number; paid_shops: number; earned: number }[];
  payouts: { paid_on: string; amount: number; tds: number; reference: string }[];
};

const SITE = process.env.NEXT_PUBLIC_SITE_URL || "https://www.dukania.in";
const money = (n: number) => (n < 0 ? `−${rupees(Math.abs(n))}` : rupees(n));
const monthName = (d: string) => new Date(`${d}T00:00:00`).toLocaleDateString("en-IN", { month: "short", year: "numeric" });
const dayName = (d: string) => new Date(`${d}T00:00:00`).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" });

/**
 * An influencer partner's private page (partner_stats, migration 0104),
 * reached by the secret in their link: clicks, shops, commission and
 * payouts. No shop names or phone numbers.
 */
export default async function PartnerStatsPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const { data, error } = await supabase.rpc("partner_stats", { p_token: token });
  if (error || !data) notFound();
  const s = data as Stats;

  const cards: [string, string, string?][] = [
    ["Link clicks", String(s.clicks)],
    ["Shops joined", String(s.signups), "with your link or code"],
    ["Shops that paid", String(s.paid_shops)],
    ["Earned", money(Number(s.earned))],
    ["To be paid", money(Number(s.payable)), Number(s.held) > 0 ? `+ ${money(Number(s.held))} after the ${s.hold_days}-day wait` : undefined],
    ["Paid to you", money(Number(s.paid))],
  ];

  return (
    <section className="mx-auto max-w-5xl px-4 py-12 sm:px-6">
      <p className={eyebrow}>Dukania partner</p>
      <h1 className="mt-2 font-display text-3xl font-bold tracking-tight sm:text-4xl">Namaste, {s.name}.</h1>
      <p className="mt-3 text-dim">
        Your code <b className="font-mono text-paper">{s.code}</b>
        {Number(s.buyer_off_pct) > 0 ? <> gives shops {Number(s.buyer_off_pct)}% off</> : null}. You earn {s.rule}, paid {s.hold_days > 0 ? `${s.hold_days} days after the shop pays` : "after the shop pays"}.
        {!s.active && <b className="text-red-700"> Your code is switched off right now.</b>}
      </p>
      <p className="mt-2 break-all text-sm text-dim">Your link: <b className="text-paper">{SITE.replace(/^https?:\/\//, "")}/r/{s.code}</b></p>

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
              <b className="tabular-nums">{money(Number(o.amount) - Number(o.tds ?? 0))}{Number(o.tds) > 0 ? <span className="font-normal text-dim"> after {money(Number(o.tds))} TDS</span> : null}</b>
            </li>
          ))}
        </ul>
      )}

      <p className="mt-10 text-xs text-dim">
        Keep this page&apos;s link to yourself — anyone with it can see these numbers. If a shop gets a refund, its commission is taken back. Questions? Message Dukania on WhatsApp.
      </p>
    </section>
  );
}
