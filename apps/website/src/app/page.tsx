import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import * as LucideIcons from "lucide-react";
import { ArrowRight, Check, X, PlayCircle, MessageCircle, Sparkles } from "lucide-react";
import Reveal from "@/components/reveal";
import ThreeWaysTabs from "@/components/three-ways-tabs";
import ProductTour from "@/components/home/product-tour";
import FilmCard from "@/components/home/film-card";
import FaqGrid from "@/components/home/faq-grid";
import { LaptopFrame, PhoneFrame } from "@/components/device-frame";
import AuthCodeRedirect from "@/components/auth-code-redirect";
import { desktopShots, mobileShots } from "@/lib/shots";
import { getPageContentMap, getPageSeo, buildPageMetadata } from "@/lib/cms";
import { getSiteInfo, whatsappLink } from "@/lib/site-info";
import PlanCards from "@/components/site/plan-cards";
import ClosingCta from "@/components/site/closing-cta";
import { btnGhost, btnPrimary, eyebrow } from "@/lib/ui";

export async function generateMetadata(): Promise<Metadata> {
  const seo = await getPageSeo("/");
  return buildPageMetadata(seo);
}

type Icon = keyof typeof LucideIcons;

// Everything below is what the app does today — keep it that way: no
// feature goes on this page before it ships.
const FEATURES: { icon: Icon; title: string; tone: string }[] = [
  { icon: "ReceiptText", title: "Fast billing", tone: "bg-red-50 text-red-600" },
  { icon: "WifiOff", title: "Works without internet", tone: "bg-emerald-50 text-emerald-600" },
  { icon: "ScanLine", title: "Barcode scanning", tone: "bg-indigo-50 text-indigo-600" },
  { icon: "TriangleAlert", title: "Stock & low-stock alerts", tone: "bg-amber-50 text-amber-600" },
  { icon: "CalendarClock", title: "Expiry tracking", tone: "bg-orange-50 text-orange-600" },
  { icon: "Landmark", title: "GST filing made easy", tone: "bg-teal-50 text-teal-600" },
  { icon: "Route", title: "E-way bills & reverse charge", tone: "bg-sky-50 text-sky-600" },
  { icon: "Users", title: "Customers & khata", tone: "bg-blue-50 text-blue-600" },
  { icon: "Truck", title: "Purchases & suppliers", tone: "bg-violet-50 text-violet-600" },
  { icon: "FileScan", title: "Read supplier bills", tone: "bg-yellow-50 text-yellow-700" },
  { icon: "Undo2", title: "Returns & exchanges", tone: "bg-cyan-50 text-cyan-600" },
  { icon: "ShieldCheck", title: "Staff logins & approvals", tone: "bg-purple-50 text-purple-600" },
  { icon: "Printer", title: "Print & share bills", tone: "bg-rose-50 text-rose-600" },
  { icon: "QrCode", title: "UPI QR at the counter", tone: "bg-slate-100 text-slate-700" },
  { icon: "Wrench", title: "Job cards for repairs", tone: "bg-emerald-50 text-emerald-700" },
  { icon: "Wallet", title: "Cashbook & expenses", tone: "bg-orange-50 text-orange-600" },
  { icon: "BarChart3", title: "Reports", tone: "bg-blue-50 text-blue-600" },
  { icon: "PackageSearch", title: "Ready product list", tone: "bg-red-50 text-red-600" },
  { icon: "FileSpreadsheet", title: "Excel import & export", tone: "bg-green-50 text-green-700" },
  { icon: "Languages", title: "In your language", tone: "bg-lime-50 text-lime-700" },
  { icon: "BadgePercent", title: "Discount & privilege cards", tone: "bg-amber-50 text-amber-600" },
  { icon: "Gift", title: "Offers, coupons & scratch cards", tone: "bg-pink-50 text-pink-600" },
  { icon: "Sparkles", title: "Run your shop from ChatGPT", tone: "bg-emerald-50 text-emerald-700" },
  { icon: "BookOpen", title: "Book store billing", tone: "bg-yellow-50 text-yellow-700" },
];

