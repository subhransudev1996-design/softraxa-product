import type { Metadata } from "next";
import Link from "next/link";
import { BookOpen, CreditCard, Landmark, LifeBuoy, MessageCircle, Package, Printer, Rocket, ShieldCheck, Users } from "lucide-react";
import PageHero from "@/components/page-hero";
import FaqGrid from "@/components/home/faq-grid";
import ClosingCta from "@/components/site/closing-cta";
import { getPageSeo, buildPageMetadata } from "@/lib/cms";
import { getSiteInfo, whatsappLink } from "@/lib/site-info";
import { eyebrow } from "@/lib/ui";

export async function generateMetadata(): Promise<Metadata> {
  return buildPageMetadata(await getPageSeo("/help"));
}

type Topic = { id: string; icon: typeof Rocket; title: string; items: { q: string; a: string }[] };

/** Answers by topic — only how the app works today. */
export default async function HelpPage() {
  const info = await getSiteInfo();
  const trial = info.trialDays ? `${info.trialDays}-day free trial` : "free trial";
  const wa = whatsappLink(info, "Hi, I need help with Dukania.");

  const TOPICS: Topic[] = [
    {
      id: "start", icon: Rocket, title: "Getting started",
      items: [
        { q: "How do I start?", a: `Download the app, sign up with your email and pick your type of shop. Your shop starts on a ${trial} straight away.` },
        { q: "Do I have to type in all my products?", a: "No. Tick products from the ready list for your trade, import your list from Excel, or add them as you bill." },
        { q: "Phone or computer?", a: "Both. Dukania works on Android phones and Windows PCs, on the same account, in sync." },
        { q: "Which languages?", a: "English and 10 Indian languages: Hindi, Marathi, Gujarati, Bengali, Punjabi, Tamil, Telugu, Kannada, Malayalam and Odia." },
      ],
    },
    {
      id: "billing", icon: Printer, title: "Billing & printing",
      items: [
        { q: "Which printers work?", a: "Bluetooth thermal printers from the phone, and A4 or A5 printing from the PC. You can add your logo and a note at the bottom of the bill." },
        { q: "Can I send the bill on WhatsApp?", a: "Yes — share the bill as a PDF in one tap." },
        { q: "How does the UPI QR work?", a: "Add your UPI ID once in business settings. Choose UPI at checkout and a QR with the bill amount appears for the customer to scan." },
        { q: "What if the internet goes?", a: "Keep billing. Bills are saved on the device and sync by themselves when the internet is back." },
      ],
    },
    {
      id: "stock", icon: Package, title: "Stock & products",
      items: [
        { q: "How does stock stay right?", a: "Every bill, purchase and return moves the stock. Low stock and expiring items are flagged for you." },
        { q: "I sell sizes and colours.", a: "Add them as variants — each has its own stock and barcode." },
        { q: "Can I enter a supplier's bill quickly?", a: "Yes. Open the supplier's PDF or Excel bill in Dukania and it fills the purchase for you." },
      ],
    },
    {
      id: "gst", icon: Landmark, title: "GST",
      items: [
        { q: "Does Dukania do my GST return?", a: "It makes the GSTR-1 file for the portal, shows GSTR-3B with the cash to pay, and matches purchases with GSTR-2B. You or your CA upload the file on the GST portal." },
        { q: "Can I make bills without GST?", a: "Yes — non-GST bills, cash memos and estimates." },
      ],
    },
    {
      id: "staff", icon: Users, title: "Staff",
      items: [
        { q: "How do I add staff?", a: "The owner adds them from the Staff screen and chooses what each person can do." },
        { q: "I need more staff logins.", a: "Tap \"Ask for more\" on the Staff screen. We'll add them to your plan and confirm on WhatsApp." },
        { q: "A staff member left. What do I do?", a: "Sign them out and remove them from the Staff screen — they lose access straight away." },
      ],
    },
    {
      id: "plans", icon: CreditCard, title: "Plans & payment",
      items: [
        { q: "How do I pay?", a: "By UPI, cash or bank transfer. Tap \"I've paid\" in the app or send the screenshot on WhatsApp; your plan is extended once we see the payment." },
        { q: "What happens when my plan ends?", a: "You can still open the app and export your records. To make new bills, renew." },
        { q: "Where do I see my plan?", a: "On the Plan screen in the app — your plan, when it ends, your logins and add-ons." },
      ],
    },
    {
      id: "data", icon: ShieldCheck, title: "Your data",
      items: [
        { q: "Is my data safe?", a: "Each shop's data is kept apart at the database level, so no other shop can see it." },
        { q: "Can I take my data out?", a: "Yes — export your products, customers, bills and reports to Excel any time." },
        { q: "How do I delete my account?", a: "See the Delete account page for the steps. Your data is removed as described there." },
      ],
    },
  ];

  return (
    <>
      <PageHero
        eyebrow="Help"
        title={"Questions?\nAnswers here."}
        lead="The things shop owners ask us most. Can't find yours? Open Support in the app, or message us on WhatsApp."
      />

      <nav aria-label="Help topics" className="mx-auto max-w-7xl px-6 pt-10">
        <ul className="grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-7">
          {TOPICS.map((t) => (
            <li key={t.id}>
              <a href={`#${t.id}`} className="flex h-full flex-col items-center gap-2 rounded-2xl border border-hairline bg-white px-3 py-4 text-center text-sm font-semibold text-paper shadow-card hover:border-brand/40">
                <span className="inline-flex h-9 w-9 items-center justify-center rounded-xl bg-brand-soft text-brand"><t.icon className="h-5 w-5" /></span>
                {t.title}
              </a>
            </li>
          ))}
        </ul>
      </nav>

      {TOPICS.map((t) => (
        <section key={t.id} id={t.id} className="mx-auto max-w-7xl scroll-mt-24 px-6 pt-12">
          <p className={eyebrow}>{t.title}</p>
          <div className="mt-4"><FaqGrid items={t.items} /></div>
        </section>
      ))}

      <section className="mx-auto grid max-w-7xl grid-cols-1 gap-4 px-6 py-14 md:grid-cols-3">
        <div className="rounded-2xl border border-hairline bg-white p-5 shadow-card">
          <LifeBuoy className="h-6 w-6 text-brand" />
          <p className="mt-3 font-bold">Support in the app</p>
          <p className="mt-1 text-sm text-dim">More → Support. Say what it&apos;s about; we reply in the app and you get a notification.</p>
        </div>
        <div className="rounded-2xl border border-hairline bg-white p-5 shadow-card">
          <MessageCircle className="h-6 w-6 text-brand" />
          <p className="mt-3 font-bold">WhatsApp</p>
          <p className="mt-1 text-sm text-dim">The fastest way to reach a person.</p>
          {wa && <a href={wa} target="_blank" rel="noreferrer" className="mt-2 inline-block text-sm font-semibold text-brand hover:underline">Chat on WhatsApp</a>}
        </div>
        <div className="rounded-2xl border border-hairline bg-white p-5 shadow-card">
          <BookOpen className="h-6 w-6 text-brand" />
          <p className="mt-3 font-bold">More to read</p>
          <p className="mt-1 text-sm text-dim">
            <Link href="/features" className="font-semibold text-brand hover:underline">Features</Link> ·{" "}
            <Link href="/gst" className="font-semibold text-brand hover:underline">GST</Link> ·{" "}
            <Link href="/ai" className="font-semibold text-brand hover:underline">AI setup</Link> ·{" "}
            <Link href="/delete-account" className="font-semibold text-brand hover:underline">Delete account</Link>
          </p>
        </div>
      </section>

      <ClosingCta info={info} title="Still stuck? We'll help you." waText="Hi, I need help with Dukania." />
    </>
  );
}
