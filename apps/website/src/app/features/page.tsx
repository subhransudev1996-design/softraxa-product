import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { ArrowRight, MessageCircle } from "lucide-react";
import Reveal from "@/components/reveal";
import PageHero from "@/components/page-hero";
import ClosingCta from "@/components/site/closing-cta";
import LucideIcon, { type IconName } from "@/components/site/lucide-icon";
import { LaptopFrame, PhoneFrame } from "@/components/device-frame";
import { desktopShots, mobileShots, type Shot } from "@/lib/shots";
import { getPageSeo, buildPageMetadata } from "@/lib/cms";
import { getSiteInfo, whatsappLink } from "@/lib/site-info";
import { btnGhost, btnPrimary, eyebrow } from "@/lib/ui";

export async function generateMetadata(): Promise<Metadata> {
  return buildPageMetadata(await getPageSeo("/features"));
}

type Item = { icon: IconName; title: string; body: string };
type Group = {
  id: string;
  label: string;
  title: string;
  lead: string;
  items: Item[];
  picture?: { kind: "laptop" | "phone"; shot: Shot } | { kind: "photo"; src: string; alt: string };
  more?: { href: string; label: string };
};

// Only what the app does today — nothing goes here before it ships.
const GROUPS: Group[] = [
  {
    id: "billing",
    label: "Billing",
    title: "Bill a customer in seconds.",
    lead: "Scan, tap or type — the bill adds GST, discounts and round-off for you, and takes cash, UPI, card or credit.",
    picture: { kind: "laptop", shot: desktopShots.newBill },
    items: [
      { icon: "ScanLine", title: "Barcode billing", body: "Scan with a USB scanner or the phone camera; weighing-scale barcodes too." },
      { icon: "QrCode", title: "UPI QR with the amount", body: "The customer scans and pays the exact bill amount." },
      { icon: "SplitSquareHorizontal", title: "Split payments", body: "Part cash, part UPI — on the same bill." },
      { icon: "Printer", title: "Print any size", body: "Bluetooth thermal printers, A4 and A5, with your logo and a note at the bottom." },
      { icon: "Share2", title: "Share on WhatsApp", body: "Send the bill as a PDF in one tap." },
      { icon: "FileText", title: "Estimates & cash memos", body: "Quotations, non-GST bills and cash memos when you need them." },
    ],
  },
  {
    id: "offline",
    label: "Works offline",
    title: "Keeps billing when the internet doesn't.",
    lead: "Every bill is saved on the device first and synced in the background when the connection comes back.",
    picture: { kind: "photo", src: "/images/site/offline-shopkeeper.jpg", alt: "A shop owner billing on Dukania without internet" },
    items: [
      { icon: "WifiOff", title: "Bill with no signal", body: "The counter never stops for the network." },
      { icon: "RefreshCw", title: "Syncs by itself", body: "No button to press — it catches up on its own." },
      { icon: "MonitorSmartphone", title: "Phone and PC together", body: "One account on Android and Windows, always in step." },
    ],
  },
  {
    id: "stock",
    label: "Stock",
    title: "Know what you have — and what's running out.",
    lead: "Stock moves with every bill and purchase. Low stock and expiry are flagged before they cost you.",
    picture: { kind: "laptop", shot: desktopShots.stock },
    items: [
      { icon: "TriangleAlert", title: "Low-stock alerts", body: "See what to reorder at a glance." },
      { icon: "CalendarClock", title: "Expiry tracking", body: "Batches that are about to expire, before they do." },
      { icon: "Shapes", title: "Sizes, colours, storage", body: "Variants for garments, footwear and mobiles." },
      { icon: "Ruler", title: "Sell by kg, metre or piece", body: "Loose items, packs and pieces, and cuts from a roll." },
      { icon: "Smartphone", title: "IMEI and serial numbers", body: "On the purchase and on the bill." },
      { icon: "PackageSearch", title: "Ready product list", body: "Thousands of common products for your trade — tick and start." },
      { icon: "ImagePlus", title: "Product photos", body: "Find the right item faster." },
      { icon: "FileSpreadsheet", title: "Excel import & export", body: "Bring your list in; take your data out any time." },
    ],
  },
  {
    id: "gst",
    label: "GST",
    title: "GST from the bill to the return.",
    lead: "GST bills with HSN and CGST/SGST/IGST, and the files your CA needs at month end — from the same billing.",
    picture: { kind: "laptop", shot: desktopShots.reports },
    more: { href: "/gst", label: "How GST works in Dukania" },
    items: [
      { icon: "Landmark", title: "GSTR-1 file for the portal", body: "Upload it on the GST portal as it is." },
      { icon: "Calculator", title: "GSTR-3B with the cash to pay", body: "Output tax, input credit, what's left to pay." },
      { icon: "GitCompare", title: "GSTR-2B matching", body: "Your purchases against what suppliers filed." },
      { icon: "Route", title: "E-way bill files", body: "Ready to upload for goods on the move." },
      { icon: "Repeat", title: "Reverse charge & composition", body: "RCM purchases and CMP-08 for composition shops." },
    ],
  },
  {
    id: "khata",
    label: "Customers & khata",
    title: "Every customer's dues, in one place.",
    lead: "Give credit with confidence — Dukania keeps the khata, the limits and the payments straight.",
    picture: { kind: "phone", shot: mobileShots.checkout },
    items: [
      { icon: "BookUser", title: "Khata for every customer", body: "What they bought, what they paid, what's due." },
      { icon: "ShieldAlert", title: "Credit limits", body: "Stop a bill that would cross a customer's limit." },
      { icon: "PiggyBank", title: "Advances", body: "Take money in advance and use it on later bills." },
      { icon: "Tags", title: "Customer prices", body: "Special rates for your regular buyers." },
    ],
  },
  {
    id: "purchases",
    label: "Purchases",
    title: "Purchases and suppliers without the paperwork.",
    lead: "Enter a supplier's bill once — stock, cost and supplier dues update together.",
    picture: { kind: "laptop", shot: desktopShots.invoices },
    items: [
      { icon: "FileScan", title: "Read supplier bills", body: "Open a supplier's PDF or Excel bill and Dukania fills the purchase." },
      { icon: "Truck", title: "Supplier dues", body: "What you owe, to whom, since when." },
      { icon: "Undo2", title: "Returns both ways", body: "Purchase returns, sales returns and exchanges by bill line." },
    ],
  },
  {
    id: "staff",
    label: "Staff",
    title: "Staff logins, with the owner in control.",
    lead: "Give each person their own login and decide what they can see and do.",
    items: [
      { icon: "ShieldCheck", title: "Permissions per person", body: "Billing only, or stock too — you choose." },
      { icon: "BadgeCheck", title: "Owner approvals", body: "Discounts above a limit wait for your OK." },
      { icon: "LogOut", title: "Sign out a staff member", body: "From your phone, any time." },
    ],
  },
  {
    id: "money",
    label: "Money & reports",
    title: "See where the money goes.",
    lead: "Sales, profit, stock value, cash in hand and expenses — every day, every month.",
    picture: { kind: "laptop", shot: desktopShots.expenses },
    items: [
      { icon: "Wallet", title: "Cashbook & day close", body: "Count the drawer and close the day." },
      { icon: "Receipt", title: "Expenses", body: "Rent, salary, electricity — by category." },
      { icon: "BarChart3", title: "Reports", body: "Sales, profit, stock and GST, ready to share." },
    ],
  },
  {
    id: "repairs",
    label: "Repairs & service",
    title: "Job cards for repair shops and workshops.",
    lead: "Take the device or vehicle in, give an estimate the customer approves, and bill parts and labour together.",
    picture: { kind: "laptop", shot: desktopShots.jobCard },
    items: [
      { icon: "Wrench", title: "Job cards", body: "Status from received to delivered." },
      { icon: "ClipboardCheck", title: "Estimates the customer approves", body: "Before the work starts." },
      { icon: "ListChecks", title: "Service catalog", body: "Your standard jobs and their prices." },
    ],
  },
  {
    id: "offers",
    label: "Offers & loyalty",
    title: "Bring customers back.",
    lead: "Discount cards, coupons and scratch cards that apply on the bill by themselves.",
    items: [
      { icon: "BadgePercent", title: "Discount & privilege cards", body: "By percentage or by category, found by number." },
      { icon: "Gift", title: "Offers & coupons", body: "Coupon codes and vouchers with their own rules." },
      { icon: "Ticket", title: "Scratch cards", body: "A little surprise at the counter." },
    ],
  },
  {
    id: "ai",
    label: "AI assistant",
    title: "Ask your shop in plain words.",
    lead: "Connect Dukania to ChatGPT or Claude: enter a supplier's bill from a photo, make a bill, check who owes you. Nothing is saved until you say yes.",
    more: { href: "/ai", label: "See Dukania AI" },
    items: [
      { icon: "Sparkles", title: "In your language", body: "Ask in Hindi or your own language." },
      { icon: "Camera", title: "Bills from a photo", body: "Share the supplier's bill and say 'enter this purchase'." },
      { icon: "Hand", title: "You say yes first", body: "A preview every time; staff rules still apply." },
    ],
  },
];

