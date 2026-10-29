import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { ArrowRight, Download, MessageCircle, Smartphone, Store, Ticket } from "lucide-react";
import Reveal from "@/components/reveal";
import PageHero from "@/components/page-hero";
import ClosingCta from "@/components/site/closing-cta";
import { PartnerVisit } from "@/components/partner-visit";
import { getSiteInfo, rupees, whatsappLink } from "@/lib/site-info";
import { supabase } from "@/lib/supabase-client";
import { btnGhost, btnPrimary, eyebrow } from "@/lib/ui";

// Fresh on every visit: a code can be switched off any time.
export const dynamic = "force-dynamic";

type Partner = { name: string; handle: string; code: string; buyer_off_pct: number };

// An influencer partner's link (migration 0104): the code is live for the
// visitor's next 30 days; an unknown or switched-off code goes home.
async function getPartner(code: string): Promise<Partner | null> {
  const { data, error } = await supabase.rpc("public_partner", { p_code: code });
  if (error || !data) return null;
  return data as Partner;
}

export async function generateMetadata({ params }: { params: Promise<{ code: string }> }): Promise<Metadata> {
  const { code } = await params;
  const p = await getPartner(code);
  if (!p) return { robots: { index: false } };
  const off = Number(p.buyer_off_pct);
  return {
    title: `${p.name}'s code ${p.code}${off > 0 ? ` — ${off}% off Dukania` : " — Dukania"}`,
    description: `Billing, GST and stock for your shop on phone and PC. Start free, then use ${p.name}'s code ${p.code} when you take a plan.`,
    robots: { index: false },
  };
}

export default async function PartnerLinkPage({ params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  const p = await getPartner(code);
  if (!p) redirect("/");
  const info = await getSiteInfo();
  const off = Number(p.buyer_off_pct);
  const trial = info.trialDays ? `${info.trialDays}-day free trial` : "free trial";
  const waText = `Hi, I came from ${p.name}. My code is ${p.code}. I want Dukania for my shop.`;
  const wa = whatsappLink(info, waText);
  const withCode = (price: number) => Math.round(price * (1 - off / 100));

  const steps = [
    { icon: Download, title: "Get the app", body: `Download Dukania on your Android phone or Windows PC and start your ${trial}.` },
    { icon: Ticket, title: "Enter the code", body: `In the app open Plan and enter ${p.code} on the "Refer a shop" card.` },
    { icon: Store, title: "Take a plan", body: off > 0 ? `When you're ready, your plan is ${off}% less than the website price.` : "When you're ready, take a plan — pay by UPI, cash or bank." },
  ];

  return (
    <>
      <PartnerVisit code={p.code} />
      <PageHero
        eyebrow={`Invited by ${p.name}${p.handle ? ` · ${p.handle}` : ""}`}
        title={off > 0 ? `${off}% off Dukania\nwith code ${p.code}.` : `Run your shop on Dukania.\nCode ${p.code}.`}
        lead={`Billing, GST, stock and dues for your shop — on your phone and PC, even without internet. Start with a ${trial}; your code is saved for your plan.`}
        actions={
          <>
            <Link href="/download" className={btnPrimary}>Start free trial <ArrowRight className="h-4 w-4" /></Link>
            <a href={wa || "/contact"} target={wa ? "_blank" : undefined} rel="noreferrer" className={btnGhost}>
              <MessageCircle className="h-4 w-4" /> Ask on WhatsApp
            </a>
          </>
        }
        aside={
          <div className="mx-auto w-full max-w-sm rounded-3xl border-2 border-dashed border-brand/50 bg-white p-6 text-center shadow-card">
            <p className="text-sm font-semibold text-dim">Your code</p>
            <p className="mt-2 font-mono text-4xl font-bold tracking-widest text-brand">{p.code}</p>
            {off > 0 && <p className="mt-3 inline-flex rounded-full bg-marigold/25 px-3 py-1 text-sm font-bold text-paper">{off}% off your plan</p>}
            <p className="mt-4 flex items-center justify-center gap-1.5 text-xs text-dim">
              <Smartphone className="h-3.5 w-3.5" /> Enter it in the app: Plan → Refer a shop
            </p>
          </div>
        }
      />

      <section className="mx-auto max-w-7xl px-6 py-14">
        <p className={eyebrow}>Three steps</p>
        <h2 className="mt-2 font-display text-3xl font-bold tracking-tight">How to use {p.name}&apos;s code.</h2>
        <ol className="mt-8 grid grid-cols-1 gap-4 md:grid-cols-3">
          {steps.map((s, i) => (
            <Reveal key={s.title} delay={i * 0.05}>
              <li className="h-full rounded-2xl border border-hairline bg-white p-5 shadow-card">
                <span className="inline-flex h-10 w-10 items-center justify-center rounded-xl bg-brand-soft text-brand"><s.icon className="h-5 w-5" /></span>
                <p className="mt-3 font-bold text-paper">{i + 1}. {s.title}</p>
                <p className="mt-1 text-sm text-dim">{s.body}</p>
              </li>
            </Reveal>
          ))}
        </ol>
      </section>

      {off > 0 && info.plans.length > 0 && (
        <section className="bg-brand-soft/50 py-14">
          <div className="mx-auto max-w-7xl px-6">
            <p className={eyebrow}>Your price with {p.code}</p>
            <h2 className="mt-2 font-display text-3xl font-bold tracking-tight">{off}% less on every plan.</h2>
            <ul className="mt-8 grid grid-cols-1 gap-4 md:grid-cols-3">
              {info.plans.map((plan) => (
                <li key={plan.name} className="rounded-2xl border border-hairline bg-white p-5 shadow-card">
                  <p className="font-display text-lg font-bold">{plan.name}</p>
                  <p className="mt-3 flex items-end gap-2">
                    <span className="font-display text-3xl font-bold text-brand">{rupees(withCode(plan.websitePrice))}</span>
                    <span className="pb-1 text-sm font-semibold text-dim">{plan.billing === "lifetime" ? "one time" : "/ year"}</span>
                  </p>
                  <p className="mt-1 text-sm text-dim"><s>{rupees(plan.websitePrice)}</s> without the code</p>
                </li>
              ))}
            </ul>
            <p className="mt-4 text-xs text-dim">On the plan itself; extra staff logins and add-ons are at their usual price. <Link href="/pricing" className="font-semibold text-brand underline">See what each plan has</Link>.</p>
          </div>
        </section>
      )}

      <ClosingCta info={info} title={`Start free — keep ${p.code} for later.`} waText={waText} />
    </>
  );
}