const TRADES: { title: string; image: string; focus: string; points: string[] }[] = [
  { title: "Mobile & electronics", image: "/images/site/trade-mobile.jpg", focus: "70%", points: ["IMEI on every bill", "Colour / storage variants", "Repair job cards"] },
  { title: "Hardware & electrical", image: "/images/site/trade-hardware.jpg", focus: "50%", points: ["Sell by metre, kg or piece", "Cut wire and pipe from the roll", "Big product lists"] },
  { title: "Garments & footwear", image: "/images/site/trade-garments.jpg", focus: "55%", points: ["Sizes and colours", "Barcode billing", "Exchanges without paperwork"] },
  { title: "Grocery & kirana", image: "/images/site/trade-grocery.jpg", focus: "65%", points: ["Loose items by weight", "Weighing-scale barcodes", "Khata for regular customers"] },
  { title: "Car & bike workshops", image: "/images/site/trade-workshop.jpg", focus: "40%", points: ["Vehicle job cards", "Parts and labour on one bill", "Estimates the customer approves"] },
  { title: "Any retail counter", image: "/images/site/trade-retail.jpg", focus: "55%", points: ["GST billing from day one", "Stock that stays right", "Works on the phone you have"] },
];

const HERO_CHIPS: { icon: Icon; label: string }[] = [
  { icon: "WifiOff", label: "Works offline" },
  { icon: "FileCheck2", label: "GST ready" },
  { icon: "Languages", label: "In your language" },
  { icon: "MonitorSmartphone", label: "Phone & PC" },
  { icon: "Sparkles", label: "AI assistant" },
];

function LucideIcon({ name, className }: { name: Icon; className?: string }) {
  const C = LucideIcons[name] as LucideIcons.LucideIcon;
  return <C className={className} aria-hidden="true" />;
}