const EVERYWHERE: Item[] = [
  { icon: "Languages", title: "11 languages", body: "English, Hindi, Marathi, Gujarati, Bengali, Punjabi, Tamil, Telugu, Kannada, Malayalam and Odia." },
  { icon: "MonitorSmartphone", title: "Android & Windows", body: "Counter PC and pocket phone on one account." },
  { icon: "Lock", title: "Your data stays yours", body: "Each shop's data is kept apart; export it any time." },
  { icon: "MessageCircle", title: "Help on WhatsApp", body: "Real people who know the app." },
];

function Picture({ p }: { p: NonNullable<Group["picture"]> }) {
  if (p.kind === "photo") {
    return <Image src={p.src} alt={p.alt} width={1672} height={941} sizes="(max-width: 1024px) 90vw, 560px"
      className="aspect-[4/3] h-auto w-full rounded-3xl object-cover shadow-card" />;
  }
  if (p.kind === "phone") {
    return (
      <div className="mx-auto w-56">
        <PhoneFrame>
          <Image src={p.shot.src} width={p.shot.width} height={p.shot.height} alt={p.shot.alt} sizes="224px" className="h-auto w-full" />
        </PhoneFrame>
      </div>
    );
  }
  return (
    <LaptopFrame>
      <Image src={p.shot.src} width={p.shot.width} height={p.shot.height} alt={p.shot.alt} sizes="(max-width: 1024px) 90vw, 560px" className="h-auto w-full" />
    </LaptopFrame>
  );
}

