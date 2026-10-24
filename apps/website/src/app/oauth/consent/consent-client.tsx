"use client";

import { useEffect, useMemo, useState, type FormEvent } from "react";
import { createClient, type OAuthAuthorizationDetails } from "@supabase/supabase-js";

type Step = "loading" | "login" | "consent" | "working" | "error" | "not-admin";

export default function ConsentClient() {
  // Its own session, kept only for this page (not the CMS's login).
  const supabase = useMemo(
    () =>
      createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
        auth: { storageKey: "dukania-oauth-consent", persistSession: true },
      }),
    [],
  );
  const [step, setStep] = useState<Step>("loading");
  const [message, setMessage] = useState("");
  const [details, setDetails] = useState<OAuthAuthorizationDetails | null>(null);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [formError, setFormError] = useState("");
  const [authorizationId, setAuthorizationId] = useState("");

  async function load(id: string) {
    setStep("loading");
    const { data: user } = await supabase.auth.getUser();
    if (!user.user) {
      setStep("login");
      return;
    }
    // Only SOFTRAXA admins may connect an AI app to the admin panel.
    const { data: profile } = await supabase.from("profiles").select("role").eq("id", user.user.id).maybeSingle();
    if (profile?.role !== "admin") {
      setStep("not-admin");
      return;
    }
    const { data, error } = await supabase.auth.oauth.getAuthorizationDetails(id);
    if (error || !data) {
      setMessage(error?.message ?? "This connection request has expired. Start again from the AI app.");
      setStep("error");
      return;
    }
    if (!("authorization_id" in data)) {
      // Allowed before: straight back to the app.
      window.location.href = data.redirect_url;
      return;
    }
    setDetails(data);
    setStep("consent");
  }

  async function start() {
    const id = new URL(window.location.href).searchParams.get("authorization_id") ?? "";
    setAuthorizationId(id);
    if (!id) {
      setMessage("This page is opened by ChatGPT or Claude when you connect them to Dukania Admin.");
      setStep("error");
      return;
    }
    await load(id);
  }

  useEffect(() => {
    // After the first paint: the address is only known in the browser.
    const t = setTimeout(start, 0);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function signIn(e: FormEvent) {
    e.preventDefault();
    setFormError("");
    setStep("working");
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    if (error) {
      setFormError(error.message);
      setStep("login");
      return;
    }
    setPassword("");
    await load(authorizationId);
  }

  async function decide(approve: boolean) {
    setStep("working");
    const { data, error } = approve
      ? await supabase.auth.oauth.approveAuthorization(authorizationId)
      : await supabase.auth.oauth.denyAuthorization(authorizationId);
    if (error || !data) {
      setMessage(error?.message ?? "Something went wrong. Start again from the AI app.");
      setStep("error");
      return;
    }
    window.location.href = data.redirect_url;
  }

  async function signOut() {
    await supabase.auth.signOut();
    setStep("login");
  }

  const input =
    "mt-1 w-full rounded-lg border border-black/15 bg-transparent px-3 py-2 text-sm dark:border-white/20";
  const primary =
    "w-full rounded-lg bg-neutral-900 px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-60 dark:bg-white dark:text-neutral-900";
  const secondary =
    "w-full rounded-lg border border-black/15 px-4 py-2.5 text-sm font-semibold dark:border-white/20";

  return (
    <main className="grid min-h-screen place-items-center px-6 py-16">
      <div className="w-full max-w-md rounded-2xl border border-black/10 bg-white p-8 shadow-sm dark:border-white/10 dark:bg-neutral-900">
        <p className="text-center text-xs font-semibold uppercase tracking-wider text-neutral-500">Dukania Admin</p>

        {(step === "loading" || step === "working") && (
          <div className="py-10 text-center">
            <div className="mx-auto h-10 w-10 animate-spin rounded-full border-[3px] border-neutral-200 border-t-neutral-800 dark:border-neutral-700 dark:border-t-neutral-100 motion-reduce:animate-none" />
            <p className="mt-4 text-sm text-neutral-500">One moment…</p>
          </div>
        )}

        {step === "login" && (
          <form onSubmit={signIn}>
            <h1 className="mt-3 text-center text-xl font-semibold">Sign in to connect</h1>
            <p className="mt-2 text-center text-sm leading-6 text-neutral-500">
              An AI app wants to use your Dukania admin panel. Sign in with your admin account first.
            </p>
            <label className="mt-6 block text-sm font-medium" htmlFor="email">Email</label>
            <input id="email" type="email" autoComplete="email" required value={email}
              onChange={(e) => setEmail(e.target.value)} className={input} />
            <label className="mt-4 block text-sm font-medium" htmlFor="password">Password</label>
            <input id="password" type="password" autoComplete="current-password" required value={password}
              onChange={(e) => setPassword(e.target.value)} className={input} />
            {formError && <p className="mt-3 text-sm text-red-600" role="alert">{formError}</p>}
            <button type="submit" className={`mt-6 ${primary}`}>Sign in</button>
          </form>
        )}

        {step === "consent" && details && (
          <div>
            <h1 className="mt-3 text-center text-xl font-semibold">
              Allow {details.client.name || "this app"} to manage Dukania?
            </h1>
            <p className="mt-2 text-center text-sm text-neutral-500">Signed in as {details.user.email}</p>
            <div className="mt-6 space-y-3 rounded-xl bg-neutral-50 p-4 text-sm leading-6 dark:bg-neutral-800/60">
              <p><strong>It can read</strong> your clients, subscriptions, payments, payment claims, support tickets, leads, plans, master products, health checks and the audit log.</p>
              <p><strong>It can act</strong> — renew subscriptions, suspend or restore shops, change features, reply to tickets, add notes — but only after showing you a preview and you saying yes in the chat. Every action is in the audit log.</p>
              <p className="text-neutral-500">It never sees passwords or keys. You can disconnect it any time from the AI app.</p>
            </div>
            <p className="mt-4 break-all text-xs text-neutral-400">Sends you back to: {details.redirect_uri}</p>
            <div className="mt-6 grid gap-3">
              <button type="button" onClick={() => decide(true)} className={primary}>Allow</button>
              <button type="button" onClick={() => decide(false)} className={secondary}>Deny</button>
            </div>
            <button type="button" onClick={signOut} className="mt-4 w-full text-center text-xs text-neutral-500 underline">
              Not you? Sign out
            </button>
          </div>
        )}

        {step === "not-admin" && (
          <div className="text-center">
            <h1 className="mt-3 text-xl font-semibold">Admins only</h1>
            <p className="mt-2 text-sm leading-6 text-neutral-500">
              This account isn&apos;t a Dukania admin, so it can&apos;t be connected. Sign in with the admin account.
            </p>
            <button type="button" onClick={signOut} className={`mt-6 ${secondary}`}>Use another account</button>
          </div>
        )}

        {step === "error" && (
          <div className="text-center">
            <h1 className="mt-3 text-xl font-semibold">Can&apos;t connect</h1>
            <p className="mt-2 text-sm leading-6 text-neutral-500">{message}</p>
          </div>
        )}
      </div>
    </main>
  );
}
