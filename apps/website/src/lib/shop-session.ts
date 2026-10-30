"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase-client";

/* A shop owner signed in on dukania.in (migrations 0105, 0106). The
   Supabase session says who they are; a 2-hour pay link token (from the
   session, or from the app's ?t=…) is what the razorpay function uses. */

const TOKEN_KEY = "dk_pay_token";
const FN = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/razorpay`;

export type FnError = Error & { expired?: boolean; off?: boolean };

/** Calls the razorpay function. Errors carry `expired` / `off` flags. */
export async function callFn(action: string, token: string, extra: Record<string, unknown> = {}) {
  const res = await fetch(FN, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "" },
    body: JSON.stringify({ action, token, ...extra }),
  });
  const data = await res.json().catch(() => ({ error: "Something went wrong — try again" }));
  if (!res.ok) throw Object.assign(new Error(data.error ?? "Something went wrong"), data) as FnError;
  return data;
}

export function savedToken(): string | null {
  try {
    return sessionStorage.getItem(TOKEN_KEY);
  } catch {
    return null;
  }
}

export function saveToken(token: string | null) {
  try {
    if (token) sessionStorage.setItem(TOKEN_KEY, token);
    else sessionStorage.removeItem(TOKEN_KEY);
  } catch {
    // Private mode: the token lives only in memory.
  }
}

/** A fresh pay link token from the signed-in session, or null when not signed in. */
export async function tokenFromSession(): Promise<string | null> {
  const { data } = await supabase.auth.getSession();
  if (!data.session) return null;
  const { data: token, error } = await supabase.rpc("create_pay_link");
  if (error) throw new Error(error.message);
  saveToken(String(token));
  return String(token);
}

/** Calls the function with the saved token; on an expired token, makes a new one from the session once. */
export async function callWithSession(action: string, extra: Record<string, unknown> = {}) {
  let token = savedToken() ?? (await tokenFromSession());
  if (!token) throw Object.assign(new Error("Please sign in"), { expired: true }) as FnError;
  try {
    return await callFn(action, token, extra);
  } catch (e) {
    if (!(e as FnError).expired) throw e;
    saveToken(null);
    token = await tokenFromSession();
    if (!token) throw e;
    return callFn(action, token, extra);
  }
}

export async function signIn(email: string, password: string) {
  const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
  if (error) throw new Error(error.message.includes("Invalid") ? "That email and password don't match a Dukania account." : error.message);
  // Only an owner gets a link; anyone else is signed out again.
  try {
    return await tokenFromSession();
  } catch (e) {
    // An influencer partner on the shop login: their page is elsewhere (0107).
    const { data: partner } = await supabase.rpc("my_partner");
    if (partner) {
      window.location.assign("/partner/me");
      return null;
    }
    await supabase.auth.signOut();
    throw e;
  }
}

export async function signOut() {
  saveToken(null);
  await supabase.auth.signOut();
}

/** Is someone signed in on this browser? null while checking. */
export function useSignedIn(): boolean | null {
  const [signedIn, setSignedIn] = useState<boolean | null>(null);
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSignedIn(Boolean(data.session)));
    const { data } = supabase.auth.onAuthStateChange((_e, session) => setSignedIn(Boolean(session)));
    return () => data.subscription.unsubscribe();
  }, []);
  return signedIn;
}
