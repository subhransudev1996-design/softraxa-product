"use client";

import { useEffect, useState } from "react";
import { createClient, type EmailOtpType } from "@supabase/supabase-js";

type Status = "working" | "success" | "error";

export default function CallbackClient() {
  const [status, setStatus] = useState<Status>("working");
  const [message, setMessage] = useState("");

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
