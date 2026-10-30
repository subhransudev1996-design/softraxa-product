"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import SignInForm from "@/components/account/sign-in-form";
import { useSignedIn } from "@/lib/shop-session";

/** dukania.in/login — the shop owner signs in, then goes on to their account (or ?next=). */
export default function LoginClient({ next }: { next: string }) {
  const router = useRouter();
  const signedIn = useSignedIn();

  useEffect(() => {
    if (signedIn) router.replace(next);
  }, [signedIn, next, router]);

  if (signedIn !== false) return <div className="h-96 animate-pulse rounded-3xl bg-white/60" />;
  return <SignInForm onDone={() => router.replace(next)} />;
}
