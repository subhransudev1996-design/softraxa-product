import type { Metadata } from "next";
import LoginClient from "@/components/account/login-client";

export const metadata: Metadata = {
  title: "Sign in — Dukania",
  description: "Sign in to see your Dukania plan, renew, upgrade or add staff logins.",
  robots: { index: false, follow: false },
};

/** Shop owners sign in to their account (0106). */
export default async function LoginPage({ searchParams }: { searchParams: Promise<{ next?: string }> }) {
  const { next } = await searchParams;
  // Only our own pages.
  const to = typeof next === "string" && /^\/(account|pay)(\?[\w=:&.-]*)?$/.test(next) ? next : "/account";
  return (
    <section className="mx-auto max-w-6xl px-4 pb-20 pt-10 sm:px-6">
      <h1 className="mb-8 font-display text-3xl font-bold tracking-tight text-paper">Your shop</h1>
      <LoginClient next={to} />
    </section>
  );
}
