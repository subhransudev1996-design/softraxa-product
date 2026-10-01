import type { Metadata } from "next";
import * as LucideIcons from "lucide-react";
import SectionHeading from "@/components/section-heading";
import Reveal from "@/components/reveal";
import Accordion from "@/components/accordion";
import CtaBand from "@/components/cta-band";
import AuroraBg from "@/components/aurora-bg";
import ThreeWaysTabs from "@/components/three-ways-tabs";
import ScreenshotTabs from "@/components/screenshot-tabs";
import { DesktopShot, MobileShot } from "@/components/app-shot";
import { desktopShots, mobileShots } from "@/lib/shots";
import MagneticButton from "@/components/magnetic-button";
import { getPageContentMap, getPageSeo, buildPageMetadata } from "@/lib/cms";
import { getSiteInfo, whatsappLink, rupees } from "@/lib/site-info";

export async function generateMetadata(): Promise<Metadata> {
  const seo = await getPageSeo("/dukania");
  return buildPageMetadata(seo);
}

// Everything below is what the app does today — keep it that way: no
// feature goes on this page before it ships.
const FEATURES: { icon: keyof typeof LucideIcons; title: string; body: string }[] = [
  { icon: "ReceiptText", title: "Fast billing", body: "GST bills, non-GST bills, cash memos and estimates. Keyboard shortcuts on Windows, one-tap add on the phone." },
  { icon: "WifiOff", title: "Works without internet", body: "Bills are saved on the device and sync on their own when the connection is back." },
  { icon: "ScanLine", title: "Barcode scanning", body: "Scan with the phone camera or a USB scanner. Weighing-scale labels for loose goods too." },
  { icon: "Boxes", title: "Stock & low-stock alerts", body: "Live stock for every product and variant, low and out-of-stock lists, stock adjustments." },
  { icon: "CalendarClock", title: "Expiry tracking", body: "Know which products expire soon before they turn into a loss." },
  { icon: "Landmark", title: "GST returns", body: "GSTR-1 and GSTR-3B summaries, HSN codes, CGST/SGST/IGST — ready for your accountant." },
  { icon: "Users", title: "Customers & khata", body: "Credit sales, part payments and dues for each customer — your udhaar book, digital." },
  { icon: "Truck", title: "Purchases & suppliers", body: "Record purchases, track what you owe each supplier, and handle purchase returns." },
  { icon: "Undo2", title: "Returns & exchanges", body: "Sale returns, credit notes and exchanges that keep stock and money right." },
  { icon: "ShieldCheck", title: "Staff logins & approvals", body: "Each staff member sees only what you allow. Below-cost sales and big discounts wait for your OK." },
  { icon: "Printer", title: "Print & share bills", body: "Bluetooth thermal printers from the phone, any printer from Windows, PDF bills on WhatsApp." },
  { icon: "Wrench", title: "Job cards for repairs", body: "Take in devices or vehicles, give estimates, track repairs and bill parts and labour." },
  { icon: "Wallet", title: "Cashbook & expenses", body: "Cash in the drawer, day closing, and every shop expense in one place." },
  { icon: "BarChart3", title: "Reports", body: "Sales, profit, stock value, dues, purchases and expenses — on screen or exported." },
  { icon: "PackageSearch", title: "Ready product list", body: "Pick common products from our shared list instead of typing every name and detail." },
  { icon: "FileSpreadsheet", title: "Excel import & export", body: "Bring your products, customers and suppliers in from Excel — and take all your data out any time." },
];

const SHOP_TYPES: { icon: keyof typeof LucideIcons; title: string; points: string[] }[] = [
  { icon: "Smartphone", title: "Mobile & electronics", points: ["IMEI / serial number on every bill", "Variants like colour and storage", "Repair job cards"] },
  { icon: "Hammer", title: "Hardware & electrical", points: ["Sell by metre, kg or piece", "Cut wire and pipe from the roll", "Big product lists with fast search"] },
  { icon: "Shirt", title: "Garments & footwear", points: ["Sizes and colours as variants", "Barcode billing at the counter", "Exchanges without the paperwork"] },
  { icon: "ShoppingBasket", title: "Grocery & kirana", points: ["Loose items by weight or ₹ amount", "Weighing-scale barcodes", "Customer khata and dues"] },
  { icon: "Car", title: "Car & bike workshops", points: ["Vehicle job cards", "Parts and labour on one bill", "Estimates the customer approves"] },
  { icon: "Store", title: "Any retail counter", points: ["GST billing from day one", "Stock that stays right", "Works on the phone you already have"] },
];

