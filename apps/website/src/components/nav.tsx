"use client";

import { useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { Menu, X } from "lucide-react";
import BrandLogo from "@/components/brand-logo";

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
          <Link
            href="/download"
            className="stamp-press hidden items-center rounded-xl bg-brand px-4 py-2.5 text-sm font-semibold text-white hover:bg-brand-2 sm:inline-flex"
          >
            Start free trial
          </Link>
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
            <Link
              href="/download"
              onClick={() => setOpen(false)}
              className="mt-4 inline-flex justify-center rounded-xl bg-brand px-4 py-3 text-sm font-semibold text-white"
            >
              Start free trial
            </Link>
          </nav>
        </div>
      )}
    </header>
  );
}
