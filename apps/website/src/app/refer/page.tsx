import type { Metadata } from "next";
import Link from "next/link";
import { ArrowRight, Gift, Share2, Smartphone, Store } from "lucide-react";
import Reveal from "@/components/reveal";
import PageHero from "@/components/page-hero";
import FaqGrid from "@/components/home/faq-grid";
import ClosingCta from "@/components/site/closing-cta";
import { getPageSeo, buildPageMetadata } from "@/lib/cms";
import { getSiteInfo } from "@/lib/site-info";
import { btnPrimary, eyebrow } from "@/lib/ui";

export async function generateMetadata(): Promise<Metadata> {
  return buildPageMetadata(await getPageSeo("/refer"));
}

// The referral programme (migration 0101): a code per shop on the app's
// Plan screen; free months when a referred shop takes a plan.
const STEPS = [
  { icon: Smartphone, title: "Find your code", body: "In the Dukania app open the Plan screen — your code (like DKAB2CD) is on the \"Refer a shop\" card." },
  { icon: Share2, title: "Share it", body: "Tap Share and send it on WhatsApp to a shop owner you know." },
  { icon: Store, title: "They join with it", body: "They start their free trial and enter your code on their Plan screen within 30 days." },
  { icon: Gift, title: "You get free months", body: "When they take a plan, free months are added to yours. The app shows what you've earned." },
];

export default async function ReferPage() {
  const info = await getSiteInfo();
  const faqs = [
    { q: "How many shops can I refer?", a: "As many as you like. Every shop that joins with your code and takes a plan earns you free months." },
    { q: "When do I get my free months?", a: "Once the shop you referred takes a plan, we add the months to your plan and tell you on WhatsApp." },
    { q: "My friend forgot to enter the code.", a: "They can enter it on their Plan screen in their first 30 days — or tell us on WhatsApp and we'll link it." },
    { q: "Does my friend get anything?", a: `They get the same ${info.trialDays ? `${info.trialDays}-day ` : ""}free trial and the website price — and a shop owner who already uses Dukania to ask.` },
  ];

  return (
    <>
      <PageHero
        eyebrow="Refer a shop"
        title={"Share Dukania,\nget free months."}
        lead="Know a shop owner still billing by hand? Send them your code. When they join and take a plan, you get free months on yours."
        actions={<Link href="/download" className={btnPrimary}>Get the app <ArrowRight className="h-4 w-4" /></Link>}
      />

      <section className="mx-auto max-w-7xl px-6 py-14">
        <p className={eyebrow}>How it works</p>
        <h2 className="mt-2 font-display text-3xl font-bold tracking-tight">Four steps.</h2>
        <ol className="mt-8 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {STEPS.map((s, i) => (
            <Reveal key={s.title} delay={i * 0.05}>
              <li className="relative h-full rounded-2xl border border-hairline bg-white p-5 shadow-card">
                <span className="absolute right-4 top-3 font-display text-4xl font-bold text-brand/15">{i + 1}</span>
                <span className="inline-flex h-10 w-10 items-center justify-center rounded-xl bg-brand-soft text-brand"><s.icon className="h-5 w-5" /></span>
                <p className="mt-3 font-bold text-paper">{s.title}</p>
                <p className="mt-1 text-sm text-dim">{s.body}</p>
              </li>
            </Reveal>
          ))}
        </ol>
      </section>

      <section className="bg-[#f6f0e2] py-14">
        <div className="mx-auto max-w-3xl px-6 text-center">
          <p className="hand -rotate-2 text-3xl text-paper/90">The best shops hear about Dukania from another shop.</p>
          <p className="mt-4 text-dim">That&apos;s why we&apos;d rather thank you than spend on ads.</p>
        </div>
      </section>

      <section className="mx-auto max-w-7xl px-6 py-14">
        <p className={eyebrow}>Questions</p>
        <h2 className="mt-2 font-display text-2xl font-bold tracking-tight sm:text-3xl">About referrals.</h2>
        <div className="mt-6"><FaqGrid items={faqs} /></div>
      </section>

      <ClosingCta info={info} waText="Hi, I want to know about the Dukania referral programme." />
    </>
  );
}
