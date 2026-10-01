"use client";

import { useState } from "react";
import Link from "next/link";
import Image from "next/image";
import { usePathname } from "next/navigation";
import { Menu, X, ChevronDown, Store, Boxes } from "lucide-react";

const PRODUCT_ITEMS = [
  {
    href: "/dukania",
    label: "Dukania — Retail POS",
    description: "Our flagship inventory, billing and GST application.",
    icon: Store,
    color: "text-amber"
  },
  {
    href: "/products",
    label: "Custom Solutions",
    description: "Bespoke POS, CRM, and operations software built to order.",
    icon: Boxes,
    color: "text-sky"
  }
];

export default function Nav() {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  const [dropdownOpen, setDropdownOpen] = useState(false);

  return (
    <header className="sticky top-0 z-50 border-b border-hairline bg-bg/70 backdrop-blur-xl">
      <div className="mx-auto flex max-w-7xl items-center justify-between px-6 py-4">
        {/* Brand Logo */}
        <Link href="/" className="flex items-center gap-2">
          <Image
            src="/images/logo.png"
            alt="Softraxa"
            width={140}
            height={36}
            className="h-9 w-auto"
            priority
          />
        </Link>

        {/* Desktop Menu */}
        <nav className="hidden items-center gap-8 text-sm text-dim md:flex">
          {/* Home */}
          <Link
            href="/"
            className={`relative transition-colors hover:text-paper ${
              pathname === "/" ? "text-paper" : ""
            }`}
          >
            Home
            {pathname === "/" && (
              <span className="absolute -bottom-1.5 left-0 h-px w-full bg-gradient-to-r from-violet to-sky" />
            )}
          </Link>

          {/* Products Dropdown */}
          <div
            className="relative"
            onMouseEnter={() => setDropdownOpen(true)}
            onMouseLeave={() => setDropdownOpen(false)}
          >
            <button
              className={`flex items-center gap-1 py-2 transition-colors hover:text-paper ${
                pathname === "/dukania" || pathname === "/products" ? "text-paper" : ""
              }`}
              onClick={() => setDropdownOpen((v) => !v)}
              aria-expanded={dropdownOpen}
              aria-haspopup="true"
            >
              Products
              <ChevronDown className={`h-3.5 w-3.5 transition-transform duration-200 ${dropdownOpen ? "rotate-180" : ""}`} />
            </button>

            {/* Dropdown Menu — pt-3 creates an invisible hover bridge so the mouse can travel from the button to the panel */}
            {dropdownOpen && (
              <div className="absolute left-0 top-full z-50 pt-3">
                <div className="w-80 rounded-2xl border border-hairline bg-surface/90 p-3 shadow-xl backdrop-blur-xl">
                  <div className="space-y-1">
                    {PRODUCT_ITEMS.map((item) => (
                      <Link
                        key={item.href}
                        href={item.href}
                        onClick={() => setDropdownOpen(false)}
                        className="flex items-start gap-3 rounded-xl p-3 hover:bg-paper/5 transition-colors group"
                      >
                        <span className={`inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-paper/4 transition-colors group-hover:bg-paper/10 ${item.color}`}>
                          <item.icon className="h-5 w-5" />
                        </span>
                        <div>
                          <p className="font-semibold text-paper text-sm leading-none">{item.label}</p>
                          <p className="mt-1.5 text-xs text-dim leading-relaxed">{item.description}</p>
                        </div>
                      </Link>
                    ))}
                  </div>
                </div>
              </div>
            )}
          </div>

          {/* Pricing */}
          <Link href="/dukania#pricing" className="relative transition-colors hover:text-paper">
            Pricing
          </Link>

          {/* Download */}
          <Link
            href="/download"
            className={`relative transition-colors hover:text-paper ${
              pathname === "/download" ? "text-paper" : ""
            }`}
          >
            Download
          </Link>

          {/* About */}
          <Link
            href="/about"
            className={`relative transition-colors hover:text-paper ${
              pathname === "/about" ? "text-paper" : ""
            }`}
          >
            About
            {pathname === "/about" && (
              <span className="absolute -bottom-1.5 left-0 h-px w-full bg-gradient-to-r from-violet to-sky" />
            )}
          </Link>

          {/* Contact */}
          <Link
            href="/contact"
            className={`relative transition-colors hover:text-paper ${
              pathname === "/contact" ? "text-paper" : ""
            }`}
          >
            Contact
            {pathname === "/contact" && (
              <span className="absolute -bottom-1.5 left-0 h-px w-full bg-gradient-to-r from-violet to-sky" />
            )}
          </Link>
        </nav>

        {/* Demo Consultation CTAs */}
        <div className="flex items-center gap-3">
          <Link
            href="/contact"
            className="stamp-press hidden rounded-lg bg-paper px-4 py-2 text-sm font-semibold text-bg hover:bg-paper/90 sm:inline-flex"
          >
            Book a demo
          </Link>
          <button
            type="button"
            onClick={() => setOpen((v) => !v)}
            className="inline-flex h-10 w-10 items-center justify-center rounded-lg border border-hairline text-paper md:hidden"
            aria-label={open ? "Close menu" : "Open menu"}
            aria-expanded={open}
          >
            {open ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
          </button>
        </div>
      </div>

      {/* Mobile Drawer */}
      {open && (
        <div className="border-t border-hairline bg-surface/95 backdrop-blur-xl md:hidden">
          <nav className="mx-auto flex max-w-7xl flex-col px-6 py-4">
            {/* Home */}
            <Link
              href="/"
              onClick={() => setOpen(false)}
              className={`border-b border-hairline py-3 text-base ${
                pathname === "/" ? "text-paper" : "text-dim"
              }`}
            >
              Home
            </Link>

            {/* Products Nested List */}
            <div className="border-b border-hairline py-3">
              <p className="text-xs uppercase tracking-wider text-dim/60 font-semibold mb-2">Products</p>
              <div className="pl-4 space-y-3 my-1.5">
                <Link
                  href="/dukania"
                  onClick={() => setOpen(false)}
                  className={`block text-base ${
                    pathname === "/dukania" ? "text-paper" : "text-dim"
                  }`}
                >
                  Dukania — Retail POS
                </Link>
                <Link
                  href="/products"
                  onClick={() => setOpen(false)}
                  className={`block text-base ${
                    pathname === "/products" ? "text-paper" : "text-dim"
                  }`}
                >
                  Custom Solutions
                </Link>
              </div>
            </div>

            {/* Pricing */}
            <Link
              href="/dukania#pricing"
              onClick={() => setOpen(false)}
              className="border-b border-hairline py-3 text-base text-dim"
            >
              Pricing
            </Link>

            {/* Download */}
            <Link
              href="/download"
              onClick={() => setOpen(false)}
              className={`border-b border-hairline py-3 text-base ${
                pathname === "/download" ? "text-paper" : "text-dim"
              }`}
            >
              Download
            </Link>

            {/* About */}
            <Link
              href="/about"
              onClick={() => setOpen(false)}
              className={`border-b border-hairline py-3 text-base ${
                pathname === "/about" ? "text-paper" : "text-dim"
              }`}
            >
              About
            </Link>

            {/* Contact */}
            <Link
              href="/contact"
              onClick={() => setOpen(false)}
              className={`border-b border-hairline py-3 text-base ${
                pathname === "/contact" ? "text-paper" : "text-dim"
              }`}
            >
              Contact
            </Link>

            {/* Book Demo Link */}
            <Link
              href="/contact"
              onClick={() => setOpen(false)}
              className="mt-4 inline-flex justify-center rounded-lg bg-paper px-4 py-3 text-sm font-semibold text-bg"
            >
              Book a demo
            </Link>
          </nav>
        </div>
      )}
    </header>
  );
}
