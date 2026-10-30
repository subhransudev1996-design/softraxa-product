"use client";

import { useEffect, useMemo, useState } from "react";
import { Check, Loader2, Lock, MessageCircle, ShieldCheck, Ticket } from "lucide-react";
import { readPartnerCode } from "@/components/campaign-capture";
import { supabase } from "@/lib/supabase-client";
import { rupees } from "@/lib/site-info";
import { btnGhost, btnPrimary, eyebrow } from "@/lib/ui";

/* The pay page (migration 0105): the shop is known by a pay link token
   from the app (?t=…) or from signing in here. Prices come from the
   razorpay function; the browser only says what the owner picked. */

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
type Quote = { lines: { label: string; amount: number }[]; amount: number; until: string | null; code_ok: boolean | null; code_reason: string | null };
type Done = { ok: boolean; kind: string; plan?: string; addon?: string; until?: string; receipt_no?: string; error?: string };

const FN = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/razorpay`;
const KEY = "dk_pay_token";

async function call(action: string, token: string, extra: Record<string, unknown> = {}) {
  const res = await fetch(FN, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "" },
    body: JSON.stringify({ action, token, ...extra }),
  });
  const data = await res.json().catch(() => ({ error: "Something went wrong — try again" }));
  if (!res.ok) throw Object.assign(new Error(data.error ?? "Something went wrong"), data);
  return data;
}

const day = (d?: string | null) =>
  d ? new Date(`${d}T00:00:00`).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" }) : "";

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
  try {
    if (initial) {
      sessionStorage.setItem(KEY, initial);
      return initial;
    }
    return sessionStorage.getItem(KEY);
  } catch {
    return initial;
  }
}

export default function PayClient({ initialToken, whatsapp }: { initialToken: string | null; whatsapp: string }) {
  const [token, setToken] = useState<string | null>(() => startToken(initialToken));
  const [ctx, setCtx] = useState<{ token: string; data?: Ctx; error?: string } | null>(null);

  // Keep the token out of the address bar and history (after the first render).
  useEffect(() => {
    if (initialToken) window.history.replaceState(null, "", "/pay");
  }, [initialToken]);

  useEffect(() => {
    if (!token) return;
    let live = true;
    call("context", token)
      .then((data) => live && setCtx({ token, data }))
      .catch((e) => {
        if (!live) return;
        if (e.expired) {
          try { sessionStorage.removeItem(KEY); } catch {}
          setToken(null);
        }
        setCtx({ token, error: e.message });
      });
    return () => { live = false; };
  }, [token]);

  const wa = whatsapp ? `https://wa.me/${whatsapp}?text=${encodeURIComponent("Hi, I want to pay for my Dukania plan.")}` : "";

  if (!token) return <SignIn note={ctx?.error} onToken={setToken} />;
  if (!ctx || ctx.token !== token) return <Waiting text="Loading your shop…" />;
  if (ctx.error || !ctx.data) {
    return (
      <Panel>
        <p className="font-semibold text-paper">{ctx.error}</p>
        {wa && <a href={wa} target="_blank" rel="noreferrer" className={`${btnGhost} mt-5`}><MessageCircle className="h-4 w-4" /> Pay on WhatsApp</a>}
      </Panel>
    );
  }
  return <Checkout token={token} ctx={ctx.data} wa={wa} />;
}

function SignIn({ note, onToken }: { note?: string; onToken: (t: string) => void }) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const { error: authError } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    if (authError) {
      setBusy(false);
      return setError(authError.message.includes("Invalid") ? "Wrong email or password" : authError.message);
    }
    const { data, error: linkError } = await supabase.rpc("create_pay_link");
    setBusy(false);
    if (linkError) return setError(linkError.message);
    try { sessionStorage.setItem(KEY, String(data)); } catch {}
    onToken(String(data));
  }

  return (
    <Panel>
      <p className={eyebrow}>Sign in to pay</p>
      <h2 className="mt-2 font-display text-2xl font-bold">Your Dukania account</h2>
      <p className="mt-2 text-sm text-dim">
        The shop owner&apos;s email and password — the same as in the app. Or open the app and tap <b className="text-paper">Pay online</b> on the Plan screen.
      </p>
      {note && <p className="mt-3 rounded-xl bg-[#fff8e6] px-4 py-3 text-sm text-paper">{note}</p>}
      <form onSubmit={submit} className="mt-5 space-y-3">
        <input required type="email" autoComplete="email" placeholder="Email" value={email} onChange={(e) => setEmail(e.target.value)}
          className="w-full rounded-xl border border-hairline bg-white px-4 py-3 text-sm outline-none focus:border-brand" />
        <input required type="password" autoComplete="current-password" placeholder="Password" value={password} onChange={(e) => setPassword(e.target.value)}
          className="w-full rounded-xl border border-hairline bg-white px-4 py-3 text-sm outline-none focus:border-brand" />
        {error && <p className="text-sm font-medium text-red-700">{error}</p>}
        <button type="submit" disabled={busy} className={`${btnPrimary} w-full justify-center disabled:opacity-60`}>
          {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Lock className="h-4 w-4" />} Continue
        </button>
      </form>
    </Panel>
  );
}

