"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Button, Input, Label } from "@/components/ui";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  // Two-step login: after the password, the 6-digit code from the authenticator app.
  const [step, setStep] = useState<"password" | "code">("password");
  const [code, setCode] = useState("");

  // Password already given but the code is still needed (the panel sends you back here).
  useEffect(() => {
    createClient().auth.mfa.getAuthenticatorAssuranceLevel().then(({ data }) => {
      if (data?.nextLevel === "aal2" && data.currentLevel !== "aal2") setStep("code");
    });
  }, []);

  /** Into the panel if this login is on the admin team (migration 0098). */
  async function enter() {
    const supabase = createClient();
    const { data: me } = await supabase.rpc("admin_me");
    if (!me) {
      await supabase.auth.signOut();
      setStep("password");
      setError("This login is not on the Dukania admin team, or it has been removed.");
      setBusy(false);
      return;
    }
    router.push("/");
    router.refresh();
  }

  async function login(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) {
      setError(error.message);
      setBusy(false);
      return;
    }
    const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
    if (aal?.nextLevel === "aal2" && aal.currentLevel !== "aal2") {
      setStep("code");
      setBusy(false);
      return;
    }
    await enter();
  }

  async function verify(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const supabase = createClient();
    const { data: factors } = await supabase.auth.mfa.listFactors();
    const factor = factors?.totp?.[0];
    if (!factor) {
      setError("No authenticator app is set up for this login. Sign in again.");
      setBusy(false);
      return;
    }
    const { error } = await supabase.auth.mfa.challengeAndVerify({ factorId: factor.id, code: code.trim() });
    if (error) {
      setError("That code didn't work. Check the time on your phone and try the newest code.");
      setBusy(false);
      return;
    }
    await enter();
  }

  async function startOver() {
    await createClient().auth.signOut();
    setStep("password");
    setCode("");
    setError(null);
  }

  return (
    <main className="flex min-h-screen">
      <aside className="dot-grid relative hidden w-[44%] flex-col justify-between bg-sidebar p-12 lg:flex">
        <div className="flex items-center gap-3">
          <span className="grid h-10 w-10 place-items-center rounded-lg bg-marigold text-lg font-extrabold text-sidebar">D</span>
          <p className="text-lg font-bold text-white">Dukania <span className="font-medium text-sidebar-muted">Admin</span></p>
        </div>
        <div>
          <h2 className="max-w-md text-4xl font-bold leading-tight tracking-tight text-white">
            Every shop, every rupee, <span className="text-marigold">one workspace.</span>
          </h2>
          <ul className="mt-8 space-y-3 text-sm text-sidebar-muted">
            <li>Clients, renewals and support</li>
            <li>Leads, marketing and influencers</li>
            <li>Payments, sales and accounts</li>
          </ul>
        </div>
        <p className="text-xs text-sidebar-muted">© {new Date().getFullYear()} Dukania</p>
      </aside>
      <section className="flex flex-1 items-center justify-center bg-canvas p-6">
        <div className="w-full max-w-sm">
        <div className="mb-6 flex items-center gap-2.5 lg:hidden">
          <span className="grid h-8 w-8 place-items-center rounded-lg bg-marigold text-sm font-extrabold text-sidebar">D</span>
          <p className="text-sm font-bold text-ink">Dukania <span className="font-medium text-zinc-500">Admin</span></p>
        </div>
        <div className="rounded-xl border border-zinc-200/80 bg-white p-7 shadow-[0_1px_2px_rgba(23,19,43,0.05)]">
          <h1 className="text-2xl font-bold tracking-tight text-ink">
            {step === "code" ? "Enter your code" : "Sign in"}
          </h1>
          <p className="mb-5 mt-1 text-sm text-zinc-500">
            {step === "code"
              ? "Open your authenticator app and type the 6-digit code for Dukania admin."
              : "For the Dukania team."}
          </p>
          {step === "code" ? (
            <form onSubmit={verify} className="space-y-4">
              <div>
                <Label>6-digit code</Label>
                <Input
                  inputMode="numeric"
                  autoComplete="one-time-code"
                  autoFocus
                  maxLength={6}
                  value={code}
                  onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
                  placeholder="123456"
                  required
                />
              </div>
              {error && (
                <p className="rounded-lg bg-red-50 px-3.5 py-2.5 text-sm font-medium text-red-700">{error}</p>
              )}
              <Button type="submit" disabled={busy || code.length !== 6} className="w-full justify-center py-2.5">
                {busy ? "Checking…" : "Continue"}
              </Button>
              <button type="button" onClick={startOver} className="w-full text-center text-sm font-semibold text-zinc-500 hover:text-ink">
                Use a different login
              </button>
            </form>
          ) : (
          <form onSubmit={login} className="space-y-4">
            <div>
              <Label>Email</Label>
              <Input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@dukania.in"
                required
              />
            </div>
            <div>
              <Label>Password</Label>
              <Input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                required
              />
            </div>
            {error && (
              <p className="rounded-lg bg-red-50 px-3.5 py-2.5 text-sm font-medium text-red-700">
                {error}
              </p>
            )}
            <Button type="submit" disabled={busy} className="w-full justify-center py-2.5">
              {busy ? "Signing in…" : "Sign in"}
            </Button>
          </form>
          )}
        </div>
        </div>
      </section>
    </main>
  );
}
