import type { Metadata } from "next";
import Link from "next/link";
import { ArrowRight, Check, Gift, X } from "lucide-react";
import Reveal from "@/components/reveal";
import PageHero from "@/components/page-hero";
import FaqGrid from "@/components/home/faq-grid";
import ClosingCta from "@/components/site/closing-cta";
import PlanCards from "@/components/site/plan-cards";
import { getPageSeo, buildPageMetadata } from "@/lib/cms";
import { getSiteInfo, rupees } from "@/lib/site-info";
import { supabase } from "@/lib/supabase-client";
import { eyebrow } from "@/lib/ui";

export async function generateMetadata(): Promise<Metadata> {
  return buildPageMetadata(await getPageSeo("/pricing"));
}

// On every plan (what the app does today).
const EVERY_PLAN = [
  "Billing, barcode and printing",
  "Works offline, syncs by itself",
  "Stock, expiry and low-stock alerts",
  "GST bills and GST return files",
  "Customers, khata and suppliers",
  "Reports, cashbook and expenses",
  "Android and Windows on one account",
  "11 languages",
  "Updates included",
  "Help on WhatsApp",
];

export default async function PricingPage() {
  const info = await getSiteInfo();
  const trial = info.trialDays ? `${info.trialDays}-day free trial` : "Free trial";
  const plans = info.plans;
  // Online payment on dukania.in/pay (migration 0105), once switched on.
  const { data: payOnline } = await supabase.rpc("online_payments_on");

  const faqs = [
    { q: "Do I pay anything to try it?", a: `No. Sign up in the app and your shop starts on a ${trial.toLowerCase()} with every feature — no card, no payment.` },
    { q: "How do I pay?", a: payOnline
      ? "Online on dukania.in/pay by UPI, card or netbanking — your plan turns on straight away. In the app, tap Pay online on the Plan screen. You can also pay by UPI or bank transfer and send us the screenshot on WhatsApp."
      : "By UPI, cash or bank transfer. Tap \"I've paid\" in the app or send us the payment screenshot on WhatsApp, and your plan is extended once we see it." },
    { q: "What happens when my plan ends?", a: "You can still open the app, see your records and export them. To make new bills, renew the plan." },
    { q: "Can I add more staff later?", a: "Yes. Ask from the Staff screen in the app and we add the extra logins to your plan." },
    { q: "Do I get a bill for my payment?", a: "Yes — a receipt for every payment, sent on WhatsApp. Need a GST invoice for your books? Ask us when you pay." },
    { q: "Is my data safe if I don't renew?", a: "Yes. Your data stays yours; you can export it to Excel at any time." },
  ];

  return (
    <>
      <PageHero
        eyebrow="Pricing"
        title={"Simple and honest pricing.\nTry it free first."}
        lead={`Every plan starts with a ${trial.toLowerCase()}. Pay once a year — or once for life — by UPI, cash or bank.`}
      />

      <section className="bg-brand-soft/50 py-14">
        <div className="mx-auto max-w-7xl px-6">
          {info.discountPct > 0 && plans.length > 0 && (
            <p className="inline-flex rounded-full bg-marigold/25 px-4 py-1.5 text-sm font-semibold text-paper">
              Launch offer: {info.discountPct}% off every plan
            </p>
          )}
          <PlanCards info={info} />
          <p className="mt-6 text-sm text-dim">Prices include updates and WhatsApp support. Nothing extra to pay later.</p>
          {payOnline === true && (
            <Link href="/pay" className="mt-4 inline-flex items-center gap-2 text-sm font-semibold text-brand hover:underline">
              Already using Dukania? Pay or renew online <ArrowRight className="h-4 w-4" />
            </Link>
          )}
        </div>
      </section>

      {plans.length > 1 && (
        <section className="mx-auto max-w-7xl px-6 py-14">
          <Reveal>
            <p className={eyebrow}>Compare</p>
            <h2 className="mt-2 font-display text-3xl font-bold tracking-tight">Which plan is right for you?</h2>
            <div className="mt-6 overflow-x-auto rounded-2xl border border-hairline bg-white shadow-card">
              <table className="w-full min-w-[560px] text-sm">
                <thead>
                  <tr className="bg-elevated/70 text-left">
                    <th className="px-4 py-3 font-bold" />
                    {plans.map((p) => <th key={p.name} className={`px-4 py-3 font-bold ${p.isRecommended ? "text-brand" : ""}`}>{p.name}</th>)}
                  </tr>
                </thead>
                <tbody>
                  <Row label="Price" cells={plans.map((p) => `${rupees(p.websitePrice)} ${p.billing === "lifetime" ? "once" : "a year"}`)} />
                  <Row label="Renewal" cells={plans.map((p) => (p.billing === "lifetime" ? "Never" : "Every year"))} />
                  <Row label="Logins" cells={plans.map((p) => (p.users ? `Owner + ${p.users - 1} staff` : "Unlimited"))} />
                  <Row label="Extra staff login" cells={plans.map((p) => (p.extraStaffPrice > 0 ? `${rupees(p.extraStaffPrice)} a year` : "—"))} />
                  <Row label="AI assistant (ChatGPT & Claude)" cells={plans.map((p) => (p.includesAi ? true : p.aiAddonPrice > 0 ? `Add for ${rupees(p.aiAddonPrice)} a year` : false))} />
                  <Row label="Everything else" cells={plans.map(() => true)} />
                </tbody>
              </table>
            </div>
          </Reveal>
        </section>
      )}

      <section className="bg-[#f6f0e2] py-14">
        <div className="mx-auto grid max-w-7xl grid-cols-1 gap-8 px-6 lg:grid-cols-[1.4fr_1fr] lg:items-center">
          <Reveal>
            <p className={eyebrow}>On every plan</p>
            <h2 className="mt-2 font-display text-3xl font-bold tracking-tight">No feature locked away.</h2>
            <ul className="mt-6 grid grid-cols-1 gap-2.5 sm:grid-cols-2">
              {EVERY_PLAN.map((f) => (
                <li key={f} className="flex items-center gap-2.5 text-sm">
                  <span className="inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-brand text-white"><Check className="h-3 w-3" /></span>
                  {f}
                </li>
              ))}
            </ul>
          </Reveal>
          <Reveal delay={0.1}>
            <div className="rounded-3xl border border-brand/20 bg-white p-6 shadow-card">
              <span className="inline-flex h-10 w-10 items-center justify-center rounded-xl bg-brand-soft text-brand"><Gift className="h-5 w-5" /></span>
              <h3 className="mt-3 font-display text-xl font-bold">Refer a shop, get free months</h3>
              <p className="mt-2 text-sm text-dim">
                Share your Dukania code with another shop owner. When they join and take a plan, you get free months on yours.
              </p>
              <Link href="/refer" className="mt-4 inline-flex items-center gap-1.5 text-sm font-semibold text-brand hover:text-brand-2">
                How referrals work <ArrowRight className="h-4 w-4" />
              </Link>
            </div>
          </Reveal>
        </div>
      </section>

      <section className="mx-auto max-w-7xl px-6 py-14">
        <p className={eyebrow}>Questions</p>
        <h2 className="mt-2 font-display text-2xl font-bold tracking-tight sm:text-3xl">About plans and payment.</h2>
        <div className="mt-6"><FaqGrid items={faqs} /></div>
      </section>

      <ClosingCta info={info} waText="Hi, I want to know which Dukania plan is right for my shop." />
    </>
  );
}

function Row({ label, cells }: { label: string; cells: (string | boolean)[] }) {
  return (
    <tr className="border-t border-hairline">
      <td className="px-4 py-3 font-medium text-dim">{label}</td>
      {cells.map((c, i) => (
        <td key={i} className="px-4 py-3">
          {c === true ? <Check className="h-4 w-4 text-brand-2" /> : c === false ? <X className="h-4 w-4 text-zinc-300" /> : c}
        </td>
      ))}
    </tr>
  );
}
