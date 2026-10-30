"use client";

import { useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { LogOut, Menu, UserRound, X } from "lucide-react";
import BrandLogo from "@/components/brand-logo";
import { signOut, useSignedIn } from "@/lib/shop-session";

const LINKS = [
  { href: "/features", label: "Features" },
  { href: "/shops", label: "For your shop" },
  { href: "/gst", label: "GST" },
  { href: "/pricing", label: "Pricing" },
  { href: "/ai", label: "AI" },
  { href: "/help", label: "Help" },
  { href: "/contact", label: "Contact" },
];

export default function Nav() {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  // A shop owner signed in on this browser (0106) sees their account, not the trial.
  const signedIn = useSignedIn();
  const router = useRouter();
  async function logout() {
    setOpen(false);
    await signOut();
    router.push("/login");
  }

  return (
    <header className="sticky top-0 z-50 border-b border-hairline bg-bg/85 backdrop-blur-xl">
      <div className="mx-auto flex max-w-7xl items-center justify-between px-6 py-4">
        <Link href="/" aria-label="Dukania home">
          <BrandLogo />
        </Link>

        <nav className="hidden items-center gap-1 rounded-full border border-hairline bg-white/80 p-1 text-sm text-dim shadow-card lg:flex">
          {LINKS.map((l) => (
            <Link
              key={l.href}
              href={l.href}
              className={`rounded-full px-3.5 py-2 transition-colors hover:text-paper ${
                pathname === l.href || pathname.startsWith(`${l.href}/`) ? "bg-brand-soft font-semibold text-brand" : ""
              }`}
            >
              {l.label}
            </Link>
          ))}
        </nav>

        <div className="flex items-center gap-3">
          {signedIn ? (
            <>
              <button type="button" onClick={logout} className="hidden items-center gap-1.5 rounded-xl px-3 py-2.5 text-sm font-semibold text-dim hover:text-paper sm:inline-flex">
                <LogOut className="h-4 w-4" /> Log out
              </button>
              <Link
                href="/account"
                className="stamp-press hidden items-center gap-2 rounded-xl bg-brand px-4 py-2.5 text-sm font-semibold text-white hover:bg-brand-2 sm:inline-flex"
              >
                <UserRound className="h-4 w-4" /> My account
              </Link>
            </>
          ) : (
            <>
              <Link href="/login" className="hidden rounded-xl px-3 py-2.5 text-sm font-semibold text-dim hover:text-paper sm:inline-flex">
                Log in
              </Link>
              <Link
                href="/download"
                className="stamp-press hidden items-center rounded-xl bg-brand px-4 py-2.5 text-sm font-semibold text-white hover:bg-brand-2 sm:inline-flex"
              >
                Start free trial
              </Link>
            </>
          )}
          <button
            type="button"
            onClick={() => setOpen((v) => !v)}
            className="inline-flex h-10 w-10 items-center justify-center rounded-lg border border-hairline text-paper lg:hidden"
            aria-label={open ? "Close menu" : "Open menu"}
            aria-expanded={open}
          >
            {open ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
          </button>
        </div>
      </div>

      {open && (
        <div className="border-t border-hairline bg-surface/95 backdrop-blur-xl lg:hidden">
          <nav className="mx-auto flex max-w-7xl flex-col px-6 py-4">
            {LINKS.map((l) => (
              <Link
                key={l.href}
                href={l.href}
                onClick={() => setOpen(false)}
                className={`border-b border-hairline py-3 text-base ${pathname === l.href ? "text-paper" : "text-dim"}`}
              >
                {l.label}
              </Link>
            ))}
            {signedIn ? (
              <>
                <Link
                  href="/account"
                  onClick={() => setOpen(false)}
                  className="mt-4 inline-flex items-center justify-center gap-2 rounded-xl bg-brand px-4 py-3 text-sm font-semibold text-white"
                >
                  <UserRound className="h-4 w-4" /> My account
                </Link>
                <button type="button" onClick={logout} className="mt-2 inline-flex items-center justify-center gap-2 rounded-xl border border-hairline px-4 py-3 text-sm font-semibold text-paper">
                  <LogOut className="h-4 w-4" /> Log out
                </button>
              </>
            ) : (
              <>
                <Link
                  href="/download"
                  onClick={() => setOpen(false)}
                  className="mt-4 inline-flex justify-center rounded-xl bg-brand px-4 py-3 text-sm font-semibold text-white"
                >
                  Start free trial
                </Link>
                <Link
                  href="/login"
                  onClick={() => setOpen(false)}
                  className="mt-2 inline-flex justify-center rounded-xl border border-hairline px-4 py-3 text-sm font-semibold text-paper"
                >
                  Log in to your shop
                </Link>
              </>
            )}
          </nav>
        </div>
      )}
    </header>
  );
}