export default async function FeaturesPage() {
  const info = await getSiteInfo();
  const wa = whatsappLink(info, "Hi, I want a demo of Dukania for my shop.");
  const total = GROUPS.reduce((n, g) => n + g.items.length, 0) + EVERYWHERE.length;

  return (
    <>
      <PageHero
        eyebrow="Features"
        title={"Everything your shop needs,\nin one app."}
        lead={`${total} things Dukania does for Indian shops today — billing, stock, GST, khata, staff, repairs, offers and an AI assistant.`}
        actions={
          <>
            <Link href="/download" className={btnPrimary}>Start free trial <ArrowRight className="h-4 w-4" /></Link>
            <a href={wa || "/contact"} target={wa ? "_blank" : undefined} rel="noreferrer" className={btnGhost}>
              <MessageCircle className="h-4 w-4" /> Book a free demo
            </a>
          </>
        }
        aside={
          <LaptopFrame>
            <Image src={desktopShots.dashboard.src} width={desktopShots.dashboard.width} height={desktopShots.dashboard.height}
              alt={desktopShots.dashboard.alt} priority sizes="(max-width: 1024px) 90vw, 560px" className="h-auto w-full" />
          </LaptopFrame>
        }
      />

      {/* jump to an area */}
      <nav aria-label="Feature areas" className="sticky top-[73px] z-30 border-b border-hairline bg-bg/90 backdrop-blur-xl">
        <ul className="mx-auto flex max-w-7xl gap-2 overflow-x-auto px-6 py-3">
          {GROUPS.map((g) => (
            <li key={g.id}>
              <a href={`#${g.id}`} className="inline-flex whitespace-nowrap rounded-full border border-hairline bg-white px-3 py-1.5 text-xs font-semibold text-dim hover:border-brand/40 hover:text-brand">
                {g.label}
              </a>
            </li>
          ))}
        </ul>
      </nav>

      {GROUPS.map((g, i) => (
        <section key={g.id} id={g.id} className={`scroll-mt-32 py-14 ${i % 2 ? "bg-brand-soft/40" : ""}`}>
          <div className={`mx-auto grid max-w-7xl grid-cols-1 items-center gap-10 px-6 ${g.picture ? "lg:grid-cols-2" : ""}`}>
            <Reveal className={g.picture && i % 2 ? "lg:order-2" : ""}>
              <p className={eyebrow}>{g.label}</p>
              <h2 className="mt-2 font-display text-3xl font-bold tracking-tight">{g.title}</h2>
              <p className="mt-3 max-w-xl text-dim">{g.lead}</p>
              <ul className={`mt-6 grid grid-cols-1 gap-3 ${g.picture ? "sm:grid-cols-2" : "sm:grid-cols-2 lg:grid-cols-3"}`}>
                {g.items.map((it) => (
                  <li key={it.title} className="flex gap-3 rounded-2xl border border-hairline bg-white p-4 shadow-card">
                    <span className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-brand-soft text-brand">
                      <LucideIcon name={it.icon} className="h-5 w-5" />
                    </span>
                    <span>
                      <span className="block text-sm font-bold text-paper">{it.title}</span>
                      <span className="mt-0.5 block text-xs leading-relaxed text-dim">{it.body}</span>
                    </span>
                  </li>
                ))}
              </ul>
              {g.more && (
                <Link href={g.more.href} className="mt-5 inline-flex items-center gap-1.5 text-sm font-semibold text-brand hover:text-brand-2">
                  {g.more.label} <ArrowRight className="h-4 w-4" />
                </Link>
              )}
            </Reveal>
            {g.picture && (
              <Reveal delay={0.1} className={i % 2 ? "lg:order-1" : ""}>
                <Picture p={g.picture} />
              </Reveal>
            )}
          </div>
        </section>
      ))}

      <section className="bg-[#f6f0e2] py-14">
        <div className="mx-auto max-w-7xl px-6">
          <p className={eyebrow}>Everywhere</p>
          <h2 className="mt-2 font-display text-3xl font-bold tracking-tight">Made for how Indian shops work.</h2>
          <ul className="mt-8 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {EVERYWHERE.map((it) => (
              <li key={it.title} className="rounded-2xl border border-hairline bg-white p-5 shadow-card">
                <span className="inline-flex h-10 w-10 items-center justify-center rounded-xl bg-brand-soft text-brand">
                  <LucideIcon name={it.icon} className="h-5 w-5" />
                </span>
                <p className="mt-3 font-bold text-paper">{it.title}</p>
                <p className="mt-1 text-sm text-dim">{it.body}</p>
              </li>
            ))}
          </ul>
        </div>
      </section>

      <div className="pt-14" />
      <ClosingCta info={info} />
    </>
  );
}