export default async function DukaniaPage() {
  const content = await getPageContentMap("dukania");
  const seo = await getPageSeo("/dukania");
  const info = await getSiteInfo();

  const hero = content.hero?.content || {};
  const title: string = hero.title || "Inventory & billing\nthat puts you in control.";
  const lead: string =
    hero.lead || "Know exactly what's in stock, bill online or completely offline, and reorder before you run out — with Dukania.";
  const trial = info.trialDays ? `${info.trialDays}-day free trial` : "Free trial";
  const wa = whatsappLink(info, "Hi, I want to know more about Dukania for my shop.");

  const compareItems: string[] = content.compare?.items || [
    "Bill a customer with no internet",
    "Spot low stock instantly",
    "Track expiry dates automatically",
    "GST reports in one tap",
    "Staff logins with limited access",
    "Sync across desktop and mobile",
  ];

  const faqItems = content.faqs?.items || [
    { q: "Is there a free trial?", a: "Yes. Sign up in the app and your shop starts on a free trial straight away — no card, no payment." },
    { q: "Does it really work with no internet?", a: "Yes. Billing works fully offline and syncs automatically once the connection is back." },
    { q: "Does it handle GST?", a: "Yes — GST bills with HSN codes, CGST/SGST/IGST, plus GSTR-1 and GSTR-3B reports." },
  ];

  return (
    <>
      {seo.structured_data && Object.keys(seo.structured_data).length > 0 && (
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(seo.structured_data) }}
        />
      )}

      {/* 1 — hero: the message on the left, the real app on the right, so
          the product is on screen before any scrolling. */}
      <section className="relative overflow-hidden border-b border-hairline">
        <AuroraBg />
        <div className="relative mx-auto grid max-w-7xl items-center gap-12 px-6 pb-20 pt-14 sm:pt-20 lg:grid-cols-[1fr_1.15fr] lg:gap-10 lg:pb-24">
          <Reveal>
            <p className="inline-flex items-center gap-2 rounded-full border border-hairline bg-paper/4 px-3 py-1 font-mono text-[11px] uppercase tracking-[0.15em] text-amber">
              <span className="h-1.5 w-1.5 rounded-full bg-amber" /> Billing &amp; stock software<span className="hidden sm:inline">&nbsp;for Indian shops</span>
            </p>
            <h1 className="mt-6 font-display text-4xl font-bold leading-[1.05] tracking-tight sm:text-5xl xl:text-[3.6rem]">
              {title.includes("\n") ? (
                <>
                  <span className="gradient-text">{title.split("\n")[0]}</span>
                  <br />
                  {title.split("\n").slice(1).join("\n")}
                </>
              ) : (
                <span className="gradient-text">{title}</span>
              )}
            </h1>
            <p className="mt-6 max-w-xl text-lg text-dim">{lead}</p>
            <div className="mt-8 flex flex-wrap gap-3">
              <MagneticButton href="/download">Start free trial <LucideIcons.ArrowRight className="h-4 w-4" /></MagneticButton>
              <MagneticButton href="/contact" variant="ghost">Book a free demo</MagneticButton>
            </div>
            <p className="mt-4 font-mono text-xs text-dim">
              {trial} · No card, no payment{info.fromYearly ? ` · Plans from ${rupees(info.fromYearly)}/year` : ""}
            </p>
            <ul className="mt-8 grid max-w-lg grid-cols-2 gap-x-6 gap-y-3 text-sm text-paper">
              {[
                ["Smartphone", "Android app"],
                ["Monitor", "Windows software"],
                ["WifiOff", "Bills without internet"],
                ["ReceiptText", "GST bills & returns"],
              ].map(([icon, label]) => {
                const Icon = LucideIcons[icon as keyof typeof LucideIcons] as LucideIcons.LucideIcon;
                return (
                  <li key={label} className="flex items-center gap-2.5">
                    <span className="inline-flex h-7 w-7 items-center justify-center rounded-lg bg-teal/12 text-teal">
                      <Icon className="h-4 w-4" aria-hidden="true" />
                    </span>
                    {label}
                  </li>
                );
              })}
            </ul>
          </Reveal>

          {/* the real app: Windows billing, the phone home screen in front */}
          <Reveal delay={0.12}>
            <div className="relative pb-10 lg:pb-0 lg:pr-10">
              <div className="lg:-mr-24 xl:-mr-40">
                <DesktopShot shot={desktopShots.newBill} label="Dukania · New Bill" priority />
              </div>
              <div className="absolute -bottom-2 right-0 w-[30%] min-w-[120px] max-w-[210px] sm:-bottom-6 lg:-bottom-12 lg:right-4">
                <MobileShot shot={mobileShots.dashboard} priority />
              </div>
              <div className="absolute -left-3 top-[58%] hidden rounded-2xl border border-hairline bg-surface/95 px-4 py-3 shadow-xl backdrop-blur sm:block lg:-left-8">
                <p className="flex items-center gap-2 text-sm font-semibold text-paper">
                  <LucideIcons.RefreshCw className="h-4 w-4 text-teal" aria-hidden="true" /> Phone &amp; PC in sync
                </p>
                <p className="mt-0.5 text-xs text-dim">One account, every counter</p>
              </div>
            </div>
          </Reveal>
        </div>
      </section>

      {/* 2 — real screens */}
      <section id="tour" className="mx-auto max-w-7xl px-6 py-20">
        <SectionHeading eyebrow="See it" title="The real app, screen by screen." align="center"
          lead="Billing, invoices, stock and reports on Windows — and the same shop in your pocket on Android." />
        <div className="mt-12">
          <ScreenshotTabs />
        </div>
      </section>

      {/* 3 — every feature */}
      <section id="features" className="mx-auto max-w-7xl px-6 py-20">
        <SectionHeading eyebrow="Everything included" title="The whole shop in one app."
          lead="No add-ons to buy, no separate tools to wire together." align="center" />
        <div className="mt-12 grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
          {FEATURES.map((f, i) => {
            const Icon = LucideIcons[f.icon] as LucideIcons.LucideIcon;
            return (
              <Reveal key={f.title} delay={(i % 4) * 0.05}>
                <div className="glass h-full rounded-2xl p-5">
                  <div className="inline-flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br from-violet/25 to-sky/20 ring-1 ring-paper/10">
                    <Icon className="h-5 w-5 text-sky" aria-hidden="true" />
                  </div>
                  <h3 className="mt-4 font-display text-base font-semibold">{f.title}</h3>
                  <p className="mt-1.5 text-sm text-dim">{f.body}</p>
                </div>
              </Reveal>
            );
          })}
        </div>
      </section>

      {/* 4 — who it's for */}
      <section className="mx-auto max-w-7xl px-6 py-20">
        <SectionHeading eyebrow="Made for your shop" title="Set up for the way your trade works."
          lead="Pick your type of shop when you sign up and Dukania switches on what you need." align="center" />
        <div className="mt-12 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          {SHOP_TYPES.map((t, i) => {
            const Icon = LucideIcons[t.icon] as LucideIcons.LucideIcon;
            return (
              <Reveal key={t.title} delay={(i % 3) * 0.06}>
                <div className="h-full rounded-2xl border border-hairline bg-paper/2 p-6">
                  <div className="flex items-center gap-3">
                    <span className="inline-flex h-10 w-10 items-center justify-center rounded-xl bg-amber/15 text-amber">
                      <Icon className="h-5 w-5" aria-hidden="true" />
                    </span>
                    <h3 className="font-display text-lg font-semibold">{t.title}</h3>
                  </div>
                  <ul className="mt-4 space-y-2 text-sm">
                    {t.points.map((p) => (
                      <li key={p} className="flex items-start gap-2 text-paper">
                        <LucideIcons.Check className="mt-0.5 h-4 w-4 shrink-0 text-teal" /> {p}
                      </li>
                    ))}
                  </ul>
                </div>
              </Reveal>
            );
          })}
        </div>
      </section>

      {/* 5 — three ways (interactive tabs) */}
      <section className="mx-auto max-w-7xl px-6 py-20">
        <SectionHeading eyebrow="Faster days" title="Three ways to speed up work." align="center" />
        <div className="mt-12">
          <ThreeWaysTabs />
        </div>
      </section>

      {/* 6 — offline-first */}
      <section className="mx-auto max-w-7xl px-6 py-16">
        <div className="grid items-center gap-12 lg:grid-cols-2">
          <Reveal className="flex justify-center lg:order-1">
            <MobileShot shot={mobileShots.checkout} />
          </Reveal>
          <Reveal delay={0.12} className="lg:order-2">
            <p className="font-mono text-xs uppercase tracking-[0.2em] text-sky">Offline-first</p>
            <h2 className="mt-3 font-display text-3xl font-bold tracking-tight">Keeps billing when the internet doesn&apos;t.</h2>
            <p className="mt-4 text-dim">
              Bill a customer with no signal. Dukania saves the bill on the device first and
              syncs the moment you&apos;re back online — cash, UPI, card or credit.
            </p>
            <ul className="mt-6 space-y-3 text-sm">
              {["Every bill saved on the device first", "Automatic background sync", "GST, discounts and round-off built in"].map((b) => (
                <li key={b} className="flex items-center gap-2.5 text-paper"><LucideIcons.Check className="h-4 w-4 shrink-0 text-teal" /> {b}</li>
              ))}
            </ul>
          </Reveal>
        </div>
      </section>

      {/* 7 — comparison */}
      <section className="mx-auto max-w-4xl px-6 py-20">
        <SectionHeading eyebrow="The difference" title="By hand vs. with Dukania." align="center" />
        <Reveal>
          <div className="mt-12 overflow-hidden rounded-2xl border border-hairline">
            <div className="grid grid-cols-[1fr_auto_auto] items-center gap-4 border-b border-hairline bg-paper/4 px-6 py-4 text-sm font-semibold">
              <span className="text-dim">Task</span>
              <span className="w-20 text-center text-dim">By hand</span>
              <span className="w-20 text-center text-teal">Dukania</span>
            </div>
            {compareItems.map((row, i) => (
              <div key={row} className={`grid grid-cols-[1fr_auto_auto] items-center gap-4 px-6 py-4 text-sm ${i % 2 ? "bg-paper/2" : ""}`}>
                <span className="text-paper">{row}</span>
                <span className="flex w-20 justify-center"><LucideIcons.X className="h-5 w-5 text-red-400/70" /></span>
                <span className="flex w-20 justify-center"><LucideIcons.Check className="h-5 w-5 text-teal" /></span>
              </div>
            ))}
          </div>
        </Reveal>
      </section>

      {/* 8 — pricing */}
      <section id="pricing" className="mx-auto max-w-5xl px-6 py-20">
        <SectionHeading eyebrow="Pricing" title="Simple yearly plans, priced for shop margins." align="center"
          lead="Try everything free first. When you're happy, pick the plan that fits your shop." />
        <Reveal>
          <div className="mt-12 grid gap-6 md:grid-cols-2">
            <div className="glass rounded-3xl p-8">
              <p className="font-mono text-xs uppercase tracking-[0.2em] text-teal">Start here</p>
              <h3 className="mt-3 font-display text-2xl font-bold">{trial}</h3>
              <p className="mt-2 text-dim">Every feature, your real shop, no card and no payment.</p>
              <ul className="mt-6 space-y-2.5 text-sm">
                {["Bill real customers from day one", "Your data stays when you upgrade", "Help on WhatsApp while you set up"].map((p) => (
                  <li key={p} className="flex items-start gap-2 text-paper"><LucideIcons.Check className="mt-0.5 h-4 w-4 shrink-0 text-teal" /> {p}</li>
                ))}
              </ul>
              <div className="mt-8"><MagneticButton href="/download">Start free trial <LucideIcons.ArrowRight className="h-4 w-4" /></MagneticButton></div>
            </div>
            <div className="relative rounded-3xl border-2 border-violet/40 bg-paper/4 p-8">
              <p className="font-mono text-xs uppercase tracking-[0.2em] text-violet">Paid plans</p>
              <h3 className="mt-3 font-display text-2xl font-bold">
                {info.fromYearly ? <>From {rupees(info.fromYearly)}<span className="text-base font-semibold text-dim"> / year</span></> : "Yearly plans"}
              </h3>
              <p className="mt-2 text-dim">
                {info.fromMonthly ? `Or monthly from ${rupees(info.fromMonthly)}. ` : ""}Plans differ in staff logins and a few extras — we&apos;ll help you pick.
              </p>
              <ul className="mt-6 space-y-2.5 text-sm">
                {["Billing, GST, stock, reports and printing on every plan", "Android and Windows on one account", "Updates and WhatsApp support included", "Pay by UPI, cash or bank transfer"].map((p) => (
                  <li key={p} className="flex items-start gap-2 text-paper"><LucideIcons.Check className="mt-0.5 h-4 w-4 shrink-0 text-teal" /> {p}</li>
                ))}
              </ul>
              <div className="mt-8">
                {wa ? (
                  <a href={wa} target="_blank" rel="noreferrer" className="inline-flex min-h-11 items-center gap-2 rounded-lg bg-emerald-600 px-5 text-sm font-semibold text-white hover:bg-emerald-700">
                    <LucideIcons.MessageCircle className="h-4 w-4" /> Ask for the right plan
                  </a>
                ) : (
                  <MagneticButton href="/contact" variant="ghost">Ask for the right plan</MagneticButton>
                )}
              </div>
            </div>
          </div>
        </Reveal>
      </section>

      {/* 9 — FAQ */}
      <section id="faq" className="mx-auto max-w-3xl px-6 py-16">
        <SectionHeading eyebrow="FAQ" title="Questions, answered." />
        <div className="mt-10"><Accordion items={faqItems} /></div>
      </section>

      <CtaBand
        title="Ready to run your shop on Dukania?"
        lead={`Download the app and start your ${trial.toLowerCase()} — or book a walkthrough and we'll set it up with you.`}
        cta="Start free trial"
        href="/download"
      />
    </>
  );
}