export default async function HomePage() {
  const content = await getPageContentMap("dukania");
  const seo = await getPageSeo("/");
  const info = await getSiteInfo();

  const hero = content.hero?.content || {};
  const title: string = hero.title || "Your complete shop,\nnow smarter with AI.";
  const lead: string =
    hero.lead ||
    "Bill, manage stock, track khata and file GST — online or completely offline. And when you're busy, just ask Dukania AI.";
  const trial = info.trialDays ? `${info.trialDays}-day free trial` : "Free trial";
  const wa = whatsappLink(info, "Hi, I want to know more about Dukania for my shop.");
  const demoHref = wa || "/contact";

  const compareItems: string[] = content.compare?.items || [
    "Bill with no internet",
    "Spot low stock instantly",
    "Track expiry automatically",
    "GST reports in one tap",
    "Staff logins with limited access",
    "Sync desktop and mobile",
  ];

  const faqItems = content.faqs?.items || [
    { q: "Is the free trial really free?", a: "Yes. Sign up in the app and your shop starts on a free trial straight away — no card, no payment." },
    { q: "Does it work without internet?", a: "Yes. Billing works fully offline and syncs automatically once the connection is back." },
    { q: "Will it help with GST filing?", a: "Yes — GST bills with HSN codes and CGST/SGST/IGST. Dukania makes the GSTR-1 file you upload on the GST portal, shows GSTR-3B with the cash to pay, matches purchases with GSTR-2B, and makes e-way bill files." },
    { q: "Can I accept UPI payments?", a: "Yes. Add your UPI ID once in business settings. When you choose UPI at checkout, a QR with the bill amount appears for the customer to scan." },
    { q: "Is it available in my language?", a: "Yes — Dukania works in English and 10 Indian languages: Hindi, Marathi, Gujarati, Bengali, Punjabi, Tamil, Telugu, Kannada, Malayalam and Odia." },
    { q: "Can AI really run my shop?", a: "With the AI add-on, you connect Dukania to ChatGPT or Claude and ask in plain words — make a bill, enter a supplier's bill from a photo, check who owes you. Nothing changes until you say yes." },
  ];

  const [titleLine, ...titleRest] = title.split("\n");

  return (
    <>
      <AuthCodeRedirect />
      {seo.structured_data && Object.keys(seo.structured_data).length > 0 && (
        <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(seo.structured_data) }} />
      )}

      {/* 1 — hero: the shop owner and the real app, phone and PC */}
      <section className="relative overflow-hidden">
        <Image
          src="/images/site/hero-shopkeeper.jpg"
          alt=""
          fill
          priority
          sizes="100vw"
          className="object-cover object-right opacity-90"
        />
        <div className="absolute inset-0 bg-gradient-to-r from-bg via-bg/90 to-bg/0 lg:via-bg/80" />
        <div className="relative mx-auto grid grid-cols-1 max-w-7xl items-center gap-10 px-6 pb-16 pt-10 sm:pt-14 lg:grid-cols-[1fr_1.05fr] lg:pb-20">
          <Reveal>
            <p className="inline-flex rounded-full bg-marigold/20 px-3 py-1 text-xs font-semibold text-paper">
              Billing &amp; stock software for Indian shops
            </p>
            <h1 className="mt-5 font-display text-4xl font-bold leading-[1.05] tracking-tight sm:text-5xl xl:text-[3.6rem]">
              {titleLine}
              {titleRest.length > 0 && (
                <>
                  <br />
                  <span className="text-brand">{titleRest.join(" ")}</span>
                </>
              )}
            </h1>
            <p className="mt-5 max-w-xl text-lg text-dim">{lead}</p>
            <div className="mt-7 flex flex-wrap gap-3">
              <Link href="/download" className={btnPrimary}>
                Start free trial <ArrowRight className="h-4 w-4" />
              </Link>
              <a href={demoHref} target={wa ? "_blank" : undefined} rel="noreferrer" className={btnGhost}>
                <MessageCircle className="h-4 w-4" /> Book a free demo
              </a>
            </div>
            <a href="#film" className="mt-5 inline-flex items-center gap-2 text-sm font-semibold text-brand hover:text-brand-2">
              <PlayCircle className="h-6 w-6 fill-brand text-white" aria-hidden="true" /> Watch the 2-minute film
            </a>
            <ul className="mt-9 grid max-w-xl grid-cols-5 gap-2">
              {HERO_CHIPS.map((c) => (
                <li key={c.label} className="flex flex-col items-center gap-2 text-center text-[11px] font-medium leading-tight text-dim sm:text-xs">
                  <LucideIcon name={c.icon} className="h-6 w-6 text-paper" />
                  {c.label}
                </li>
              ))}
            </ul>
          </Reveal>

          <Reveal delay={0.12}>
            <div className="relative mx-auto max-w-[620px] pt-16 lg:pt-28">
              <p className="hand absolute -top-2 left-0 -rotate-6 text-2xl leading-tight text-paper/80 sm:left-6 sm:text-3xl lg:top-2">
                Same Dukania,
                <br />
                now with AI inside!
              </p>
              <LaptopFrame className="w-[90%]">
                <Image src={desktopShots.dashboard.src} width={desktopShots.dashboard.width} height={desktopShots.dashboard.height}
                  alt={desktopShots.dashboard.alt} priority sizes="(max-width: 1024px) 85vw, 540px" className="h-auto w-full" />
              </LaptopFrame>
              <div className="absolute -bottom-8 right-0 w-[24%] min-w-[96px] max-w-[150px]">
                <PhoneFrame>
                  <Image src={mobileShots.dashboard.src} width={mobileShots.dashboard.width} height={mobileShots.dashboard.height}
                    alt={mobileShots.dashboard.alt} priority sizes="150px" className="h-auto w-full" />
                </PhoneFrame>
              </div>
              <div className="shadow-float absolute right-2 top-10 hidden rotate-3 rounded-xl bg-[#fff6d6] px-4 py-3 sm:block lg:top-20">
                <p className="text-sm font-semibold text-paper">Phone &amp; PC in sync</p>
                <p className="text-xs text-dim">One account, every counter</p>
              </div>
            </div>
          </Reveal>
        </div>
      </section>

      {/* 2 — the film, and the AI assistant */}
      <section className="mx-auto grid grid-cols-1 max-w-7xl gap-8 px-6 py-14 lg:grid-cols-2 lg:items-center">
        <Reveal><FilmCard /></Reveal>
        <Reveal delay={0.1}>
          <div className="grid grid-cols-1 items-center gap-6 sm:grid-cols-[1fr_1fr]">
            <div>
              <p className={eyebrow}>AI assistant</p>
              <h2 className="mt-2 font-display text-3xl font-bold tracking-tight">Run your shop with AI.</h2>
              <p className="mt-3 text-dim">
                Ask in simple words from ChatGPT or Claude. Dukania AI does the real work inside your shop — scan
                supplier bills, make bills, check stock and dues — and nothing changes until you say yes.
              </p>
              <Link href="/ai" className={`${btnPrimary} mt-6`}>
                See AI in action <ArrowRight className="h-4 w-4" />
              </Link>
            </div>
            <div className="rounded-3xl border border-hairline bg-white p-4 shadow-card">
              <p className="flex items-center gap-2 text-sm font-semibold">
                <span className="inline-flex h-7 w-7 items-center justify-center rounded-full bg-brand text-white">
                  <Sparkles className="h-4 w-4" />
                </span>
                Dukania AI
              </p>
              <p className="ml-auto mt-3 w-fit rounded-2xl rounded-br-sm bg-brand-soft px-3 py-2 text-xs font-medium text-brand">
                Show me low stock items
              </p>
              <div className="mt-3 rounded-2xl rounded-bl-sm bg-elevated/70 p-3 text-xs">
                <p className="text-dim">Here are your low stock items:</p>
                {[["Wheat atta 5 kg", "3 left"], ["Glucose biscuits 100 g", "5 left"], ["Detergent powder 1 kg", "2 left"]].map(([n, q]) => (
                  <p key={n} className="mt-2 flex justify-between gap-3 font-medium text-paper">
                    {n} <span className="text-red-600">{q}</span>
                  </p>
                ))}
                <p className="mt-3 w-fit rounded-lg border border-brand/40 px-2 py-1 font-semibold text-brand">Create purchase order</p>
              </div>
              <ul className="mt-3 space-y-1.5 text-[11px] text-dim">
                <li>• Scan this bill and add the products</li>
                <li>• Show today&apos;s sales report</li>
                <li>• Who owes me money?</li>
              </ul>
            </div>
          </div>
        </Reveal>
      </section>

      {/* 3 — product tour */}
      <section id="tour" className="bg-brand-soft/60 py-16">
        <div className="mx-auto max-w-7xl px-6"><ProductTour /></div>
      </section>

      {/* 4 — features */}
      <section id="features" className="mx-auto max-w-7xl scroll-mt-24 px-6 py-16">
        <p className={eyebrow}>Features</p>
        <h2 className="mt-2 font-display text-3xl font-bold tracking-tight sm:text-4xl">Everything your shop needs, in one app.</h2>
        <p className="mt-2 text-dim">{FEATURES.length} things Dukania does for you today.</p>
        <ul className="mt-8 grid grid-cols-3 gap-3 sm:grid-cols-4 lg:grid-cols-8">
          {FEATURES.map((f) => (
            <li key={f.title} className="flex flex-col items-center gap-2.5 rounded-2xl border border-hairline bg-white px-2 py-4 text-center shadow-card">
              <span className={`inline-flex h-10 w-10 items-center justify-center rounded-xl ${f.tone}`}>
                <LucideIcon name={f.icon} className="h-5 w-5" />
              </span>
              <span className="text-[12px] font-medium leading-tight text-paper">{f.title}</span>
            </li>
          ))}
        </ul>
      </section>

      {/* 5 — trades */}
      <section id="shops" className="scroll-mt-24 bg-[#f6f0e2] py-16">
        <div className="mx-auto max-w-7xl px-6">
          <p className={eyebrow}>For every trade</p>
          <h2 className="mt-2 font-display text-3xl font-bold tracking-tight sm:text-4xl">Set up for the way your trade works.</h2>
          <p className="mt-2 text-dim">Pick your type of shop when you sign up and Dukania switches on what you need.</p>
          <ul className="mt-8 grid grid-cols-2 gap-4 md:grid-cols-3 lg:grid-cols-6">
            {TRADES.map((t) => (
              <li key={t.title} className="overflow-hidden rounded-2xl border border-hairline bg-white shadow-card">
                <Image src={t.image} alt={t.title} width={1672} height={941} sizes="(max-width: 768px) 50vw, 16vw"
                  style={{ objectPosition: `${t.focus} 40%` }} className="aspect-[4/3] h-auto w-full object-cover" />
                <div className="p-3">
                  <h3 className="text-sm font-bold text-paper">{t.title}</h3>
                  <ul className="mt-2 space-y-1">
                    {t.points.map((p) => (
                      <li key={p} className="flex items-start gap-1.5 text-[11px] leading-snug text-dim">
                        <Check className="mt-0.5 h-3 w-3 shrink-0 text-brand-2" /> {p}
                      </li>
                    ))}
                  </ul>
                </div>
              </li>
            ))}
          </ul>
        </div>
      </section>

      {/* 6 — three ways + offline */}
      <section className="mx-auto grid grid-cols-1 max-w-7xl gap-6 px-6 py-16 lg:grid-cols-[1.4fr_1fr]">
        <Reveal><ThreeWaysTabs /></Reveal>
        <Reveal delay={0.1}>
          <div className="h-full overflow-hidden rounded-3xl border border-hairline bg-[#fff8e6] p-6 shadow-card sm:p-8">
            <div className="grid grid-cols-1 gap-6 sm:grid-cols-[1fr_auto] sm:items-end">
              <div>
                <p className={eyebrow}>Works offline</p>
                <h2 className="mt-2 max-w-xs font-display text-2xl font-bold tracking-tight">Keeps billing when the internet doesn&apos;t.</h2>
                <ul className="mt-5 space-y-3 text-sm text-paper">
                  {["Every bill saved on the device first", "Automatic background sync", "GST, discounts and round-off built in"].map((b) => (
                    <li key={b} className="flex items-center gap-2.5">
                      <span className="inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-brand text-white"><Check className="h-3 w-3" /></span>
                      {b}
                    </li>
                  ))}
                </ul>
              </div>
              <div className="relative justify-self-end pt-14">
                <p className="hand absolute right-0 top-0 -rotate-6 whitespace-nowrap text-2xl text-paper/80">No internet? No problem!</p>
                <Image src="/images/site/offline-shopkeeper.jpg" alt="A shop owner showing Dukania on his phone" width={1672} height={941}
                  sizes="176px" className="h-44 w-44 rounded-2xl object-cover object-[62%_30%]" />
              </div>
            </div>
          </div>
        </Reveal>
      </section>

      {/* 7 — by hand vs Dukania, and the free trial */}
      <section className="mx-auto grid grid-cols-1 max-w-7xl gap-8 px-6 pb-16 lg:grid-cols-[1.3fr_1fr] lg:items-end">
        <Reveal>
          <p className={eyebrow}>By hand vs Dukania</p>
          <h2 className="mt-2 font-display text-2xl font-bold tracking-tight sm:text-3xl">A clear difference you&apos;ll feel every day.</h2>
          <div className="mt-6 overflow-hidden rounded-2xl border border-hairline bg-white shadow-card">
            <div className="grid grid-cols-[1fr_72px_72px] bg-elevated/70 px-4 py-3 text-xs font-bold">
              <span />
              <span className="text-center text-dim">By hand</span>
              <span className="text-center text-brand">Dukania</span>
            </div>
            {compareItems.map((row) => (
              <div key={row} className="grid grid-cols-[1fr_72px_72px] items-center border-t border-hairline px-4 py-3 text-sm">
                <span>{row}</span>
                <X className="mx-auto h-4 w-4 text-red-500" />
                <Check className="mx-auto h-4 w-4 text-brand-2" />
              </div>
            ))}
          </div>
        </Reveal>
        <Reveal delay={0.1}>
          <div className="rounded-2xl border border-brand/20 bg-brand-soft/70 p-6 shadow-card">
              <h3 className="font-display text-2xl font-bold text-brand">{trial}</h3>
              <ul className="mt-4 space-y-2 text-sm">
                {["Every feature, no card", "Bill real customers from day one", "Data stays when you upgrade", "Help on WhatsApp"].map((p) => (
                  <li key={p} className="flex items-start gap-2"><Check className="mt-0.5 h-4 w-4 shrink-0 text-brand-2" /> {p}</li>
                ))}
              </ul>
              <Link href="/download" className={`${btnPrimary} mt-6 w-full justify-center`}>
                Start free trial <ArrowRight className="h-4 w-4" />
              </Link>
            </div>
        </Reveal>
      </section>

      {/* 8 — pricing: the plans with their list and website prices */}
      <section id="pricing" className="scroll-mt-24 bg-brand-soft/50 py-16">
        <div className="mx-auto max-w-7xl px-6">
          <p className={eyebrow}>Pricing</p>
          <div className="flex flex-wrap items-end justify-between gap-4">
            <h2 className="mt-2 font-display text-3xl font-bold tracking-tight sm:text-4xl">Simple and honest pricing.</h2>
            {info.discountPct > 0 && info.plans.length > 0 && (
              <p className="rounded-full bg-marigold/25 px-4 py-1.5 text-sm font-semibold text-paper">
                Launch offer: {info.discountPct}% off every plan
              </p>
            )}
          </div>
          <p className="mt-2 text-dim">Every plan starts with a {trial.toLowerCase()}. Billing, GST, stock, reports and printing on all of them.</p>
          <PlanCards info={info} />
          <p className="mt-6 text-sm text-dim">Pay by UPI, cash or bank transfer. Prices include updates and WhatsApp support.</p>
        </div>
      </section>

      {/* 9 — FAQ */}
      <section id="faq" className="mx-auto max-w-7xl scroll-mt-24 px-6 pb-16">
        <p className={eyebrow}>FAQ</p>
        <h2 className="mt-2 font-display text-2xl font-bold tracking-tight sm:text-3xl">Common questions, simple answers.</h2>
        <div className="mt-6"><FaqGrid items={faqItems} /></div>
      </section>

      {/* 10 — call to action + WhatsApp help */}
      <ClosingCta info={info} />
    </>
  );
}
