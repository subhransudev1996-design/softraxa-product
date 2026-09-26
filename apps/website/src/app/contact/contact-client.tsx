"use client";

import Image from "next/image";
import Reveal from "@/components/reveal";
import Accordion from "@/components/accordion";
import ContactForm from "@/components/contact-form";
import HonestCall from "@/components/honest-call";
import { cmsIcon, type CmsItem, type CmsJson } from "@/lib/cms-types";

export default function ContactPageClient({ content }: { content?: CmsJson }) {
  const detailsItems = content?.details?.items || [
    { icon: "Mail", label: "Email", value: "hello@softraxa.com", note: "Replace with your address" },
    { icon: "MessageCircle", label: "WhatsApp", value: "+91 00000 00000", note: "Replace with your number" },
    { icon: "Clock", label: "Response time", value: "Within 1 business day", note: "" },
  ];

  const faqItems = content?.faqs?.items || [
    { q: "What happens after I submit the form?", a: "Your request lands directly with our team and we reach out within one business day to set up a walkthrough — no automated drip emails." },
    { q: "Is a demo free?", a: "Yes. The walkthrough is free and there's no obligation to buy afterwards." },
    { q: "Do you work with businesses outside my city?", a: "Yes — Dukania works offline-first and syncs to the cloud, so we can set you up wherever you are." },
  ];

  return (
    <>
      {/* ── Warm cream hero zone ── */}
      <div className="bg-[#FDF6EC]">
        {/* Summer Sale Banner */}
        <section className="mx-auto max-w-4xl px-6 pt-10">
          <Reveal>
            <div className="relative overflow-hidden rounded-3xl border-2 border-dashed border-amber-500/35 bg-[#FFFDF5] p-6 md:p-8 flex flex-col md:flex-row md:items-center justify-between gap-6">
              <div>
                <span className="font-display text-2xl font-extrabold text-amber-800">Summer sale</span>
                <p className="mt-2 text-xs uppercase tracking-wider text-amber-600 font-bold">Until July 31:</p>
                <p className="mt-1 text-sm text-amber-900 leading-relaxed max-w-md font-medium">
                  Use code <span className="font-bold text-amber-700">SAVE26</span> to get a free onboarding package (worth 499 USD) with any plan.
                </p>
              </div>

              {/* Banner graphics side */}
              <div className="flex items-center gap-4 self-center md:self-auto select-none">
                {/* Cloud onboarding badge */}
                <div className="relative rotate-[-6deg] bg-amber-500 text-white rounded-2xl px-3.5 py-2 font-display text-center shadow-md border border-amber-400">
                  <span className="block text-[13px] font-extrabold leading-none uppercase">free</span>
                  <span className="block text-[9px] font-bold leading-none tracking-wider mt-1">ONBOARDING</span>
                </div>

                {/* Customer avatar */}
                <div className="relative">
                  <div className="h-16 w-16 rounded-full border-4 border-amber-200 overflow-hidden shadow-lg bg-[#FEF3C7]">
                    <Image
                      src="/images/avatars/customer-electronics.png"
                      width={64}
                      height={64}
                      alt="Promo avatar"
                      className="h-full w-full object-cover"
                    />
                  </div>
                  {/* Dots under avatar */}
                  <div className="absolute -bottom-3 left-1/2 -translate-x-1/2 flex gap-1">
                    <span className="h-1.5 w-1.5 rounded-full bg-amber-400" />
                    <span className="h-1.5 w-1.5 rounded-full bg-amber-300" />
                    <span className="h-1.5 w-1.5 rounded-full bg-amber-200" />
                  </div>
                </div>
              </div>
            </div>
          </Reveal>
        </section>

        {/* "Will Dukania work for you?" consultation hero */}
        <HonestCall />
      </div>

      {/* ── Contact Form & Details Grid ── */}
      <section className="mx-auto max-w-7xl px-6 py-12">
        <div className="grid gap-12 lg:grid-cols-[1.2fr_0.8fr]">
          <Reveal>
            <div className="mb-6">
              <h2 className="font-display text-2xl font-bold tracking-tight text-paper">Send us a message</h2>
              <p className="mt-1 text-sm text-dim">Tell us what you want to build and we will get back to you.</p>
            </div>
            <ContactForm />
          </Reveal>

          <Reveal delay={0.1}>
            <div className="space-y-6 lg:mt-14">
              {detailsItems.map((d: CmsItem) => {
                const IconComponent = cmsIcon(d.icon);
                return (
                  <div key={d.label} className="glass flex items-start gap-4 rounded-2xl p-5">
                    <div className="inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-paper/4 ring-1 ring-paper/10">
                      <IconComponent className="h-5 w-5 text-sky" aria-hidden="true" />
                    </div>
                    <div>
                      <p className="text-xs uppercase tracking-wide text-dim">{d.label}</p>
                      <p className="mt-0.5 font-medium text-paper">{d.value}</p>
                      {d.note && <p className="mt-0.5 text-[11px] text-dim/70">{d.note}</p>}
                    </div>
                  </div>
                );
              })}
            </div>
          </Reveal>
        </div>
      </section>

      {/* ── FAQ Accordion ── */}
      <section className="mx-auto max-w-3xl px-6 pb-24">
        <h2 className="font-display text-2xl font-bold tracking-tight">Before you ask</h2>
        <div className="mt-8">
          <Accordion items={faqItems} />
        </div>
      </section>
    </>
  );
}
