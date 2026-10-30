"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ArrowRight, ArrowUpRight, CalendarClock, Crown, LogOut, MessageCircle, Plus, Receipt, Sparkles, Users } from "lucide-react";
import { callWithSession, saveToken, signOut, type FnError } from "@/lib/shop-session";
import { rupees } from "@/lib/site-info";
import { supabase } from "@/lib/supabase-client";
import { btnGhost, btnPrimary } from "@/lib/ui";

/* dukania.in/account (migration 0106): the shop's plan and days left,
   logins and add-ons, the upgrades on offer and past payments. Buying
   goes to /pay with the choice made; the app follows by itself. */

type Account = {
  shop: string; email: string; online_payments: boolean;
  plan: null | { name: string; billing: string; is_trial: boolean; includes_ai: boolean; status: string;
    start: string; expiry: string; days_left: number; active: boolean };
  logins: { limit: number | null; used: number };
  addons: { kind: string; quantity: number; valid_until: string }[];
  payments: { payment_date: string; amount: number; receipt_no: string | null; mode: string; plan: string; kind: string; addon: string | null }[];
  upgrades: { plan_id: string; plan: string; billing: string; amount: number; until: string | null }[];
};

const day = (d?: string | null) =>
  d ? new Date(`${d}T00:00:00`).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" }) : "";
const MODE: Record<string, string> = { upi: "UPI", card: "Card", cash: "Cash", other: "Online", credit: "Credit" };

/** "8 months", "23 days", "1 day". */
function left(days: number) {
  if (days >= 60) return `${Math.round(days / 30.4)} months`;
  return `${days} day${days === 1 ? "" : "s"}`;
}

