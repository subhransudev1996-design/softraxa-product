"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { ArrowUpRight, Check, Loader2, Lock, MessageCircle, Minus, Plus, ShieldCheck, Sparkles, X } from "lucide-react";
import SignInForm from "@/components/account/sign-in-form";
import { readPartnerCode } from "@/components/campaign-capture";
import { callFn, saveToken, savedToken, tokenFromSession, type FnError } from "@/lib/shop-session";
import { rupees } from "@/lib/site-info";
import { btnGhost, btnPrimary } from "@/lib/ui";

/* The pay page (migrations 0105, 0106): the shop is known by a pay link
   token from the app (?t=…), from the signed-in session, or from signing
   in here. Prices come from the razorpay function; the browser only says
   what the owner picked. ?do=renew|staff|ai|upgrade:<plan id> preselects. */

type Plan = {
  id: string; name: string; description: string; billing: "yearly" | "lifetime"; is_recommended: boolean;
  includes_ai: boolean; users: number | null; list_price: number; website_price: number;
  extra_staff_price: number; ai_addon_price: number;
};
type Ctx = {
  shop: string; email: string; phone: string; partner_code: string | null; plans: Plan[];
  current: null | { plan: string; billing: string; is_trial: boolean; includes_ai: boolean; expiry: string; active: boolean;
    extra_staff_price: number; ai_addon_price: number };
};
type Quote = { kind?: string; lines: { label: string; amount: number }[]; amount: number; from: string | null; until: string | null;
  code: string | null; code_ok: boolean | null; code_reason: string | null };
type Done = { ok: boolean; kind: string; plan?: string; addon?: string; until?: string; receipt_no?: string; amount?: number; error?: string };

const call = callFn;

const day = (d?: string | null) =>
  d ? new Date(`${d}T00:00:00`).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" }) : "";
const todayIso = () => new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Kolkata" });

function loadCheckout(): Promise<void> {
  return new Promise((resolve, reject) => {
    if ((window as unknown as { Razorpay?: unknown }).Razorpay) return resolve();
    const s = document.createElement("script");
    s.src = "https://checkout.razorpay.com/v1/checkout.js";
    s.onload = () => resolve();
    s.onerror = () => reject(new Error("Couldn't load the payment window — check your internet and try again"));
    document.body.appendChild(s);
  });
}

function startToken(initial: string | null) {
  if (initial) {
    saveToken(initial);
    return initial;
  }
  return savedToken();
}

export default function PayClient({ initialToken, initialDo, whatsapp }: { initialToken: string | null; initialDo: string | null; whatsapp: string }) {
  // undefined: still looking for a signed-in session.
  const [token, setToken] = useState<string | null | undefined>(() => startToken(initialToken) ?? undefined);
  const [ctx, setCtx] = useState<{ token: string; data?: Ctx; error?: string } | null>(null);

  // Keep the token out of the address bar and history (after the first render).
  useEffect(() => {
    if (initialToken) window.history.replaceState(null, "", initialDo ? `/pay?do=${encodeURIComponent(initialDo)}` : "/pay");
  }, [initialToken, initialDo]);

  // Signed in on this browser already? Then no sign-in form.
  useEffect(() => {
    if (token !== undefined) return;
    let live = true;
    tokenFromSession().then((t) => live && setToken(t)).catch(() => live && setToken(null));
    return () => { live = false; };
  }, [token]);

  useEffect(() => {
    if (!token) return;
    let live = true;
    call("context", token)
      .then((data) => live && setCtx({ token, data }))
      .catch((e: FnError) => {
        if (!live) return;
        if (e.expired) {
          saveToken(null);
          setToken(null);
        }
        setCtx({ token, error: e.message });
      });
    return () => { live = false; };
  }, [token]);

  const wa = whatsapp ? `https://wa.me/${whatsapp}?text=${encodeURIComponent("Hi, I want to pay for my Dukania plan.")}` : "";

  if (token === undefined) return <Loading />;
  if (!token) return <SignInForm note={ctx?.error} button="Continue to payment" onDone={setToken} />;
  if (!ctx || ctx.token !== token) return <Loading />;
  if (ctx.error || !ctx.data) {
    return (
      <div className="mx-auto max-w-lg rounded-2xl border border-hairline bg-white p-8 text-center shadow-card">
        <p className="font-display text-xl font-bold text-paper">Online payment isn&apos;t open right now</p>
        <p className="mt-2 text-sm text-dim">{ctx.error}</p>
        {wa && <a href={wa} target="_blank" rel="noreferrer" className={`${btnGhost} mt-6`}><MessageCircle className="h-4 w-4" /> Pay on WhatsApp</a>}
      </div>
    );
  }
  return <Checkout token={token} ctx={ctx.data} initialDo={initialDo} wa={wa} />;
}

