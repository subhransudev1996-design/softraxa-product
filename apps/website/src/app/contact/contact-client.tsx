"use client";

import { MessageCircle } from "lucide-react";
import Reveal from "@/components/reveal";
import Accordion from "@/components/accordion";
import ContactForm from "@/components/contact-form";
import HonestCall from "@/components/honest-call";
import { cmsIcon, type CmsItem, type CmsJson } from "@/lib/cms-types";
import { displayPhone, whatsappLink, type SiteInfo } from "@/lib/site-info";

export default function ContactPageClient({ content, info }: { content?: CmsJson; info: SiteInfo }) {
  // Real details from the admin panel's Settings (public_site_info).
  const wa = whatsappLink(info, "Hi, I want to know more about Dukania for my shop.");
  const detailsItems: CmsItem[] = [
    ...(info.whatsapp ? [{ icon: "MessageCircle", label: "WhatsApp", value: displayPhone(info.whatsapp), href: wa, note: "Fastest — usually within a few hours" }] : []),
    ...(info.phone ? [{ icon: "Phone", label: "Phone", value: info.phone, href: `tel:${info.phone.replace(/[^0-9+]/g, "")}`, note: "" }] : []),
    ...(info.email ? [{ icon: "Mail", label: "Email", value: info.email, href: `mailto:${info.email}`, note: "" }] : []),
    ...(info.address ? [{ icon: "MapPin", label: "Address", value: info.address, note: "" }] : []),
    { icon: "Clock", label: "Response time", value: "Within 1 business day", note: "" },
  ];

  const faqItems = content?.faqs?.items || [
    { q: "What happens after I submit the form?", a: "Your request comes straight to us and we call or WhatsApp you within one business day to set up a walkthrough — no automated emails." },
    { q: "Is a demo free?", a: "Yes. The walkthrough is free and there's no obligation to buy afterwards. You can also start the free trial yourself from the app." },
    { q: "Do you work with businesses outside my city?", a: "Yes — Dukania runs on your phone or PC and keeps your data in the cloud, so we can set you up anywhere in India over a call." },
  ];

  return (
    <>
      {/* ── Warm cream hero zone ── */}
      <div className="bg-[#FDF6EC]">
        {wa && (
          <section className="mx-auto max-w-4xl px-6 pt-10">
            <Reveal>
              <a
                href={wa}
                target="_blank"
                rel="noreferrer"
                className="flex flex-col justify-between gap-4 rounded-3xl border border-emerald-600/20 bg-white p-6 shadow-sm transition-shadow hover:shadow-md md:flex-row md:items-center md:p-8"
              >
                <div>
                  <p className="font-display text-2xl font-extrabold text-emerald-800">Talk to us on WhatsApp</p>
                  <p className="mt-1 max-w-md text-sm text-emerald-900/80">
                    The quickest way to ask about Dukania, plans or getting your shop set up. {displayPhone(info.whatsapp)}
                  </p>
                </div>
                <span className="inline-flex items-center gap-2 self-start rounded-full bg-emerald-600 px-5 py-2.5 text-sm font-semibold text-white md:self-auto">
                  <MessageCircle className="h-4 w-4" /> Chat on WhatsApp
                </span>
              </a>
            </Reveal>
          </section>
        )}

        {/* "Will Dukania work for you?" consultation hero */}
        <HonestCall />
      </div>

      {/* ── Contact Form & Details Grid ── */}
      <section className="mx-auto max-w-7xl px-6 py-12">
        <div className="grid gap-12 lg:grid-cols-[1.2fr_0.8fr]">
          <Reveal>
            <div className="mb-6">
              <h2 className="font-display text-2xl font-bold tracking-tight text-paper">Send us a message</h2>
              <p className="mt-1 text-sm text-dim">Tell us about your shop and we&apos;ll call you back within one business day.</p>
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