function Checkout({ token, ctx, wa }: { token: string; ctx: Ctx; wa: string }) {
  const cur = ctx.current;
  const onLifetime = Boolean(cur?.active && cur.billing === "lifetime");
  const canAddon = Boolean(cur?.active && !cur.is_trial);
  const [mode, setMode] = useState<"plan" | "addon">(onLifetime ? "addon" : "plan");
  const firstPlan = ctx.plans.find((p) => p.name === cur?.plan && p.billing !== "lifetime")
    ?? ctx.plans.find((p) => p.is_recommended) ?? ctx.plans[0];
  const [planId, setPlanId] = useState(firstPlan?.id ?? "");
  const [staff, setStaff] = useState(0);
  const [ai, setAi] = useState(false);
  const [code, setCode] = useState(() => ctx.partner_code ?? readPartnerCode() ?? "");
  const [addon, setAddon] = useState<"staff" | "ai">("staff");
  const [qty, setQty] = useState(1);
  const [quote, setQuote] = useState<{ key: string; data?: Quote; error?: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<Done | null>(null);

  const plan = ctx.plans.find((p) => p.id === planId);
  const aiOffered = Boolean(plan && !plan.includes_ai && plan.ai_addon_price > 0);
  const item = useMemo(() => mode === "plan"
    ? { kind: "plan", plan_id: planId, extra_staff: staff, ai_addon: ai && aiOffered, code: code.trim() }
    : { kind: "addon", addon, quantity: addon === "ai" ? 1 : qty }, [mode, planId, staff, ai, aiOffered, code, addon, qty]);
  const key = JSON.stringify(item);

  useEffect(() => {
    let live = true;
    const t = setTimeout(() => {
      call("quote", token, { item })
        .then((data) => live && setQuote({ key, data }))
        .catch((e) => live && setQuote({ key, error: e.message }));
    }, 300);
    return () => { live = false; clearTimeout(t); };
  }, [token, item, key]);

  const q = quote?.key === key ? quote : null;

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

  if (done) return <Result done={done} wa={wa} />;

  return (
    <div className="grid grid-cols-1 gap-6 lg:grid-cols-[1.4fr_1fr]">
      <div className="space-y-6">
        <Panel>
          <p className="text-sm text-dim">Paying for</p>
          <p className="font-display text-2xl font-bold">{ctx.shop}</p>
          {cur && (
            <p className="mt-1 text-sm text-dim">
              Now on <b className="text-paper">{cur.plan}</b>
              {cur.billing === "lifetime" && cur.active ? " for life" : cur.active ? `, until ${day(cur.expiry)}` : `, ended ${day(cur.expiry)}`}
            </p>
          )}
          {canAddon && !onLifetime && (
            <div className="mt-4 flex gap-2">
              {(["plan", "addon"] as const).map((m) => (
                <button key={m} onClick={() => setMode(m)} aria-pressed={mode === m}
                  className={`rounded-xl px-4 py-2 text-sm font-semibold ${mode === m ? "bg-brand text-white" : "border border-hairline bg-white text-paper"}`}>
                  {m === "plan" ? "Renew or change plan" : "Add logins or AI"}
                </button>
              ))}
            </div>
          )}
        </Panel>

        {mode === "plan" ? (
          <Panel>
            <p className={eyebrow}>Choose your plan</p>
            <div className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-3">
              {ctx.plans.map((p) => (
                <button key={p.id} onClick={() => { setPlanId(p.id); setAi(false); }} aria-pressed={p.id === planId}
                  className={`rounded-2xl border-2 p-4 text-left transition ${p.id === planId ? "border-brand bg-brand-soft/60" : "border-hairline bg-white hover:border-brand/40"}`}>
                  <span className="block font-bold text-paper">{p.name}</span>
                  <span className="mt-1 block font-display text-2xl font-bold text-brand">{rupees(p.website_price)}</span>
                  <span className="block text-xs text-dim">
                    {p.billing === "lifetime" ? "one time" : "a year"}
                    {p.list_price > p.website_price && <> · <s>{rupees(p.list_price)}</s></>}
                  </span>
                  {p.users && <span className="mt-2 block text-xs text-dim">{p.users} logins{p.includes_ai ? " · AI included" : ""}</span>}
                </button>
              ))}
            </div>
            {plan && (
              <div className="mt-5 grid grid-cols-1 gap-3 sm:grid-cols-2">
                <label className="rounded-2xl border border-hairline bg-white p-4 text-sm">
                  <span className="font-semibold text-paper">Extra staff logins</span>
                  <span className="block text-xs text-dim">{rupees(plan.extra_staff_price)} each a year · plan has {plan.users ?? "unlimited"}</span>
                  <input type="number" min={0} max={50} value={staff}
                    onChange={(e) => setStaff(Math.max(0, Math.min(50, Math.floor(Number(e.target.value) || 0))))}
                    className="mt-2 w-24 rounded-lg border border-hairline px-3 py-2" />
                </label>
                {aiOffered && (
                  <label className="flex items-start gap-3 rounded-2xl border border-hairline bg-white p-4 text-sm">
                    <input type="checkbox" checked={ai} onChange={(e) => setAi(e.target.checked)} className="mt-1" />
                    <span>
                      <span className="font-semibold text-paper">AI assistant</span>
                      <span className="block text-xs text-dim">{rupees(plan.ai_addon_price)} a year · ChatGPT &amp; Claude</span>
                    </span>
                  </label>
                )}
              </div>
            )}
            <label className="mt-5 block text-sm">
              <span className="flex items-center gap-1.5 font-semibold text-paper"><Ticket className="h-4 w-4 text-brand" /> Discount code</span>
              <input value={code} onChange={(e) => setCode(e.target.value.toUpperCase())} placeholder="Optional"
                className="mt-2 w-full max-w-xs rounded-lg border border-hairline px-3 py-2 font-mono" />
            </label>
          </Panel>
        ) : (
          <Panel>
            <p className={eyebrow}>Add to your plan</p>
            <div className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-2">
              <button onClick={() => setAddon("staff")} aria-pressed={addon === "staff"}
                className={`rounded-2xl border-2 p-4 text-left ${addon === "staff" ? "border-brand bg-brand-soft/60" : "border-hairline bg-white"}`}>
                <span className="block font-bold text-paper">Extra staff logins</span>
                <span className="block text-xs text-dim">{rupees(cur?.extra_staff_price ?? 0)} each a year</span>
              </button>
              {!cur?.includes_ai && (cur?.ai_addon_price ?? 0) > 0 && (
                <button onClick={() => setAddon("ai")} aria-pressed={addon === "ai"}
                  className={`rounded-2xl border-2 p-4 text-left ${addon === "ai" ? "border-brand bg-brand-soft/60" : "border-hairline bg-white"}`}>
                  <span className="block font-bold text-paper">AI assistant</span>
                  <span className="block text-xs text-dim">{rupees(cur?.ai_addon_price ?? 0)} a year</span>
                </button>
              )}
            </div>
            {addon === "staff" && (
              <label className="mt-4 block text-sm">
                <span className="font-semibold text-paper">How many?</span>
                <input type="number" min={1} max={50} value={qty}
                  onChange={(e) => setQty(Math.max(1, Math.min(50, Math.floor(Number(e.target.value) || 1))))}
                  className="ml-3 w-24 rounded-lg border border-hairline px-3 py-2" />
              </label>
            )}
            <p className="mt-4 text-xs text-dim">
              {cur?.billing === "lifetime" ? "Runs for one year." : "Runs until your plan renews — you pay only for the days left."}
            </p>
          </Panel>
        )}
      </div>

      <div>
        <div className="sticky top-24">
          <Panel>
            <p className={eyebrow}>To pay</p>
            {!q ? (
              <p className="mt-4 flex items-center gap-2 text-sm text-dim"><Loader2 className="h-4 w-4 animate-spin" /> Working out your price…</p>
            ) : q.error ? (
              <p className="mt-4 text-sm font-medium text-red-700">{q.error}</p>
            ) : q.data && (
              <>
                <ul className="mt-4 space-y-2 text-sm">
                  {q.data.lines.map((l) => (
                    <li key={l.label} className="flex justify-between gap-3">
                      <span className="text-dim">{l.label}</span>
                      <span className={`tabular-nums ${l.amount < 0 ? "text-emerald-700" : "text-paper"}`}>
                        {l.amount < 0 ? `−${rupees(-l.amount)}` : rupees(l.amount)}
                      </span>
                    </li>
                  ))}
                </ul>
                {q.data.code_ok === false && <p className="mt-2 text-xs font-medium text-red-700">Code: {q.data.code_reason}</p>}
                <div className="mt-4 flex items-end justify-between border-t border-hairline pt-4">
                  <span className="text-sm font-semibold text-paper">Total</span>
                  <span className="font-display text-3xl font-bold text-brand">{rupees(q.data.amount)}</span>
                </div>
                <p className="mt-1 text-xs text-dim">
                  GST included.{" "}
                  {q.data.until ? `Active until ${day(q.data.until)}.` : mode === "plan" ? "Yours for life." : ""}
                </p>
              </>
            )}
            {error && <p className="mt-4 text-sm font-medium text-red-700">{error}</p>}
            <button onClick={pay} disabled={busy || !q?.data} className={`${btnPrimary} mt-5 w-full justify-center disabled:opacity-60`}>
              {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Lock className="h-4 w-4" />}
              {q?.data ? `Pay ${rupees(q.data.amount)}` : "Pay"}
            </button>
            <p className="mt-3 flex items-center gap-1.5 text-xs text-dim">
              <ShieldCheck className="h-4 w-4 text-emerald-700" /> UPI, cards, netbanking and wallets, through Razorpay.
            </p>
          </Panel>
        </div>
      </div>
    </div>
  );
}

function Result({ done, wa }: { done: Done; wa: string }) {
  if (!done.ok) {
    return (
      <Panel>
        <p className="font-display text-2xl font-bold">We&apos;re checking your payment</p>
        <p className="mt-2 text-sm text-dim">
          {done.error ? `${done.error}. ` : ""}If money was taken, your plan turns on within a few minutes — you don&apos;t need to pay again.
          If it doesn&apos;t, message us with your payment details.
        </p>
        {wa && <a href={wa} target="_blank" rel="noreferrer" className={`${btnGhost} mt-5`}><MessageCircle className="h-4 w-4" /> WhatsApp Dukania</a>}
      </Panel>
    );
  }
  const what = done.kind === "plan" ? done.plan : done.addon === "ai" ? "The AI assistant" : "Your extra staff logins";
  const lifetime = done.kind === "plan" && (!done.until || done.until >= "2099-01-01");
  return (
    <Panel>
      <span className="inline-flex h-12 w-12 items-center justify-center rounded-full bg-emerald-600 text-white"><Check className="h-6 w-6" /></span>
      <p className="mt-4 font-display text-2xl font-bold">Payment received — thank you!</p>
      <p className="mt-2 text-dim">
        <b className="text-paper">{what}</b> {lifetime ? "is yours for life." : <>is active until <b className="text-paper">{day(done.until)}</b>.</>}
        {done.receipt_no && <> Receipt {done.receipt_no}.</>}
      </p>
      <p className="mt-4 rounded-xl bg-brand-soft/60 px-4 py-3 text-sm text-paper">
        Go back to the Dukania app — it updates by itself in a few seconds. If it doesn&apos;t, pull down on the Plan screen to refresh.
      </p>
    </Panel>
  );
}

function Panel({ children }: { children: React.ReactNode }) {
  return <div className="rounded-3xl border border-hairline bg-white p-6 shadow-card">{children}</div>;
}

function Waiting({ text }: { text: string }) {
  return <Panel><p className="flex items-center gap-2 text-sm text-dim"><Loader2 className="h-4 w-4 animate-spin" /> {text}</p></Panel>;
}
