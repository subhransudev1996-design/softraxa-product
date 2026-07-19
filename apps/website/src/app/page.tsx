import { Layers, WifiOff, Store, BarChart3, ArrowRight, MessageCircle, IndianRupee } from "lucide-react";
import Hero from "@/components/hero";
import Marquee from "@/components/marquee";
import SectionHeading from "@/components/section-heading";
import FeatureCard from "@/components/feature-card";
import ProcessSteps from "@/components/process-steps";
import Reveal from "@/components/reveal";
import StatCounter from "@/components/stat-counter";
import CtaBand from "@/components/cta-band";
import HonestCall from "@/components/honest-call";
import Testimonials from "@/components/testimonials";
import AppsSuite from "@/components/apps-suite";
import { DesktopShot } from "@/components/app-shot";
import Parallax from "@/components/parallax";
import { desktopShots } from "@/lib/shots";
import MagneticButton from "@/components/magnetic-button";
import WhyShowcase from "@/components/why-showcase";
import WhatWeBuild from "@/components/what-we-build";
import AuthCodeRedirect from "@/components/auth-code-redirect";

const ico = "h-5 w-5 text-sky";

const SERVICES = [
  { icon: <Layers className={ico} />, title: "Product engineering", body: "The whole product — mobile app, backend and admin tooling — designed and built as one system.", href: "/services" },
  { icon: <WifiOff className={ico} />, title: "Offline-first mobile", body: "Apps that keep working with no signal and sync the moment a connection comes back.", href: "/services" },
  { icon: <Store className={ico} />, title: "Business software", body: "POS, inventory and billing built around how a real shop actually runs its day.", href: "/services" },
  { icon: <BarChart3 className={ico} />, title: "Data & reporting", body: "Sales, stock and expense data turned into reports an owner actually reads.", href: "/services" },
];

const WHY = [
  { icon: <WifiOff className={ico} />, title: "Offline-first, always", body: "Every screen works without a connection and reconciles automatically once you're back online." },
  { icon: <MessageCircle className={ico} />, title: "WhatsApp-speed support", body: "Message us directly and talk to the person who wrote the code — not a support script." },
  { icon: <IndianRupee className={ico} />, title: "India-first pricing", body: "Priced for real shop margins, not enterprise SaaS budgets." },
];

import { getPageContentMap, getPageSeo, buildPageMetadata } from "@/lib/cms";
import type { Metadata } from "next";

export async function generateMetadata(): Promise<Metadata> {
  const seo = await getPageSeo("/");
  return buildPageMetadata(seo);
}

export default async function HomePage() {
  const content = await getPageContentMap("home");
  const seo = await getPageSeo("/");

  const heroContent = content.hero?.content;
  const statsItems = content.stats?.items || [];

  return (
    <>
      <AuthCodeRedirect />
      {seo.structured_data && Object.keys(seo.structured_data).length > 0 && (
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(seo.structured_data) }}
        />
      )}
      
      <Hero content={heroContent} />

      <Marquee items={["Offline-first", "Flutter", "Supabase", "Real-time sync", "Android", "Windows", "Postgres", "Row-level security"]} />

      {/* services overview */}
      <section className="mx-auto max-w-7xl px-6 py-20">
        <SectionHeading
          eyebrow="What we build"
          title="Software agencies talk. We ship working products."
          lead="Four things we do well, end to end — from the first workflow sketch to the app in your staff's hands."
        />
        <div className="mt-12">
          <WhatWeBuild />
        </div>
      </section>

      {/* apps we build */}
      <section className="mx-auto max-w-7xl px-6 py-20">
        <SectionHeading
          eyebrow="Apps we build"
          title="One studio. A shelf of business apps."
          lead="Dukania is live today. The rest we build to order — same offline-first, India-first engineering, shaped around your trade."
        />
        <div className="mt-12">
          <AppsSuite />
        </div>
      </section>

      {/* Dukania spotlight */}
      <section className="mx-auto max-w-7xl px-6 py-20">
        <div className="glass overflow-hidden rounded-3xl">
          <div className="grid items-center gap-10 p-8 sm:p-12 lg:grid-cols-2">
            <Reveal>
              <p className="font-mono text-xs uppercase tracking-[0.2em] text-amber">Flagship product</p>
              <h2 className="mt-4 font-display text-3xl font-bold tracking-tight sm:text-4xl">Dukania</h2>
              <p className="mt-4 text-dim">
                Billing, stock, expiry tracking and reporting for real shops — built
                offline-first so a patchy connection never stops a sale.
              </p>
              <ul className="mt-6 space-y-2.5 text-sm text-paper">
                {["Bill customers online or completely offline", "Track stock and expiry with automatic low-stock alerts", "Reports and multi-user roles built in"].map((p) => (
                  <li key={p} className="flex items-start gap-2.5">
                    <span className="mt-1 h-1.5 w-1.5 shrink-0 rounded-full bg-gradient-to-r from-violet to-sky" />
                    {p}
                  </li>
                ))}
              </ul>
              <div className="mt-8">
                <MagneticButton href="/dukania">Explore Dukania <ArrowRight className="h-4 w-4" /></MagneticButton>
              </div>
            </Reveal>
            <Reveal delay={0.15}>
              <Parallax amount={36}>
                <DesktopShot shot={desktopShots.dashboard} label="Dukania · dashboard" />
              </Parallax>
            </Reveal>
          </div>
        </div>
      </section>

      {/* impact band */}
      <section className="mx-auto max-w-7xl px-6 py-16">
        <Reveal>
          <div className="grid grid-cols-2 gap-8 rounded-2xl border border-hairline bg-paper/4 px-8 py-10 text-center sm:grid-cols-4">
            {statsItems.map((stat: any) => (
              <div key={stat.label}>
                <p className="font-display text-3xl font-bold text-paper sm:text-4xl">
                  <StatCounter to={stat.value} suffix={stat.suffix} />
                </p>
                <p className="mt-2 text-xs text-dim">{stat.label}</p>
              </div>
            ))}
          </div>
        </Reveal>
      </section>

      {/* process */}
      <section className="mx-auto max-w-7xl px-6 py-20">
        <SectionHeading eyebrow="How we work" title="A short path from idea to live software." />
        <ProcessSteps />
      </section>

      {/* why softraxa */}
      <section className="mx-auto max-w-7xl px-6 py-20">
        <SectionHeading eyebrow="Why Softraxa" title="Built for the way business actually runs." />
        <div className="mt-12">
          <WhyShowcase />
        </div>
      </section>

      {/* testimonials */}
      <section className="mx-auto max-w-7xl px-6 py-20">
        <SectionHeading eyebrow="In their words" title="What shop owners say." align="center" />
        <div className="mt-14">
          <Testimonials />
        </div>
      </section>

      <HonestCall />
    </>
  );
}