/* ---------- Checkout ---------- */

type Mode = "plan" | "upgrade" | "addon";

function Checkout({ token, ctx, initialDo, wa }: { token: string; ctx: Ctx; initialDo: string | null; wa: string }) {
  const cur = ctx.current;
  const onLifetime = Boolean(cur?.active && cur.billing === "lifetime");
  const canAddon = Boolean(cur?.active && !cur.is_trial);
  // Upgrades (0106): from a running yearly plan to a dearer one or to Lifetime.
  const curPlan = ctx.plans.find((p) => p.name === cur?.plan);
  const upgrades = canAddon && !onLifetime && curPlan
    ? ctx.plans.filter((p) => p.id !== curPlan.id && (p.billing === "lifetime" || p.website_price > curPlan.website_price))
    : [];
  const modes: Mode[] = [...(onLifetime ? [] : ["plan" as Mode]), ...(upgrades.length ? ["upgrade" as Mode] : []), ...(canAddon ? ["addon" as Mode] : [])];
  const asked = initialDo ?? "";
  const startMode: Mode = asked.startsWith("upgrade") && upgrades.length ? "upgrade"
    : (asked === "staff" || asked === "ai") && canAddon ? "addon" : onLifetime ? "addon" : "plan";
  const [mode, setMode] = useState<Mode>(startMode);
  const [upId, setUpId] = useState(() => upgrades.find((u) => asked === `upgrade:${u.id}`)?.id ?? upgrades[0]?.id ?? "");
  const firstPlan = ctx.plans.find((p) => p.name === cur?.plan && p.billing !== "lifetime")
    ?? ctx.plans.find((p) => p.billing !== "lifetime") ?? ctx.plans[0];
  const [planId, setPlanId] = useState(firstPlan?.id ?? "");
  const [staff, setStaff] = useState(0);
  const [ai, setAi] = useState(false);
  const [code, setCode] = useState(() => ctx.partner_code ?? readPartnerCode() ?? "");
  const [codeOpen, setCodeOpen] = useState(false);
  const [codeDraft, setCodeDraft] = useState("");
  const [addon, setAddon] = useState<"staff" | "ai">(asked === "ai" ? "ai" : "staff");
  const [qty, setQty] = useState(1);
  const [quote, setQuote] = useState<{ key: string; data?: Quote; error?: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<Done | null>(null);

  const plan = ctx.plans.find((p) => p.id === planId);
  const aiOffered = Boolean(plan && !plan.includes_ai && plan.ai_addon_price > 0);
  const item = useMemo(() => mode === "plan"
    ? { kind: "plan", plan_id: planId, extra_staff: staff, ai_addon: ai && aiOffered, code: code.trim() }
    : mode === "upgrade" ? { kind: "upgrade", plan_id: upId }
    : { kind: "addon", addon, quantity: addon === "ai" ? 1 : qty }, [mode, planId, staff, ai, aiOffered, code, upId, addon, qty]);
  const key = JSON.stringify(item);

  useEffect(() => {
    let live = true;
    const t = setTimeout(() => {
      call("quote", token, { item })
        .then((data) => live && setQuote({ key, data }))
        .catch((e) => live && setQuote({ key, error: e.message }));
    }, 250);
    return () => { live = false; clearTimeout(t); };
  }, [token, item, key]);

  const q = quote?.key === key ? quote : null;
  const lastQuote = q?.data ?? quote?.data ?? null;

  async function waitForPlan(orderId: string) {
    for (let i = 0; i < 10; i++) {
      await new Promise((r) => setTimeout(r, 3000));
      const s = await call("status", token, { razorpay_order_id: orderId }).catch(() => null);
      if (s?.ok) return s as Done;
    }
    return null;
  }

  async function pay() {
    setError(null);
    setBusy(true);
    try {
      const order = await call("order", token, { item });
      await loadCheckout();
      const Razorpay = (window as unknown as { Razorpay: new (o: unknown) => { open: () => void; on: (e: string, f: (r: { error?: { description?: string } }) => void) => void } }).Razorpay;
      const rz = new Razorpay({
        key: order.key_id, order_id: order.order_id, amount: order.amount, currency: order.currency,
        name: "Dukania", description: order.description,
        prefill: { email: order.email, contact: order.phone, name: order.shop },
        notes: { shop: order.shop },
        theme: { color: "#6d28d9" },
        handler: async (r: { razorpay_order_id: string; razorpay_payment_id: string; razorpay_signature: string }) => {
          try {
            const res = await call("confirm", token, r);
            if (res.ok) return setDone(res);
            setDone((await waitForPlan(r.razorpay_order_id)) ?? { ok: false, kind: mode, error: res.error });
          } catch (e) {
            setDone((await waitForPlan(r.razorpay_order_id)) ?? { ok: false, kind: mode, error: (e as Error).message });
          } finally {
            setBusy(false);
          }
        },
        modal: { ondismiss: () => setBusy(false) },
      });
      rz.on("payment.failed", (r) => setError(r.error?.description ?? "The payment didn't go through — try again"));
      rz.open();
    } catch (e) {
      setError((e as Error).message);
      setBusy(false);
    }
  }

  if (done) return <Result done={done} shop={ctx.shop} wa={wa} />;

  const trialEnded = cur ? cur.expiry < todayIso() : false;
  const status = !cur ? "No plan yet"
    : cur.is_trial ? (trialEnded ? `Free trial ended ${day(cur.expiry)}` : `Free trial until ${day(cur.expiry)}`)
    : cur.billing === "lifetime" && cur.active ? `${cur.plan} · for life`
    : cur.active ? `${cur.plan} · until ${day(cur.expiry)}` : `${cur.plan} · ended ${day(cur.expiry)}`;

  return (
    <div className="grid grid-cols-1 items-start gap-8 lg:grid-cols-[1fr_400px]">
      <div>
        {/* Shop */}
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-hairline pb-5">
          <div className="flex items-center gap-3">
            <span className="inline-flex h-11 w-11 items-center justify-center rounded-xl bg-brand-soft font-display text-lg font-bold text-brand">
              {ctx.shop.trim().charAt(0).toUpperCase()}
            </span>
            <div>
              <p className="font-semibold text-paper">{ctx.shop}</p>
              <p className="text-sm text-dim">{status}</p>
            </div>
          </div>
          {modes.length > 1 && (
            <div className="inline-flex flex-wrap rounded-xl bg-elevated p-1 text-sm font-semibold">
              {modes.map((m) => (
                <button key={m} onClick={() => setMode(m)} aria-pressed={mode === m}
                  className={`rounded-lg px-3.5 py-1.5 transition ${mode === m ? "bg-white text-paper shadow-sm" : "text-dim hover:text-paper"}`}>
                  {m === "plan" ? (canAddon ? "Renew" : "Choose a plan") : m === "upgrade" ? "Upgrade" : "Add logins or AI"}
                </button>
              ))}
            </div>
          )}
        </div>

        {mode === "upgrade" ? (
          <>
            <Step n={1} title="Upgrade your plan" />
            <p className="mt-2 text-sm text-dim">
              Starts today. You pay only the difference for the {Math.max(0, Math.round((new Date(`${cur?.expiry}T00:00:00`).getTime() - new Date(`${todayIso()}T00:00:00`).getTime()) / 86400000))} days
              left on {cur?.plan} — your renewal date stays {day(cur?.expiry)}. Lifetime counts the unused days off its price.
            </p>
            <div role="radiogroup" className="mt-4 space-y-3">
              {upgrades.map((p) => {
                const on = p.id === upId;
                return (
                  <button key={p.id} role="radio" aria-checked={on} onClick={() => setUpId(p.id)}
                    className={`flex w-full items-start gap-4 rounded-2xl border bg-white p-5 text-left transition ${on ? "border-brand ring-4 ring-brand/10" : "border-hairline hover:border-brand/40"}`}>
                    <span className={`mt-1 inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-full border-2 ${on ? "border-brand bg-brand" : "border-hairline"}`}>
                      {on && <span className="h-2 w-2 rounded-full bg-white" />}
                    </span>
                    <span className="min-w-0 flex-1">
                      <span className="flex flex-wrap items-center gap-2">
                        <span className="font-display text-lg font-bold text-paper">{cur?.plan} → {p.name}</span>
                        {p.billing === "lifetime" && <span className="rounded-full bg-marigold/25 px-2 py-0.5 text-[11px] font-bold uppercase tracking-wide text-amber">Pay once</span>}
                      </span>
                      <span className="mt-1 block text-sm text-dim">
                        {p.includes_ai && !cur?.includes_ai ? "Adds the AI assistant (ChatGPT & Claude). " : ""}
                        {p.billing === "lifetime" ? "No more yearly renewals." : `Then ${rupees(p.website_price)} a year from ${day(cur?.expiry)}.`}
                      </span>
                    </span>
                    <span className="shrink-0 text-right">
                      {on && q?.data ? (
                        <span className="block font-display text-2xl font-bold tabular-nums text-paper">{rupees(q.data.amount)}</span>
                      ) : (
                        <ArrowUpRight className="h-5 w-5 text-brand" />
                      )}
                      {on && <span className="block text-xs text-dim">to pay now</span>}
                    </span>
                  </button>
                );
              })}
            </div>
          </>
        ) : mode === "plan" ? (
          <>
            <Step n={1} title={canAddon ? "Renew your plan" : "Choose your plan"} />
            <div role="radiogroup" className="mt-4 space-y-3">
              {ctx.plans.map((p) => {
                const on = p.id === planId;
                const save = p.list_price - p.website_price;
                return (
                  <button key={p.id} role="radio" aria-checked={on} onClick={() => { setPlanId(p.id); setAi(false); }}
                    className={`relative flex w-full items-start gap-4 rounded-2xl border bg-white p-5 text-left transition ${on ? "border-brand ring-4 ring-brand/10" : "border-hairline hover:border-brand/40"}`}>
                    <span className={`mt-1 inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-full border-2 ${on ? "border-brand bg-brand" : "border-hairline"}`}>
                      {on && <span className="h-2 w-2 rounded-full bg-white" />}
                    </span>
                    <span className="min-w-0 flex-1">
                      <span className="flex flex-wrap items-center gap-2">
                        <span className="font-display text-lg font-bold text-paper">{p.name}</span>
                        {p.is_recommended && <span className="rounded-full bg-brand px-2 py-0.5 text-[11px] font-bold uppercase tracking-wide text-white">Most chosen</span>}
                        {p.billing === "lifetime" && <span className="rounded-full bg-marigold/25 px-2 py-0.5 text-[11px] font-bold uppercase tracking-wide text-amber">Pay once</span>}
                      </span>
                      {p.description && <span className="mt-1 block text-sm text-dim">{p.description}</span>}
                      <span className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-dim">
                        {p.users && <span>{p.users} logins</span>}
                        <span>{p.includes_ai ? "AI assistant included" : "AI as an add-on"}</span>
                        <span>{p.billing === "lifetime" ? "Updates for life" : "Renews yearly"}</span>
                      </span>
                    </span>
                    <span className="shrink-0 text-right">
                      <span className="block font-display text-2xl font-bold tabular-nums text-paper">{rupees(p.website_price)}</span>
                      <span className="block text-xs text-dim">{p.billing === "lifetime" ? "one time" : "per year"}</span>
                      {save > 0 && <span className="mt-1 inline-block rounded-md bg-emerald-50 px-1.5 py-0.5 text-[11px] font-bold text-emerald-700">Save {rupees(save)}</span>}
                    </span>
                  </button>
                );
              })}
            </div>

            {plan && (
              <>
                <Step n={2} title="Extras" hint="Optional" />
                <div className="mt-4 divide-y divide-hairline rounded-2xl border border-hairline bg-white">
                  <div className="flex items-center justify-between gap-4 p-5">
                    <div>
                      <p className="font-semibold text-paper">Extra staff logins</p>
                      <p className="text-sm text-dim">{plan.users ? `${plan.users} included · ` : ""}{rupees(plan.extra_staff_price)} each {plan.billing === "lifetime" ? "for a year" : "a year"}</p>
                    </div>
                    <Stepper value={staff} min={0} max={50} onChange={setStaff} />
                  </div>
                  {aiOffered && (
                    <label className="flex cursor-pointer items-center justify-between gap-4 p-5">
                      <span>
                        <span className="flex items-center gap-1.5 font-semibold text-paper"><Sparkles className="h-4 w-4 text-brand" /> AI assistant</span>
                        <span className="block text-sm text-dim">Run the shop from ChatGPT or Claude · {rupees(plan.ai_addon_price)} a year</span>
                      </span>
                      <Switch checked={ai} onChange={setAi} />
                    </label>
                  )}
                </div>
              </>
            )}
          </>
        ) : (
          <>
            <Step n={1} title="What would you like to add?" />
            <div role="radiogroup" className="mt-4 space-y-3">
              {[
                { k: "staff" as const, name: "Extra staff logins", price: cur?.extra_staff_price ?? 0, show: true },
                { k: "ai" as const, name: "AI assistant", price: cur?.ai_addon_price ?? 0, show: !cur?.includes_ai && (cur?.ai_addon_price ?? 0) > 0 },
              ].filter((x) => x.show).map((x) => {
                const on = addon === x.k;
                return (
                  <button key={x.k} role="radio" aria-checked={on} onClick={() => setAddon(x.k)}
                    className={`flex w-full items-center gap-4 rounded-2xl border bg-white p-5 text-left transition ${on ? "border-brand ring-4 ring-brand/10" : "border-hairline hover:border-brand/40"}`}>
                    <span className={`inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-full border-2 ${on ? "border-brand bg-brand" : "border-hairline"}`}>
                      {on && <span className="h-2 w-2 rounded-full bg-white" />}
                    </span>
                    <span className="flex-1 font-semibold text-paper">{x.name}</span>
                    <span className="text-sm text-dim">{rupees(x.price)} a year</span>
                  </button>
                );
              })}
            </div>
            {addon === "staff" && (
              <div className="mt-3 flex items-center justify-between rounded-2xl border border-hairline bg-white p-5">
                <p className="font-semibold text-paper">How many logins?</p>
                <Stepper value={qty} min={1} max={50} onChange={setQty} />
              </div>
            )}
            <p className="mt-3 text-sm text-dim">
              {cur?.billing === "lifetime" ? "Runs for one year from today." : `Runs until your plan renews on ${day(cur?.expiry)} — you pay only for the days left.`}
            </p>
          </>
        )}
      </div>

      {/* The bill */}
      <aside className="lg:sticky lg:top-24">
        <div className="rounded-t-2xl border border-b-0 border-hairline bg-white px-6 pb-6 pt-6 shadow-card">
          <div className="text-center">
            <p className="font-mono text-sm font-bold tracking-[0.3em] text-paper">DUKANIA</p>
            <p className="mt-1 font-mono text-[11px] uppercase tracking-wider text-dim">{ctx.shop}</p>
          </div>
          <Rule />
          {!lastQuote && !q?.error ? (
            <p className="flex items-center justify-center gap-2 py-6 font-mono text-xs text-dim"><Loader2 className="h-4 w-4 animate-spin" /> Adding up…</p>
          ) : q?.error ? (
            <p className="py-4 text-sm font-medium text-red-700">{q.error}</p>
          ) : lastQuote && (
            <div className={`transition-opacity ${q ? "opacity-100" : "opacity-50"}`}>
              <ul className="space-y-2.5 font-mono text-[13px]">
                {lastQuote.lines.map((l) => (
                  <li key={l.label} className="flex justify-between gap-4">
                    <span className={l.amount < 0 ? "text-emerald-700" : "text-paper"}>{l.label}</span>
                    <span className={`tabular-nums ${l.amount < 0 ? "text-emerald-700" : "text-paper"}`}>
                      {l.amount < 0 ? `−${rupees(-l.amount)}` : rupees(l.amount)}
                    </span>
                  </li>
                ))}
              </ul>
              <Rule />
              <div className="flex items-baseline justify-between">
                <span className="font-mono text-sm font-bold tracking-widest text-paper">TOTAL</span>
                <span className="font-display text-3xl font-bold tabular-nums text-paper">{rupees(lastQuote.amount)}</span>
              </div>
              <p className="mt-1 text-right font-mono text-[11px] text-dim">GST included</p>
              {(lastQuote.until || (mode === "plan" && plan?.billing === "lifetime") || (mode === "upgrade" && !lastQuote.until)) && (
                <p className="mt-4 rounded-lg bg-elevated/70 px-3 py-2 text-center font-mono text-[11px] text-paper">
                  {lastQuote.until ? `ACTIVE ${day(lastQuote.from && lastQuote.from > todayIso() ? lastQuote.from : todayIso())} → ${day(lastQuote.until)}` : "YOURS FOR LIFE"}
                </p>
              )}
            </div>
          )}

          {mode === "plan" && (
            <div className="mt-5">
              {code && lastQuote?.code_ok !== false ? (
                <div className="flex items-center justify-between rounded-lg border border-dashed border-emerald-600/40 bg-emerald-50 px-3 py-2 text-sm">
                  <span className="font-mono font-semibold text-emerald-800">{code} applied</span>
                  <button onClick={() => setCode("")} aria-label="Remove code" className="rounded p-1 text-emerald-800 hover:bg-emerald-100"><X className="h-4 w-4" /></button>
                </div>
              ) : codeOpen ? (
                <form onSubmit={(e) => { e.preventDefault(); setCode(codeDraft.trim()); }} className="flex gap-2">
                  <input autoFocus value={codeDraft} onChange={(e) => setCodeDraft(e.target.value.toUpperCase())} placeholder="CODE"
                    className="min-w-0 flex-1 rounded-lg border border-hairline px-3 py-2 font-mono text-sm outline-none focus:border-brand" />
                  <button type="submit" className="rounded-lg border border-hairline px-3 text-sm font-semibold text-paper hover:border-brand">Apply</button>
                </form>
              ) : (
                <button onClick={() => { setCodeOpen(true); setCodeDraft(code); }} className="text-sm font-semibold text-brand hover:underline">Have a discount code?</button>
              )}
              {code && lastQuote?.code_ok === false && (
                <p className="mt-2 text-xs font-medium text-red-700">{code}: {lastQuote.code_reason}</p>
              )}
            </div>
          )}

          {error && <p className="mt-4 text-sm font-medium text-red-700">{error}</p>}
          <button onClick={pay} disabled={busy || !q?.data} className={`${btnPrimary} mt-5 w-full justify-center text-base disabled:opacity-60`}>
            {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Lock className="h-4 w-4" />}
            {q?.data ? `Pay ${rupees(q.data.amount)}` : "Pay"}
          </button>
          <div className="mt-4 flex flex-wrap justify-center gap-1.5">
            {["UPI", "Cards", "Netbanking", "Wallets"].map((m) => (
              <span key={m} className="rounded-md border border-hairline px-2 py-0.5 font-mono text-[10px] uppercase tracking-wide text-dim">{m}</span>
            ))}
          </div>
          <p className="mt-3 flex items-center justify-center gap-1.5 text-xs text-dim">
            <ShieldCheck className="h-3.5 w-3.5 text-emerald-700" /> Secured by Razorpay
          </p>
        </div>
        <Tear />
      </aside>

      {/* On a phone the bill is below the plans: keep the total and Pay in reach. */}
      <div className="fixed inset-x-0 bottom-0 z-40 flex items-center justify-between gap-3 border-t border-hairline bg-white/95 px-4 py-3 backdrop-blur lg:hidden">
        <span>
          <span className="block font-mono text-[10px] uppercase tracking-wider text-dim">Total · GST incl.</span>
          <span className="font-display text-xl font-bold tabular-nums text-paper">{lastQuote ? rupees(lastQuote.amount) : "…"}</span>
        </span>
        <button onClick={pay} disabled={busy || !q?.data} className={`${btnPrimary} min-h-11 px-5 disabled:opacity-60`}>
          {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Lock className="h-4 w-4" />} Pay
        </button>
      </div>
    </div>
  );
}

/* ---------- Result ---------- */

function Result({ done, shop, wa }: { done: Done; shop: string; wa: string }) {
  if (!done.ok) {
    return (
      <div className="mx-auto max-w-lg rounded-2xl border border-hairline bg-white p-8 shadow-card">
        <Loader2 className="h-6 w-6 animate-spin text-brand" />
        <p className="mt-4 font-display text-2xl font-bold text-paper">We&apos;re confirming your payment</p>
        <p className="mt-2 text-sm text-dim">
          {done.error ? `${done.error}. ` : ""}If money was taken, your plan turns on within a few minutes — please don&apos;t pay again.
          If it hasn&apos;t after 10 minutes, message us with your payment details.
        </p>
        {wa && <a href={wa} target="_blank" rel="noreferrer" className={`${btnGhost} mt-6`}><MessageCircle className="h-4 w-4" /> WhatsApp Dukania</a>}
      </div>
    );
  }
  const what = done.kind === "plan" || done.kind === "upgrade" ? done.plan : done.addon === "ai" ? "AI assistant" : "Extra staff logins";
  const lifetime = (done.kind === "plan" || done.kind === "upgrade") && (!done.until || done.until >= "2099-01-01");
  const rows: [string, string][] = [
    ["Item", what ?? ""],
    ["Valid", lifetime ? "For life" : `Until ${day(done.until)}`],
    ...(done.receipt_no ? [["Receipt", done.receipt_no] as [string, string]] : []),
    ["Date", day(todayIso())],
  ];

  return (
    <div className="mx-auto grid max-w-4xl grid-cols-1 items-center gap-10 lg:grid-cols-[1fr_380px]">
      <div>
        <span className="inline-flex h-12 w-12 items-center justify-center rounded-full bg-emerald-600 text-white"><Check className="h-6 w-6" strokeWidth={3} /></span>
        <h2 className="mt-5 font-display text-4xl font-bold tracking-tight text-paper">You&apos;re all set.</h2>
        <p className="mt-3 max-w-md text-lg text-dim">
          {lifetime ? <>Dukania is yours for life.</> : <>{what} is active until <b className="text-paper">{day(done.until)}</b>.</>} Thank you for your payment.
        </p>
        <ol className="mt-8 space-y-4">
          {[
            ["Open the Dukania app", "on your phone or PC — the plan updates by itself in a few seconds."],
            ["Not showing yet?", "Pull down on the Plan screen to refresh."],
            ["Your account", "shows your plan, days left and every payment."],
            ["Need a GST invoice?", "Ask us on WhatsApp with your receipt number."],
          ].map(([t, d], i) => (
            <li key={t} className="flex gap-4">
              <span className="inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-brand-soft font-mono text-xs font-bold text-brand">{i + 1}</span>
              <p className="text-sm text-dim"><b className="text-paper">{t}</b> {d}</p>
            </li>
          ))}
        </ol>
        <Link href="/account" className={`${btnGhost} mt-8`}>Go to my account <ArrowUpRight className="h-4 w-4" /></Link>
      </div>

      <div className="relative">
        <div className="rounded-t-2xl border border-b-0 border-hairline bg-white px-6 pb-6 pt-6 shadow-card">
          <div className="text-center">
            <p className="font-mono text-sm font-bold tracking-[0.3em] text-paper">DUKANIA</p>
            <p className="mt-1 font-mono text-[11px] uppercase tracking-wider text-dim">{shop}</p>
          </div>
          <Rule />
          <dl className="space-y-2.5 font-mono text-[13px]">
            {rows.map(([k, v]) => (
              <div key={k} className="flex justify-between gap-4"><dt className="text-dim">{k}</dt><dd className="text-right text-paper">{v}</dd></div>
            ))}
          </dl>
          <Rule />
          <div className="flex items-baseline justify-between">
            <span className="font-mono text-sm font-bold tracking-widest text-paper">PAID</span>
            <span className="font-display text-3xl font-bold tabular-nums text-paper">{done.amount ? rupees(Number(done.amount)) : ""}</span>
          </div>
          <p className="mt-1 text-right font-mono text-[11px] text-dim">GST included · via Razorpay</p>
        </div>
        <Tear />
        <span aria-hidden className="pointer-events-none absolute -right-3 -top-4 rotate-12 rounded-lg border-[3px] border-emerald-600/80 bg-white/80 px-3 py-0.5 font-mono text-xl font-bold tracking-[0.2em] text-emerald-600/80">
          PAID
        </span>
      </div>
    </div>
  );
}

/* ---------- Small pieces ---------- */

function Step({ n, title, hint }: { n: number; title: string; hint?: string }) {
  return (
    <div className="mt-8 flex items-center gap-3">
      <span className="inline-flex h-7 w-7 items-center justify-center rounded-full bg-paper font-mono text-xs font-bold text-white">{n}</span>
      <h2 className="font-display text-xl font-bold text-paper">{title}</h2>
      {hint && <span className="text-sm text-dim">{hint}</span>}
    </div>
  );
}

function Stepper({ value, min, max, onChange }: { value: number; min: number; max: number; onChange: (v: number) => void }) {
  const btn = "inline-flex h-9 w-9 items-center justify-center rounded-lg text-paper transition hover:bg-elevated disabled:opacity-30";
  return (
    <div className="inline-flex items-center rounded-xl border border-hairline bg-white p-1">
      <button type="button" aria-label="Fewer" className={btn} disabled={value <= min} onClick={() => onChange(Math.max(min, value - 1))}><Minus className="h-4 w-4" /></button>
      <span className="w-9 text-center font-mono text-sm font-bold tabular-nums text-paper">{value}</span>
      <button type="button" aria-label="More" className={btn} disabled={value >= max} onClick={() => onChange(Math.min(max, value + 1))}><Plus className="h-4 w-4" /></button>
    </div>
  );
}

function Switch({ checked, onChange }: { checked: boolean; onChange: (v: boolean) => void }) {
  return (
    <button type="button" role="switch" aria-checked={checked} onClick={(e) => { e.preventDefault(); onChange(!checked); }}
      className={`relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition ${checked ? "bg-brand" : "bg-hairline"}`}>
      <span className={`inline-block h-5 w-5 rounded-full bg-white shadow transition ${checked ? "translate-x-5" : "translate-x-0.5"}`} />
    </button>
  );
}

/** A dashed line like a printed bill. */
function Rule() {
  return <div className="my-5 border-t-2 border-dashed border-hairline" />;
}

/** The torn bottom edge of the bill. */
function Tear() {
  return (
    <div aria-hidden className="h-3 w-full"
      style={{
        background:
          "linear-gradient(135deg, #fff 6px, transparent 0) 0 0 / 12px 12px repeat-x, linear-gradient(225deg, #fff 6px, transparent 0) 0 0 / 12px 12px repeat-x",
        filter: "drop-shadow(0 2px 1px rgba(28,21,48,0.08))",
      }}
    />
  );
}

function Loading() {
  return (
    <div className="grid grid-cols-1 gap-8 lg:grid-cols-[1fr_400px]">
      <div className="space-y-3">
        <div className="h-14 animate-pulse rounded-2xl bg-elevated" />
        {[0, 1, 2].map((i) => <div key={i} className="h-28 animate-pulse rounded-2xl bg-white" />)}
      </div>
      <div className="h-96 animate-pulse rounded-2xl bg-white" />
    </div>
  );
}
