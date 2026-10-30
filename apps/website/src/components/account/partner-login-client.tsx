"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Eye, EyeOff, Loader2, Lock } from "lucide-react";
import { supabase } from "@/lib/supabase-client";
import { btnPrimary } from "@/lib/ui";

/** dukania.in/partner/login — an influencer partner signs in (migration 0107). */
export default function PartnerLoginClient() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [show, setShow] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const { error: authError } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    if (authError) {
      setBusy(false);
      return setError(authError.message.includes("Invalid") ? "That email and password don't match a partner login." : authError.message);
    }
    const { data } = await supabase.rpc("my_partner");
    if (!data) {
      await supabase.auth.signOut();
      setBusy(false);
      return setError("This login isn't a Dukania partner. Shop owners sign in on the Log in page.");
    }
    router.replace("/partner/me");
  }

  const field = "mt-1.5 w-full rounded-xl border border-hairline bg-bg/60 px-4 py-3 text-[15px] text-paper outline-none transition focus:border-brand focus:bg-white focus:ring-4 focus:ring-brand/10";

  return (
    <form onSubmit={submit} className="mx-auto max-w-md rounded-3xl border border-hairline bg-white p-7 shadow-card sm:p-10">
      <h1 className="font-display text-2xl font-bold text-paper">Partner sign in</h1>
      <p className="mt-1.5 text-sm text-dim">See your clicks, shops and earnings. Use the login Dukania sent you on WhatsApp.</p>
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
        {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Lock className="h-4 w-4" />} Sign in
      </button>
      <p className="mt-5 text-xs text-dim">Forgot your password? Message Dukania on WhatsApp and we&apos;ll send you a new one.</p>
    </form>
  );
}
