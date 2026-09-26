import type { Metadata } from "next";
import Image from "next/image";
import * as LucideIcons from "lucide-react";
import SectionHeading from "@/components/section-heading";
import Reveal from "@/components/reveal";
import Accordion from "@/components/accordion";
import CtaBand from "@/components/cta-band";
import AuroraBg from "@/components/aurora-bg";
import HeroCollage from "@/components/hero-collage";
import Parallax from "@/components/parallax";
import ThreeWaysTabs from "@/components/three-ways-tabs";
import ShowroomIllustration from "@/components/showroom-illustration";
import PricingIllustration from "@/components/pricing-illustration";
import MobileIllustration from "@/components/mobile-illustration";
import { MobileShot } from "@/components/app-shot";
import { desktopShots, mobileShots } from "@/lib/shots";
import MagneticButton from "@/components/magnetic-button";
import { getPageContentMap, getPageSeo, buildPageMetadata } from "@/lib/cms";
import { cmsIcon, type CmsItem } from "@/lib/cms-types";

export async function generateMetadata(): Promise<Metadata> {
  const seo = await getPageSeo("/dukania");
  return buildPageMetadata(seo);
}

export default async function DukaniaPage() {
  const content = await getPageContentMap("dukania");
  const seo = await getPageSeo("/dukania");

  const heroContent = content.hero?.content || {
    eyebrow: "Softraxa product",
    title: "Inventory & billing that puts you in control.",
    lead: "Know exactly what's in stock, bill online or completely offline, and reorder before you run out — with Dukania.",
    primary_cta: "Book a free demo",
    secondary_cta: "Watch it work"
  };

  const compareItems = content.compare?.items || [
    "Bill a customer with no internet",
    "Spot low stock instantly",
    "Track expiry dates automatically",
    "GST reports in one tap",
    "Staff logins with limited access",
    "Sync across desktop and mobile",
  ];

  const builtinItems = content.builtin?.items || [
    { icon: "ScanLine", title: "Barcode scanning", body: "Scan to bill and to add stock — no add-on hardware app to wire up." },
    { icon: "BarChart3", title: "Reports & GST", body: "Sales, profit, stock value and GST, all exportable as a clean PDF." },
    { icon: "Boxes", title: "Android + Windows", body: "Run it on the counter desktop and in your pocket, in sync." },
  ];

  const faqItems = content.faqs?.items || [
    { q: "Does it really work with no internet?", a: "Yes. Billing, stock updates and job cards all work fully offline. Once a connection is available, everything syncs automatically in the background — no manual step." },
    { q: "Is my shop's data secure?", a: "Every business's data is isolated at the database level using row-level security, so one shop's data is never visible to another — even on shared infrastructure." },
    { q: "What platforms does Dukania run on?", a: "Dukania runs on Android today, with a Windows desktop build for back-office use. Get in touch if you need something else." },
    { q: "Can my staff have their own logins?", a: "Yes. You can create separate logins for staff with different levels of access, so a billing assistant sees only what they need and the owner keeps full control." },
    { q: "Does it handle GST?", a: "Yes — GST on bills and services, plus a GST report showing output and input tax by rate. You can also raise non-GST bills, cash memos and estimates." },
  ];

  const mobileFeatures = [
    "Check, adjust or transfer stock",
    "Create bills, estimates and cash memos",
    "Bill offline and sync later",
    "Manage purchases and returns",
    "Scan barcodes and share bills",
  ];

  return (
    <>
      {seo.structured_data && Object.keys(seo.structured_data).length > 0 && (
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(seo.structured_data) }}
        />
      )}

      {/* 1 — hero: centered text + full-bleed floating-card collage */}
      <section className="relative overflow-hidden border-b border-hairline">
        <AuroraBg />
        <div className="relative mx-auto max-w-3xl px-6 pt-16 text-center sm:pt-24">
          <Reveal>
            <p className="inline-flex items-center gap-2 rounded-full border border-hairline bg-paper/4 px-3 py-1 font-mono text-xs uppercase tracking-[0.15em] text-amber">
              {heroContent.eyebrow}
            </p>
            <h1 className="mt-6 font-display text-4xl font-bold leading-[1.05] tracking-tight sm:text-6xl">
              {heroContent.title.includes("\n") ? (
                <>
                  <span className="gradient-text">{heroContent.title.split("\n")[0]}</span>
                  <br />
                  {heroContent.title.split("\n").slice(1).join("\n")}
                </>
              ) : (
                <span className="gradient-text">{heroContent.title}</span>
              )}
            </h1>
            <p className="mx-auto mt-6 max-w-xl text-lg text-dim">
              {heroContent.lead}
            </p>
            <div className="mt-8 flex flex-wrap justify-center gap-4">
              <MagneticButton href="/contact">{heroContent.primary_cta} <LucideIcons.ArrowRight className="h-4 w-4" /></MagneticButton>
              <MagneticButton href="#tour" variant="ghost">{heroContent.secondary_cta}</MagneticButton>
            </div>
            <p className="mt-4 font-mono text-xs text-dim">Free demo · No credit card needed</p>
            <div className="mt-6 flex items-center justify-center gap-5 text-sm text-dim">
              <span className="inline-flex items-center gap-1.5"><LucideIcons.Smartphone className="h-4 w-4" /> Android</span>
              <span className="inline-flex items-center gap-1.5"><LucideIcons.Monitor className="h-4 w-4" /> Windows</span>
            </div>
          </Reveal>
        </div>

        {/* full-width floating-card collage */}
        <div className="relative mt-14 w-full pb-12">
          <HeroCollage />
        </div>
      </section>

      {/* 2 — product tour (video-style) */}
      <section id="tour" className="mx-auto max-w-7xl px-6 py-20">
        <SectionHeading eyebrow="Product tour" title="Dukania in 2 minutes." align="center"
          lead="A quick look at billing, stock and reports — the way a shop actually uses it." />
        <Reveal>
          <Parallax amount={30} className="mx-auto mt-12 max-w-4xl">
            <div className="group relative overflow-hidden rounded-2xl border border-hairline shadow-2xl shadow-black/50">
              <Image
                src={desktopShots.salesReport.src}
                width={desktopShots.salesReport.width}
                height={desktopShots.salesReport.height}
                alt={desktopShots.salesReport.alt}
                sizes="(max-width: 1024px) 100vw, 60vw"
                className="h-auto w-full"
              />
              <div className="absolute inset-0 flex items-center justify-center bg-bg/40 backdrop-blur-[1px]">
                <span className="inline-flex h-16 w-16 items-center justify-center rounded-full bg-paper text-bg shadow-xl transition-transform group-hover:scale-105">
                  <LucideIcons.Play className="h-6 w-6 translate-x-0.5 fill-bg" />
                </span>
              </div>
            </div>
          </Parallax>
        </Reveal>
      </section>

      {/* 3 — three ways (interactive tabs) */}
      <section className="mx-auto max-w-7xl px-6 py-20">
        <SectionHeading eyebrow="Faster days" title="Three ways to speed up work." align="center" />
        <div className="mt-12">
          <ThreeWaysTabs />
        </div>
      </section>

      {/* 4 — feature: scan & barcode */}
      <section className="mx-auto max-w-7xl px-6 py-16">
        <div className="grid items-center gap-12 lg:grid-cols-2">
          <Reveal>
            <p className="font-mono text-xs uppercase tracking-[0.2em] text-sky">Barcoding</p>
            <h2 className="mt-3 font-display text-3xl font-bold tracking-tight">Scan a barcode, add to the bill.</h2>
            <p className="mt-4 text-dim">
              No fumbling with product names. Point the camera, scan, and the item drops
              straight into the cart at the right price.
            </p>
            <ul className="mt-6 space-y-3 text-sm">
              {["Scan barcodes at checkout", "Search by name, SKU or barcode", "Print and scan product labels"].map((b) => (
                <li key={b} className="flex items-center gap-2.5 text-paper"><LucideIcons.Check className="h-4 w-4 shrink-0 text-teal" /> {b}</li>
              ))}
            </ul>
            <div className="mt-8"><MagneticButton href="/contact" variant="ghost">Book a demo <LucideIcons.ArrowRight className="h-4 w-4" /></MagneticButton></div>
          </Reveal>
          <Reveal delay={0.12} className="flex justify-center">
            <MobileShot shot={mobileShots.newBill} />
          </Reveal>
        </div>
      </section>

      {/* 5 — feature: offline-first */}
      <section className="mx-auto max-w-7xl px-6 py-16">
        <div className="grid items-center gap-12 lg:grid-cols-2">
          <Reveal className="flex justify-center lg:order-1">
            <MobileShot shot={mobileShots.checkout} />
          </Reveal>
          <Reveal delay={0.12} className="lg:order-2">
            <p className="font-mono text-xs uppercase tracking-[0.2em] text-sky">Offline-first</p>
            <h2 className="mt-3 font-display text-3xl font-bold tracking-tight">Keeps working when the internet doesn&apos;t.</h2>
            <p className="mt-4 text-dim">
              Bill a customer with no signal. Dukania saves everything locally first and
              syncs the moment you&apos;re back online — across cash, UPI, card or credit.
            </p>
            <ul className="mt-6 space-y-3 text-sm">
              {["Every bill saved locally first", "Automatic background sync", "GST, discounts and round-off built in"].map((b) => (
                <li key={b} className="flex items-center gap-2.5 text-paper"><LucideIcons.Check className="h-4 w-4 shrink-0 text-teal" /> {b}</li>
              ))}
            </ul>
          </Reveal>
        </div>
      </section>

      {/* 5b — catalog & estimates */}
      <section className="mx-auto max-w-7xl px-6 py-16">
        <div className="grid items-center gap-12 lg:grid-cols-2">
          <Reveal>
            <p className="font-mono text-xs uppercase tracking-[0.2em] text-sky">Catalog &amp; estimates</p>
            <h2 className="mt-3 font-display text-3xl font-bold tracking-tight">Turn your stock into shareable estimates.</h2>
            <p className="mt-4 text-dim">
              Selling beyond the counter usually means a lot of manual work. Dukania keeps
              your catalog and estimates in one place, so quoting a customer takes seconds.
            </p>
            <div className="mt-8 space-y-6">
              <div>
                <h3 className="font-display text-lg font-semibold">A catalog that keeps up</h3>
                <p className="mt-2 text-sm text-dim">Your live product list stays current automatically — no stale price sheets to reprint every week.</p>
              </div>
              <div>
                <h3 className="font-display text-lg font-semibold">Estimates that become bills</h3>
                <p className="mt-2 text-sm text-dim">Build a cart, save it as an estimate to share, and turn it into a bill the moment the customer says yes.</p>
              </div>
            </div>
          </Reveal>
          <Reveal delay={0.15}>
            <ShowroomIllustration />
          </Reveal>
        </div>
      </section>

      {/* 6 — comparison */}
      <section className="mx-auto max-w-4xl px-6 py-20">
        <SectionHeading eyebrow="The difference" title="By hand vs. with Dukania." align="center" />
        <Reveal>
          <div className="mt-12 overflow-hidden rounded-2xl border border-hairline">
            <div className="grid grid-cols-[1fr_auto_auto] items-center gap-4 border-b border-hairline bg-paper/4 px-6 py-4 text-sm font-semibold">
              <span className="text-dim">Task</span>
              <span className="w-20 text-center text-dim">By hand</span>
              <span className="w-20 text-center text-teal">Dukania</span>
            </div>
            {compareItems.map((row: string, i: number) => (
              <div key={row} className={`grid grid-cols-[1fr_auto_auto] items-center gap-4 px-6 py-4 text-sm ${i % 2 ? "bg-paper/2" : ""}`}>
                <span className="text-paper">{row}</span>
                <span className="flex w-20 justify-center"><LucideIcons.X className="h-5 w-5 text-red-400/70" /></span>
                <span className="flex w-20 justify-center"><LucideIcons.Check className="h-5 w-5 text-teal" /></span>
              </div>
            ))}
          </div>
        </Reveal>
      </section>

      {/* 7 — trial CTA */}
      <section className="mx-auto max-w-7xl px-6 py-16">
        <Reveal>
          <div className="glass relative overflow-hidden rounded-3xl px-8 py-14 text-center sm:px-16">
            <AuroraBg intensity="soft" />
            <div className="relative">
              <h2 className="font-display text-3xl font-bold tracking-tight sm:text-4xl">See Dukania for yourself.</h2>
              <div className="mx-auto mt-8 flex max-w-2xl flex-wrap items-center justify-center gap-x-8 gap-y-3 text-sm text-dim">
                <span className="inline-flex items-center gap-2"><LucideIcons.WifiOff className="h-4 w-4 text-teal" /> Works fully offline</span>
                <span className="inline-flex items-center gap-2"><LucideIcons.ShieldCheck className="h-4 w-4 text-teal" /> Data isolated per business</span>
                <span className="inline-flex items-center gap-2"><LucideIcons.Unlock className="h-4 w-4 text-teal" /> No lock-in — export anytime</span>
              </div>
              <div className="mt-8 flex justify-center">
                <MagneticButton href="/contact">{heroContent.primary_cta} <LucideIcons.ArrowRight className="h-4 w-4" /></MagneticButton>
              </div>
              <p className="mt-4 font-mono text-xs text-dim">Free demo · No credit card needed</p>
            </div>
          </div>
        </Reveal>
      </section>

      {/* 8 — what's built in */}
      <section id="features" className="mx-auto max-w-7xl px-6 py-20">
        <SectionHeading eyebrow="Built in" title="Everything a counter needs, built in."
          lead="No add-ons to buy, no separate tools to wire together." align="center" />
        <div className="mt-12 grid gap-8 sm:grid-cols-3">
          {builtinItems.map((f: CmsItem, i: number) => {
            const IconComponent = cmsIcon(f.icon);
            return (
              <Reveal key={f.title} delay={i * 0.08}>
                <div className="glass h-full rounded-2xl p-6">
                  <div className="inline-flex h-11 w-11 items-center justify-center rounded-xl bg-gradient-to-br from-violet/25 to-sky/20 ring-1 ring-paper/10">
                    <IconComponent className="h-5 w-5 text-sky" aria-hidden="true" />
                  </div>
                  <h3 className="mt-5 font-display text-lg font-semibold">{f.title}</h3>
                  <p className="mt-2 text-sm text-dim">{f.body}</p>
                </div>
              </Reveal>
            );
          })}
        </div>
      </section>

      {/* 9 — mobile showcase */}
      <section className="mx-auto max-w-7xl px-6 py-20">
        <SectionHeading eyebrow="On the go" title="Get more done on the go." align="center"
          lead="Dukania on mobile is the full shop in your pocket — bill, check stock and see reports from anywhere, online or off." />

        <div className="mt-12 grid items-center gap-12 lg:grid-cols-2">
          <Reveal>
            <h3 className="font-display text-2xl font-bold tracking-tight">Dukania app for billing &amp; stock</h3>
            <p className="mt-3 max-w-md text-dim">
              Included on every plan. Built for running the counter and keeping stock
              straight, right from your phone.
            </p>
            <ul className="mt-6 space-y-3.5 text-sm">
              {mobileFeatures.map((b) => (
                <li key={b} className="flex items-center gap-3 text-paper">
                  <span className="inline-flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-teal text-white">
                    <LucideIcons.Check className="h-3.5 w-3.5" />
                  </span>
                  {b}
                </li>
              ))}
            </ul>
          </Reveal>
          <Reveal delay={0.15}>
            <MobileIllustration />
          </Reveal>
        </div>

        <Reveal delay={0.1}>
          <div className="mt-14 flex flex-col items-start gap-6 rounded-3xl bg-elevated p-8 sm:flex-row sm:items-center sm:justify-between">
            <div className="flex items-center gap-4">
              <div className="flex gap-2">
                <span className="inline-flex h-11 w-11 items-center justify-center rounded-xl bg-gradient-to-br from-violet to-sky text-white shadow-lg"><LucideIcons.Smartphone className="h-5 w-5" /></span>
                <span className="inline-flex h-11 w-11 items-center justify-center rounded-xl bg-gradient-to-br from-teal to-sky text-white shadow-lg"><LucideIcons.Monitor className="h-5 w-5" /></span>
              </div>
              <h3 className="font-display text-xl font-bold tracking-tight sm:text-2xl">
                Runs on Android today, Windows for the back office.
              </h3>
            </div>
            <MagneticButton href="/contact">Book a demo <LucideIcons.ArrowRight className="h-4 w-4" /></MagneticButton>
          </div>
        </Reveal>
      </section>

      {/* 10 — pricing */}
      <section className="mx-auto max-w-7xl px-6 py-20">
        <div className="grid items-center gap-12 lg:grid-cols-2">
          <Reveal>
            <p className="font-mono text-xs uppercase tracking-[0.2em] text-sky">Pricing</p>
            <h2 className="mt-3 font-display text-3xl font-bold tracking-tight sm:text-4xl">
              Don&apos;t break the bank on shop software.
            </h2>
            <p className="mt-4 max-w-md text-dim">
              Whether you run one counter or a hundred, it&apos;s easy to find a Dukania
              plan that fits — priced for real shop margins, not enterprise budgets.
            </p>
            <div className="mt-8">
              <MagneticButton href="/contact">Get a quote <LucideIcons.ArrowRight className="h-4 w-4" /></MagneticButton>
            </div>
          </Reveal>
          <Reveal delay={0.15}>
            <PricingIllustration />
          </Reveal>
        </div>
      </section>

      {/* 11 — FAQ */}
      <section id="faq" className="mx-auto max-w-3xl px-6 py-16">
        <SectionHeading eyebrow="FAQ" title="Questions, answered." />
        <div className="mt-10"><Accordion items={faqItems} /></div>
      </section>

      <CtaBand
        title="Ready to see Dukania in your shop?"
        lead="Book a walkthrough and we'll show you exactly how it fits your day."
        cta="Book a free demo"
      />
    </>
  );
}
