"use client";

import { useState } from "react";
import Link from "next/link";
import { Check, Eye, EyeOff, Loader2, Lock, ShieldCheck, Smartphone, Zap } from "lucide-react";
import { signIn } from "@/lib/shop-session";
import { btnPrimary } from "@/lib/ui";

const POINTS: [typeof Zap, string][] = [
  [Zap, "See your plan, days left, logins and payments in one place."],
  [Check, "Renew, upgrade or add staff logins — the app updates by itself."],
  [ShieldCheck, "Payments go through Razorpay. Dukania never sees your card or UPI PIN."],
];

/** The shop owner's sign-in (the same email and password as in the app). */
export default function SignInForm({ note, button = "Sign in", onDone }: {
  note?: string; button?: string; onDone: (token: string) => void;
}) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [show, setShow] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const token = await signIn(email, password);
      if (token) onDone(token);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  const field = "mt-1.5 w-full rounded-xl border border-hairline bg-bg/60 px-4 py-3 text-[15px] text-paper outline-none transition focus:border-brand focus:bg-white focus:ring-4 focus:ring-brand/10";

  return (
    <div className="grid overflow-hidden rounded-3xl border border-hairline bg-white shadow-card lg:grid-cols-[1fr_1.1fr]">
      <div className="relative hidden flex-col justify-between bg-paper p-10 text-white lg:flex">
        <div>
          <p className="font-mono text-xs uppercase tracking-[0.2em] text-marigold">Dukania · Your shop</p>
          <h2 className="mt-4 font-display text-3xl font-bold leading-tight">Your plan, at a glance.<br />Change it in a minute.</h2>
        </div>
        <ul className="mt-10 space-y-5 text-sm text-white/80">
          {POINTS.map(([Icon, text]) => (
            <li key={text} className="flex gap-3">
              <span className="mt-0.5 inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-white/10"><Icon className="h-4 w-4 text-marigold" /></span>
              <span>{text}</span>
            </li>
          ))}
        </ul>
        <p className="mt-10 text-xs text-white/50">For the shop owner. Staff logins can&apos;t manage the plan.</p>
      </div>

      <form onSubmit={submit} className="p-7 sm:p-10">
        <h2 className="font-display text-2xl font-bold text-paper">Sign in to your shop</h2>
        <p className="mt-1.5 text-sm text-dim">Use the owner&apos;s email and password from the Dukania app.</p>

        {note && <p className="mt-5 rounded-xl border border-marigold/40 bg-[#fff8e6] px-4 py-3 text-sm text-paper">{note}</p>}

        <label className="mt-6 block text-sm font-semibold text-paper">
          Email
          <input required type="email" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} className={field} />
        </label>
        <label className="mt-4 block text-sm font-semibold text-paper">
          Password
          <span className="relative block">
            <input required type={show ? "text" : "password"} autoComplete="current-password" value={password}
              onChange={(e) => setPassword(e.target.value)} className={`${field} pr-12`} />
            <button type="button" onClick={() => setShow(!show)} aria-label={show ? "Hide password" : "Show password"}
              className="absolute right-2 top-1/2 mt-[3px] -translate-y-1/2 rounded-lg p-2 text-dim hover:text-paper">
              {show ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
            </button>
          </span>
        </label>

        {error && <p className="mt-4 text-sm font-medium text-red-700">{error}</p>}

        <button type="submit" disabled={busy} className={`${btnPrimary} mt-6 w-full justify-center disabled:opacity-60`}>
          {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Lock className="h-4 w-4" />} {button}
        </button>

        <div className="mt-6 flex items-start gap-3 rounded-xl bg-elevated/60 px-4 py-3 text-xs text-dim">
          <Smartphone className="mt-0.5 h-4 w-4 shrink-0 text-brand" />
          <span>Forgot your password? Reset it on the app&apos;s sign-in screen. New to Dukania? <a href="/download" className="font-semibold text-brand hover:underline">Start a free trial</a>. Influencer partner? <Link href="/partner/login" className="font-semibold text-brand hover:underline">Sign in here</Link>.</span>
        </div>
      </form>
    </div>
  );
}
