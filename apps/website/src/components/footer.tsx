import Link from "next/link";
import Image from "next/image";
import { ArrowRight } from "lucide-react";

const COLS = [
  {
    title: "Product",
    links: [
      { href: "/dukania", label: "Dukania" },
      { href: "/dukania#features", label: "Features" },
      { href: "/dukania#faq", label: "FAQ" },
      { href: "/contact", label: "Book a demo" },
    ],
  },
  {
    title: "Company",
    links: [
      { href: "/about", label: "About" },
      { href: "/services", label: "Services" },
      { href: "/products", label: "Work" },
      { href: "/contact", label: "Contact" },
    ],
  },
  {
    title: "Apps we build",
    links: [
      { href: "/dukania", label: "Inventory & POS" },
      { href: "/products", label: "Repair-shop app" },
      { href: "/products", label: "Salon membership" },
      { href: "/products", label: "Real-estate manager" },
    ],
  },
  {
    title: "Built for",
    links: [
      { href: "/dukania", label: "Grocery & kirana" },
      { href: "/dukania", label: "Mobile & electronics" },
      { href: "/dukania", label: "Hardware & building" },
      { href: "/dukania", label: "Repair & service shops" },
    ],
  },
];

// Placeholder social links — owner to replace "#" with real handles.
const SOCIALS: { label: string; href: string; path: string }[] = [
  { label: "WhatsApp", href: "#", path: "M17.47 14.38c-.3-.15-1.76-.87-2.03-.97-.27-.1-.47-.15-.67.15-.2.3-.77.97-.94 1.17-.17.2-.35.22-.65.07-.3-.15-1.26-.46-2.4-1.48-.89-.79-1.49-1.77-1.66-2.07-.17-.3-.02-.46.13-.61.13-.13.3-.35.45-.52.15-.17.2-.3.3-.5.1-.2.05-.37-.02-.52-.07-.15-.67-1.61-.92-2.21-.24-.58-.49-.5-.67-.51h-.57c-.2 0-.52.07-.79.37-.27.3-1.04 1.02-1.04 2.48s1.06 2.88 1.21 3.08c.15.2 2.09 3.2 5.07 4.49.71.31 1.26.49 1.69.63.71.22 1.36.19 1.87.12.57-.09 1.76-.72 2.01-1.41.25-.7.25-1.29.17-1.42-.07-.13-.27-.2-.57-.35zM12.04 21.5a9.5 9.5 0 0 1-4.84-1.33l-.35-.2-3.6.94.96-3.5-.23-.36a9.5 9.5 0 1 1 8.06 4.45z" },
  { label: "Instagram", href: "#", path: "M12 2.16c3.2 0 3.58.01 4.85.07 1.17.05 1.8.25 2.23.41.56.22.96.48 1.38.9.42.42.68.82.9 1.38.16.42.36 1.06.41 2.23.06 1.27.07 1.65.07 4.85s-.01 3.58-.07 4.85c-.05 1.17-.25 1.8-.41 2.23-.22.56-.48.96-.9 1.38-.42.42-.82.68-1.38.9-.42.16-1.06.36-2.23.41-1.27.06-1.65.07-4.85.07s-3.58-.01-4.85-.07c-1.17-.05-1.8-.25-2.23-.41a3.7 3.7 0 0 1-1.38-.9 3.7 3.7 0 0 1-.9-1.38c-.16-.42-.36-1.06-.41-2.23C2.17 15.58 2.16 15.2 2.16 12s.01-3.58.07-4.85c.05-1.17.25-1.8.41-2.23.22-.56.48-.96.9-1.38.42-.42.82-.68 1.38-.9.42-.16 1.06-.36 2.23-.41C8.42 2.17 8.8 2.16 12 2.16zm0 3.68a6.16 6.16 0 1 0 0 12.32 6.16 6.16 0 0 0 0-12.32zm0 10.16a4 4 0 1 1 0-8 4 4 0 0 1 0 8zm6.4-10.4a1.44 1.44 0 1 1-2.88 0 1.44 1.44 0 0 1 2.88 0z" },
  { label: "LinkedIn", href: "#", path: "M20.45 20.45h-3.56v-5.57c0-1.33-.02-3.04-1.85-3.04-1.85 0-2.14 1.45-2.14 2.94v5.67H9.35V9h3.42v1.56h.05c.48-.9 1.64-1.85 3.37-1.85 3.6 0 4.27 2.37 4.27 5.46v6.28zM5.34 7.43a2.07 2.07 0 1 1 0-4.14 2.07 2.07 0 0 1 0 4.14zM7.12 20.45H3.56V9h3.56v11.45zM22.22 0H1.77C.8 0 0 .78 0 1.75v20.5C0 23.22.8 24 1.77 24h20.45c.98 0 1.78-.78 1.78-1.75V1.75C24 .78 23.2 0 22.22 0z" },
  { label: "Facebook", href: "#", path: "M22 12a10 10 0 1 0-11.56 9.88v-6.99H7.9V12h2.54V9.8c0-2.5 1.49-3.89 3.78-3.89 1.09 0 2.24.2 2.24.2v2.46h-1.26c-1.24 0-1.63.77-1.63 1.56V12h2.78l-.44 2.89h-2.34v6.99A10 10 0 0 0 22 12z" },
];

