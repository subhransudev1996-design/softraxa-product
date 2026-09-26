import type { Metadata } from "next";
import * as LucideIcons from "lucide-react";
import PageHero from "@/components/page-hero";
import SectionHeading from "@/components/section-heading";
import ProcessSteps from "@/components/process-steps";
import Reveal from "@/components/reveal";
import CtaBand from "@/components/cta-band";
import { getPageContentMap, getPageSeo, buildPageMetadata } from "@/lib/cms";
import { cmsIcon, type CmsItem } from "@/lib/cms-types";

export async function generateMetadata(): Promise<Metadata> {
  const seo = await getPageSeo("/services");
  return buildPageMetadata(seo);
}

export default async function ServicesPage() {
  const content = await getPageContentMap("services");
  const seo = await getPageSeo("/services");

  const heroContent = content.hero?.content || {
    eyebrow: "Services",
    title: "What we build.",
    lead: "Softraxa is a small studio that ships complete products. Here's the work we take on, end to end."
  };

  const servicesItems = content.list?.items || [
    {
      title: "Product engineering",
      body: "We design and build the whole product as one system — mobile app, backend and admin panel — so nothing falls through the cracks between three separate vendors.",
      points: ["End-to-end architecture", "Mobile + web + backend", "One team, one roadmap"],
      icon: "Layers"
    },
    {
      title: "Offline-first mobile apps",
      body: "Apps that keep working with no signal. Local-first data, background sync and conflict handling built in from the start — not bolted on later.",
      points: ["Works fully offline", "Automatic background sync", "Android & Windows builds"],
      icon: "WifiOff"
    },
    {
      title: "Business software (POS & inventory)",
      body: "Billing, stock, purchases, returns and job cards modelled on how a real business runs its day — the domain we know best from building Dukania.",
      points: ["Billing & POS", "Stock + expiry tracking", "Returns & purchases"],
      icon: "Store"
    },
    {
      title: "Data & reporting",
      body: "Turn raw sales and stock data into reports people actually use — daily takings, top products, expenses — and export them cleanly when needed.",
      points: ["Sales & stock reports", "Expense tracking", "PDF export"],
      icon: "BarChart3"
    },
    {
      title: "Admin & operations tooling",
      body: "The back-office half of a product — client management, plans, subscriptions and support queues — so you can run the business, not just ship the app.",
      points: ["Client & plan management", "Subscriptions & billing", "Support workflows"],
      icon: "Settings"
    },
    {
      title: "Support & maintenance",
      body: "A direct line to the people who built your software. Fixes, updates and new features handled by the same team — not passed to a stranger.",
      points: ["Direct WhatsApp-speed support", "Ongoing updates", "New features on request"],
      icon: "LifeBuoy"
    }
  ];

  const stackItems = content.stack?.items || ["Flutter", "Supabase", "Next.js", "Postgres", "Edge Functions", "Row-level security"];

  return (
    <>
      {seo.structured_data && Object.keys(seo.structured_data).length > 0 && (
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(seo.structured_data) }}
        />
      )}

      <PageHero
        eyebrow={heroContent.eyebrow}
        title={heroContent.title}
        lead={heroContent.lead}
      />

      <section className="mx-auto max-w-7xl px-6 py-20">
        <div className="grid gap-6 md:grid-cols-2">
          {servicesItems.map((s: CmsItem, i: number) => {
            const IconComponent = cmsIcon(s.icon);
            return (
              <Reveal key={s.title} delay={(i % 2) * 0.08}>
                <div className="glass h-full rounded-2xl p-8">
                  <div className="inline-flex h-11 w-11 items-center justify-center rounded-xl bg-gradient-to-br from-violet/25 to-sky/20 ring-1 ring-paper/10">
                    <IconComponent className="h-5 w-5 text-sky" aria-hidden="true" />
                  </div>
                  <h3 className="mt-5 font-display text-xl font-semibold">{s.title}</h3>
                  <p className="mt-3 text-sm leading-relaxed text-dim">{s.body}</p>
                  <ul className="mt-5 space-y-2 text-sm">
                    {s.points?.map((p: string) => (
                      <li key={p} className="flex items-center gap-2 text-paper">
                        <LucideIcons.Check className="h-4 w-4 shrink-0 text-teal" /> {p}
                      </li>
                    ))}
                  </ul>
                </div>
              </Reveal>
            );
          })}
        </div>
      </section>

      {/* tech stack */}
      <section className="mx-auto max-w-7xl px-6 py-16">
        <SectionHeading eyebrow="Our stack" title="Proven tools, chosen on purpose." lead="The same stack we use to build and run Dukania in production." />
        <div className="mt-8 flex flex-wrap gap-3">
          {stackItems.map((t: string) => (
            <span key={t} className="glass rounded-full px-4 py-2 font-mono text-sm text-paper">{t}</span>
          ))}
        </div>
      </section>

      {/* process */}
      <section className="mx-auto max-w-7xl px-6 py-16">
        <SectionHeading eyebrow="How we work" title="A short path from idea to live software." />
        <ProcessSteps />
      </section>

      <CtaBand />
    </>
  );
}