export default function AccountClient({ initialToken, whatsapp }: { initialToken: string | null; whatsapp: string }) {
  const router = useRouter();
  const [state, setState] = useState<{ data?: Account; error?: string } | null>(null);

  useEffect(() => {
    if (initialToken) {
      saveToken(initialToken);
      window.history.replaceState(null, "", "/account");
    }
    let live = true;
    callWithSession("account")
      .then((data) => live && setState({ data }))
      .catch((e: FnError) => {
        if (!live) return;
        if (e.expired) return router.replace("/login?next=/account");
        // A partner has no shop: their page is /partner/me (0107).
        supabase.rpc("my_partner").then(({ data }) => {
          if (!live) return;
          if (data) router.replace("/partner/me");
          else setState({ error: e.message });
        });
      });
    return () => { live = false; };
  }, [initialToken, router]);

  async function logout() {
    await signOut();
    router.replace("/login");
  }

  if (!state) return <Skeleton />;
  if (state.error || !state.data) {
    return (
      <div className="mx-auto max-w-lg rounded-2xl border border-hairline bg-white p-8 text-center shadow-card">
        <p className="font-display text-xl font-bold text-paper">We couldn&apos;t open your account</p>
        <p className="mt-2 text-sm text-dim">{state.error}</p>
        <button onClick={logout} className={`${btnGhost} mt-6`}><LogOut className="h-4 w-4" /> Sign in again</button>
      </div>
    );
  }

  const a = state.data;
  const p = a.plan;
  const wa = whatsapp ? `https://wa.me/${whatsapp}?text=${encodeURIComponent(`Hi, I need help with the Dukania plan for ${a.shop}.`)}` : "";
  const lifetime = Boolean(p && p.billing === "lifetime" && p.active);
  const ended = Boolean(p && p.days_left < 0);
  const soon = Boolean(p && !lifetime && p.days_left >= 0 && p.days_left <= 15);
  const paid = Boolean(p && !p.is_trial);
  const canAdd = Boolean(paid && p?.active);
  const aiAddon = a.addons.find((x) => x.kind === "ai");
  const staffAddons = a.addons.filter((x) => x.kind === "staff");
  // How far through this period, for the bar.
  const total = p ? Math.max(1, (new Date(p.expiry).getTime() - new Date(p.start).getTime()) / 86400000) : 1;
  const used = p ? Math.min(1, Math.max(0, 1 - p.days_left / total)) : 0;
  const go = (what: string) => (a.online_payments ? `/pay?do=${encodeURIComponent(what)}` : wa || "/contact");
  const ext = !a.online_payments && Boolean(wa);

  const tone = !p ? "zinc" : ended ? "red" : soon || p.is_trial ? "amber" : "green";
  const badge = !p ? "No plan" : ended ? (p.is_trial ? "Trial ended" : "Plan ended") : p.is_trial ? "Free trial" : lifetime ? "Lifetime" : soon ? "Renew soon" : "Active";
  const TONES: Record<string, string> = {
    green: "bg-emerald-50 text-emerald-700 ring-emerald-600/20",
    amber: "bg-[#fff8e6] text-amber ring-marigold/40",
    red: "bg-red-50 text-red-700 ring-red-600/20",
    zinc: "bg-elevated text-dim ring-hairline",
  };

  return (
    <div className="space-y-8">
      {/* Who */}
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div className="flex items-center gap-4">
          <span className="inline-flex h-14 w-14 items-center justify-center rounded-2xl bg-paper font-display text-2xl font-bold text-white">
            {a.shop.trim().charAt(0).toUpperCase()}
          </span>
          <div>
            <h1 className="font-display text-3xl font-bold tracking-tight text-paper">{a.shop}</h1>
            <p className="text-sm text-dim">{a.email}</p>
          </div>
        </div>
        {/* The header has Log out on larger screens. */}
        <button onClick={logout} className="inline-flex items-center gap-2 rounded-xl border border-hairline bg-white px-4 py-2.5 text-sm font-semibold text-paper hover:border-brand/40 sm:hidden">
          <LogOut className="h-4 w-4" /> Log out
        </button>
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-[1.5fr_1fr]">
        {/* The plan */}
        <section className="rounded-3xl border border-hairline bg-white p-7 shadow-card">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <p className="font-mono text-[11px] uppercase tracking-[0.2em] text-dim">Your plan</p>
              <h2 className="mt-1 flex items-center gap-2 font-display text-3xl font-bold text-paper">
                {lifetime && <Crown className="h-6 w-6 text-marigold" />} {p?.name ?? "No plan yet"}
              </h2>
            </div>
            <span className={`rounded-full px-3 py-1 text-xs font-bold uppercase tracking-wide ring-1 ring-inset ${TONES[tone]}`}>{badge}</span>
          </div>

          {p && (lifetime ? (
            <p className="mt-6 text-dim">Yours for life — no renewals. Thank you for being with Dukania.</p>
          ) : (
            <div className="mt-6">
              <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between sm:gap-4">
                <p className="whitespace-nowrap">
                  <span className="font-display text-5xl font-bold tabular-nums text-paper">{ended ? "0" : left(p.days_left).split(" ")[0]}</span>
                  <span className="ml-2 text-lg text-dim">{ended ? "days left" : `${left(p.days_left).split(" ")[1]} left`}</span>
                </p>
                <p className="flex items-center gap-1.5 text-sm text-dim sm:text-right">
                  <CalendarClock className="h-4 w-4" /> {ended ? "Ended" : p.is_trial ? "Trial ends" : "Renews"} <b className="text-paper">{day(p.expiry)}</b>
                </p>
              </div>
              <div className="mt-4 h-2.5 overflow-hidden rounded-full bg-elevated">
                <div className={`h-full rounded-full ${ended ? "bg-red-500" : soon || p.is_trial ? "bg-marigold" : "bg-brand"}`} style={{ width: `${Math.round(used * 100)}%` }} />
              </div>
              <p className="mt-2 flex justify-between font-mono text-[11px] text-dim"><span>{day(p.start)}</span><span>{day(p.expiry)}</span></p>
            </div>
          ))}

          {(ended || soon) && !lifetime && (
            <p className="mt-5 rounded-xl border border-marigold/40 bg-[#fff8e6] px-4 py-3 text-sm text-paper">
              {ended
                ? "Billing has stopped in the app. Your data is safe — renew to carry on."
                : p?.is_trial ? "Your free trial ends soon. Take a plan to keep billing without a break."
                : "Your plan ends soon. Renew now — the new year starts after this one ends, you lose no days."}
            </p>
          )}

          <div className="mt-7 flex flex-wrap gap-3">
            {!lifetime && (
              <Link href={go("renew")} target={ext ? "_blank" : undefined} className={btnPrimary}>
                {paid ? "Renew plan" : "Choose a plan"} <ArrowRight className="h-4 w-4" />
              </Link>
            )}
            {a.upgrades.length > 0 && (
              <Link href={go("upgrade")} target={ext ? "_blank" : undefined} className={btnGhost}>Upgrade <ArrowUpRight className="h-4 w-4" /></Link>
            )}
          </div>
        </section>

        {/* Logins and AI */}
        <section className="space-y-6">
          <div className="rounded-3xl border border-hairline bg-white p-6 shadow-card">
            <div className="flex items-start justify-between gap-3">
              <p className="flex items-center gap-2 font-semibold text-paper"><Users className="h-4 w-4 text-brand" /> Logins</p>
              {canAdd && <Link href={go("staff")} target={ext ? "_blank" : undefined} className="inline-flex items-center gap-1 text-sm font-semibold text-brand hover:underline"><Plus className="h-4 w-4" /> Add</Link>}
            </div>
            <p className="mt-3 font-display text-3xl font-bold tabular-nums text-paper">
              {a.logins.used}<span className="text-lg text-dim"> / {a.logins.limit ?? "∞"}</span>
            </p>
            <p className="text-sm text-dim">owner and staff in use</p>
            {staffAddons.length > 0 && (
              <ul className="mt-3 space-y-1 text-xs text-dim">
                {staffAddons.map((s, i) => <li key={i}>+{s.quantity} extra until {day(s.valid_until)}</li>)}
              </ul>
            )}
          </div>

          <div className="rounded-3xl border border-hairline bg-white p-6 shadow-card">
            <div className="flex items-start justify-between gap-3">
              <p className="flex items-center gap-2 font-semibold text-paper"><Sparkles className="h-4 w-4 text-brand" /> AI assistant</p>
              {canAdd && !p?.includes_ai && !aiAddon && (
                <Link href={go("ai")} target={ext ? "_blank" : undefined} className="inline-flex items-center gap-1 text-sm font-semibold text-brand hover:underline"><Plus className="h-4 w-4" /> Add</Link>
              )}
            </div>
            <p className="mt-3 text-sm text-dim">
              {p?.includes_ai ? <>Included in <b className="text-paper">{p.name}</b>.</>
                : aiAddon ? <>On, until <b className="text-paper">{day(aiAddon.valid_until)}</b>.</>
                : "Not on your plan. Run the shop from ChatGPT or Claude."}
            </p>
          </div>
        </section>
      </div>

      {/* Upgrades */}
      {a.upgrades.length > 0 && (
        <section>
          <h2 className="font-display text-xl font-bold text-paper">Upgrade</h2>
          <p className="mt-1 text-sm text-dim">Starts today — you pay only the difference for the time left on {p?.name}.</p>
          <div className="mt-4 grid grid-cols-1 gap-4 md:grid-cols-2">
            {a.upgrades.map((u) => (
              <Link key={u.plan_id} href={go(`upgrade:${u.plan_id}`)} target={ext ? "_blank" : undefined}
                className="group flex items-center justify-between gap-4 rounded-2xl border border-hairline bg-white p-5 shadow-card transition hover:border-brand/50">
                <span>
                  <span className="block font-display text-lg font-bold text-paper">{u.plan}</span>
                  <span className="block text-sm text-dim">{u.billing === "lifetime" ? "Pay once, no more renewals" : `Same renewal date, ${day(u.until)}`}</span>
                </span>
                <span className="text-right">
                  <span className="block font-display text-2xl font-bold tabular-nums text-paper">{rupees(Number(u.amount))}</span>
                  <span className="inline-flex items-center gap-1 text-xs font-semibold text-brand">Upgrade now <ArrowRight className="h-3 w-3 transition group-hover:translate-x-0.5" /></span>
                </span>
              </Link>
            ))}
          </div>
        </section>
      )}

      {/* Payments */}
      <section>
        <h2 className="flex items-center gap-2 font-display text-xl font-bold text-paper"><Receipt className="h-5 w-5 text-brand" /> Payments</h2>
        {a.payments.length === 0 ? (
          <p className="mt-3 text-sm text-dim">No payments yet.</p>
        ) : (
          <>
          {/* Phones: a list. */}
          <ul className="mt-4 divide-y divide-hairline rounded-2xl border border-hairline bg-white shadow-card sm:hidden">
            {a.payments.map((x, i) => (
              <li key={i} className="flex items-start justify-between gap-4 px-4 py-3 text-sm">
                <span>
                  <span className="block font-medium text-paper">
                    {x.kind === "upgrade" ? `Upgrade to ${x.plan}` : x.kind === "addon" ? (x.addon === "ai" ? "AI assistant" : "Extra staff logins") : x.plan}
                  </span>
                  <span className="block font-mono text-[11px] text-dim">{day(x.payment_date)} · {MODE[x.mode] ?? x.mode}{x.receipt_no ? ` · ${x.receipt_no}` : ""}</span>
                </span>
                <span className="font-semibold tabular-nums text-paper">{rupees(Number(x.amount))}</span>
              </li>
            ))}
          </ul>
          <div className="mt-4 hidden overflow-x-auto rounded-2xl border border-hairline bg-white shadow-card sm:block">
            <table className="w-full min-w-[560px] text-sm">
              <thead className="bg-elevated/60 text-left font-mono text-[11px] uppercase tracking-wider text-dim">
                <tr><th className="px-5 py-3">Date</th><th className="px-5 py-3">For</th><th className="px-5 py-3">Paid by</th><th className="px-5 py-3">Receipt</th><th className="px-5 py-3 text-right">Amount</th></tr>
              </thead>
              <tbody className="divide-y divide-hairline">
                {a.payments.map((x, i) => (
                  <tr key={i}>
                    <td className="whitespace-nowrap px-5 py-3 text-dim">{day(x.payment_date)}</td>
                    <td className="px-5 py-3 text-paper">
                      {x.kind === "upgrade" ? `Upgrade to ${x.plan}` : x.kind === "addon" ? (x.addon === "ai" ? "AI assistant" : "Extra staff logins") : x.plan}
                    </td>
                    <td className="px-5 py-3 text-dim">{MODE[x.mode] ?? x.mode}</td>
                    <td className="px-5 py-3 font-mono text-xs text-dim">{x.receipt_no ?? "—"}</td>
                    <td className="px-5 py-3 text-right font-semibold tabular-nums text-paper">{rupees(Number(x.amount))}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          </>
        )}
        <p className="mt-4 flex flex-wrap items-center gap-2 text-sm text-dim">
          Need a GST invoice or help with your plan?
          {wa && <a href={wa} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1 font-semibold text-brand hover:underline"><MessageCircle className="h-4 w-4" /> WhatsApp us</a>}
        </p>
      </section>
    </div>
  );
}

function Skeleton() {
  return (
    <div className="space-y-6">
      <div className="h-14 w-72 animate-pulse rounded-2xl bg-elevated" />
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-[1.5fr_1fr]">
        <div className="h-72 animate-pulse rounded-3xl bg-white" />
        <div className="h-72 animate-pulse rounded-3xl bg-white" />
      </div>
    </div>
  );
}
