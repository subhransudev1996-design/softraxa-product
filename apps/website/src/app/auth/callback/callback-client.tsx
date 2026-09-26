"use client";

import { useEffect, useRef, useState, type FormEvent } from "react";
import { createClient, type EmailOtpType, type SupabaseClient } from "@supabase/supabase-js";

// "reset": a verified password-recovery link — ask for the new password.
// "reset-done": the password was changed.
type Status = "working" | "success" | "reset" | "reset-done" | "error";

const MIN_PASSWORD = 8;

export default function CallbackClient() {
  const [status, setStatus] = useState<Status>("working");
  const [message, setMessage] = useState("");
  // The recovery link's session lives only in this in-memory client (nothing
  // is persisted in the browser); it is used once, to set the new password.
  const clientRef = useRef<SupabaseClient | null>(null);
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [formError, setFormError] = useState("");
  const [saving, setSaving] = useState(false);

  async function savePassword(e: FormEvent) {
    e.preventDefault();
    if (password.length < MIN_PASSWORD) {
      setFormError(`Use at least ${MIN_PASSWORD} characters.`);
      return;
    }
    if (password !== confirm) {
      setFormError("The two passwords don't match.");
      return;
    }
    const supabase = clientRef.current;
    if (!supabase) {
      setFormError("This reset link has expired. Request a new one from the app.");
      return;
    }
    setSaving(true);
    setFormError("");
    const { error } = await supabase.auth.updateUser({ password });
    setSaving(false);
    if (error) {
      setFormError(error.message);
      return;
    }
    await supabase.auth.signOut();
    clientRef.current = null;
    setStatus("reset-done");
  }

  useEffect(() => {
    let active = true;

    async function run() {
      const url = new URL(window.location.href);
      const params = url.searchParams;
      const errorDescription = params.get("error_description");
      // Signup/reset started in the APP but the link opens in the BROWSER, so
      // there is no PKCE verifier here. The token_hash (OTP) flow is the one
      // that verifies standalone — no prior local state needed.
      const tokenHash = params.get("token_hash");
      const type = (params.get("type") as EmailOtpType | null) ?? "email";
      const code = params.get("code");

      // Supabase can redirect back with an error (expired/invalid link).
      if (errorDescription) {
        fail(decodeURIComponent(errorDescription));
        return;
      }

      if (!tokenHash && !code) {
        fail("This link is missing its verification token. It may have already been used.");
        return;
      }

      // No session persisted — the browser page just confirms the account; the
      // user then logs in from the Dukania app. `implicit` flow so the client
      // never looks for a PKCE verifier that isn't here.
      const supabase = createClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        { auth: { detectSessionInUrl: false, persistSession: false, flowType: "implicit" } }
      );

      const { error } = tokenHash
        ? await supabase.auth.verifyOtp({ token_hash: tokenHash, type })
        : await supabase.auth.exchangeCodeForSession(code!);

      if (!active) return;
      if (error) {
        fail(
          error.message.toLowerCase().includes("expired")
            ? "This link has expired. Please request a new one from the app."
            : error.message
        );
      } else if (type === "recovery") {
        clientRef.current = supabase;
        setStatus("reset");
      } else {
        setStatus("success");
      }
    }

    function fail(msg: string) {
      if (!active) return;
      setStatus("error");
      setMessage(msg);
    }

    run();
    return () => {
      active = false;
    };
  }, []);

  return (
    <main className="grid min-h-screen place-items-center px-6 py-16">
      <div className="w-full max-w-md rounded-2xl border border-black/10 bg-white p-8 text-center shadow-sm dark:border-white/10 dark:bg-neutral-900">
        {status === "working" && (
          <>
            <Spinner />
            <h1 className="mt-5 text-xl font-semibold">Verifying your email…</h1>
            <p className="mt-2 text-sm text-neutral-500">One moment.</p>
          </>
        )}

        {status === "success" && (
          <>
            <div className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-emerald-100 text-emerald-600 dark:bg-emerald-900/40">
              <CheckIcon />
            </div>
            <h1 className="mt-5 text-xl font-semibold">Email verified ✅</h1>
            <p className="mt-2 text-sm leading-6 text-neutral-500">
              Your account is confirmed. Open the <strong>Dukania</strong> app and log in
              with your email and password.
            </p>
          </>
        )}

        {status === "reset" && (
          <form onSubmit={savePassword} className="text-left">
            <h1 className="text-center text-xl font-semibold">Set a new password</h1>
            <p className="mt-2 text-center text-sm text-neutral-500">
              Choose the password you&apos;ll use to log in to the Dukania app.
            </p>
            <label className="mt-6 block text-sm font-medium" htmlFor="new-password">
              New password
            </label>
            <input
              id="new-password"
              type="password"
              autoComplete="new-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="mt-1 w-full rounded-lg border border-black/15 bg-transparent px-3 py-2 text-sm dark:border-white/20"
              minLength={MIN_PASSWORD}
              required
            />
            <label className="mt-4 block text-sm font-medium" htmlFor="confirm-password">
              Confirm new password
            </label>
            <input
              id="confirm-password"
              type="password"
              autoComplete="new-password"
              value={confirm}
              onChange={(e) => setConfirm(e.target.value)}
              className="mt-1 w-full rounded-lg border border-black/15 bg-transparent px-3 py-2 text-sm dark:border-white/20"
              minLength={MIN_PASSWORD}
              required
            />
            {formError && (
              <p className="mt-3 text-sm text-red-600" role="alert">
                {formError}
              </p>
            )}
            <button
              type="submit"
              disabled={saving}
              className="mt-6 w-full rounded-lg bg-neutral-900 px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-60 dark:bg-white dark:text-neutral-900"
            >
              {saving ? "Saving…" : "Save new password"}
            </button>
          </form>
        )}

        {status === "reset-done" && (
          <>
            <div className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-emerald-100 text-emerald-600 dark:bg-emerald-900/40">
              <CheckIcon />
            </div>
            <h1 className="mt-5 text-xl font-semibold">Password changed ✅</h1>
            <p className="mt-2 text-sm leading-6 text-neutral-500">
              Open the <strong>Dukania</strong> app and log in with your new password.
            </p>
          </>
        )}

        {status === "error" && (
          <>
            <div className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-red-100 text-red-600 dark:bg-red-900/40">
              <XIcon />
            </div>
            <h1 className="mt-5 text-xl font-semibold">Verification failed</h1>
            <p className="mt-2 text-sm leading-6 text-neutral-500">{message}</p>
            <p className="mt-4 text-xs text-neutral-400">
              Open the Dukania app, try logging in, and use “Resend verification email”.
            </p>
          </>
        )}
      </div>
    </main>
  );
}

function Spinner() {
  return (
    <div
      className="mx-auto h-10 w-10 animate-spin rounded-full border-[3px] border-neutral-200 border-t-neutral-800 dark:border-neutral-700 dark:border-t-neutral-100 motion-reduce:animate-none"
      role="status"
      aria-label="Loading"
    />
  );
}

function CheckIcon() {
  return (
    <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M20 6 9 17l-5-5" />
    </svg>
  );
}

function XIcon() {
  return (
    <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M18 6 6 18M6 6l12 12" />
    </svg>
  );
}