function BrandMark() {
  return (
    <Image
      src="/images/logo.png"
      alt="Softraxa"
      width={120}
      height={32}
      className="h-8 w-auto"
    />
  );
}

export default function Footer() {
  return (
    <footer className="relative mt-10 border-t border-hairline">
      {/* link columns */}
      <div className="mx-auto grid max-w-7xl gap-10 px-6 py-16 sm:grid-cols-2 lg:grid-cols-6">
        <div className="lg:col-span-2">
          <div className="flex items-center gap-2.5 font-display text-lg font-bold">
            <BrandMark />
          </div>
          <p className="mt-4 max-w-xs text-sm text-dim">
            A software agency building practical, offline-first business software.
            Makers of Dukania.
          </p>
        </div>

        {COLS.map((col) => (
          <div key={col.title}>
            <h3 className="font-mono text-xs uppercase tracking-widest text-dim">{col.title}</h3>
            <ul className="mt-4 space-y-3 text-sm">
              {col.links.map((l) => (
                <li key={l.href + l.label}>
                  <Link href={l.href} className="text-dim transition-colors hover:text-paper">
                    {l.label}
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>

      {/* promo / trial row */}
      <div className="border-t border-hairline">
        <div className="mx-auto flex max-w-7xl flex-col gap-6 px-6 py-8 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex items-center gap-3">
            <BrandMark />
            <p className="text-sm text-dim">
              Softraxa builds offline-first business software for India.
            </p>
          </div>
          <div className="flex items-center gap-5">
            <div className="text-right">
              <p className="text-sm font-semibold text-paper">Book a free demo</p>
              <p className="text-xs text-dim">No credit card needed.</p>
            </div>
            <Link
              href="/contact"
              className="stamp-press inline-flex min-h-11 items-center gap-2 rounded-lg bg-paper px-5 text-sm font-semibold text-bg hover:bg-paper/90"
            >
              Get started <ArrowRight className="h-4 w-4" />
            </Link>
          </div>
        </div>
      </div>

      {/* legal / social bottom bar */}
      <div className="border-t border-hairline">
        <div className="mx-auto flex max-w-7xl flex-col gap-4 px-6 py-6 text-xs text-dim sm:flex-row sm:items-center sm:justify-between">
          <div className="flex flex-wrap items-center gap-x-5 gap-y-2">
            <span>© {new Date().getFullYear()} Softraxa. All rights reserved.</span>
            {/* placeholder legal links — wire up real pages when ready */}
            <Link href="#" className="hover:text-paper">Privacy</Link>
            <Link href="#" className="hover:text-paper">Terms</Link>
          </div>

          <div className="flex items-center gap-3">
            {SOCIALS.map((s) => (
              <a
                key={s.label}
                href={s.href}
                aria-label={s.label}
                className="inline-flex h-9 w-9 items-center justify-center rounded-lg border border-hairline text-dim transition-colors hover:border-white/15 hover:text-paper"
              >
                <svg viewBox="0 0 24 24" className="h-4 w-4" fill="currentColor" aria-hidden="true">
                  <path d={s.path} />
                </svg>
              </a>
            ))}
          </div>
        </div>
      </div>
    </footer>
  );
}
