import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowRight, Check, MessageCircle, X } from "lucide-react";
import Reveal from "@/components/reveal";
import PageHero from "@/components/page-hero";
import FaqGrid from "@/components/home/faq-grid";
import ClosingCta from "@/components/site/closing-cta";
import LucideIcon from "@/components/site/lucide-icon";
import { LaptopFrame, PhoneFrame } from "@/components/device-frame";
import { getPageSeo, buildPageMetadata } from "@/lib/cms";
import { getSiteInfo, whatsappLink } from "@/lib/site-info";
import { TRADES, tradeBySlug } from "@/lib/trades";
import { btnGhost, btnPrimary, eyebrow } from "@/lib/ui";

export function generateStaticParams() {
  return TRADES.map((t) => ({ slug: t.slug }));
}

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const { slug } = await params;
  const t = tradeBySlug(slug);
  if (!t) return {};
  // The CMS can set this page's SEO by its path; otherwise from the trade.
  const seo = await getPageSeo(`/shops/${slug}`);
  const title = `${t.name} billing software — Dukania`;
  return buildPageMetadata({
    ...seo,
    title: seo.title && !seo.title.startsWith("Dukania —") ? seo.title : title,
    description: seo.description && seo.title && !seo.title.startsWith("Dukania —") ? seo.description : t.lead,
  });
}

/** One trade: its everyday problems, what Dukania does for it, the app, questions. */
export default async function TradePage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const t = tradeBySlug(slug);
  if (!t) notFound();
  const info = await getSiteInfo();
  const wa = whatsappLink(info, `Hi, I have a ${t.name.toLowerCase()} shop and want to know more about Dukania.`);
  const others = TRADES.filter((x) => x.slug !== t.slug);

  return (
    <>
      <PageHero
        eyebrow={t.name}
        title={t.title}
        lead={t.lead}
        actions={
          <>
            <Link href="/download" className={btnPrimary}>Start free trial <ArrowRight className="h-4 w-4" /></Link>
            <a href={wa || "/contact"} target={wa ? "_blank" : undefined} rel="noreferrer" className={btnGhost}>
              <MessageCircle className="h-4 w-4" /> Book a free demo
            </a>
          </>
        }
        aside={
          <Image src={t.image} alt={t.name} width={1672} height={941} priority sizes="(max-width: 1024px) 90vw, 560px"
            style={{ objectPosition: `${t.focus} 40%` }} className="aspect-[4/3] h-auto w-full rounded-3xl object-cover shadow-card" />
        }
      />

      {/* the problems, and Dukania's answer */}
      <section className="mx-auto grid max-w-7xl grid-cols-1 gap-6 px-6 py-14 lg:grid-cols-[1fr_1.4fr]">
        <Reveal>
          <div className="h-full rounded-3xl border border-hairline bg-[#fff8e6] p-6 shadow-card">
            <p className={eyebrow}>Sound familiar?</p>
            <ul className="mt-4 space-y-3">
              {t.pains.map((p) => (
                <li key={p} className="flex items-start gap-2.5 text-sm">
                  <span className="mt-0.5 inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-red-100 text-red-600"><X className="h-3 w-3" /></span>
                  {p}
                </li>
              ))}
            </ul>
            <p className="hand mt-6 -rotate-2 text-2xl text-paper/80">Dukania fixes that.</p>
          </div>
        </Reveal>
        <Reveal delay={0.1}>
          <p className={eyebrow}>What you get</p>
          <h2 className="mt-2 font-display text-3xl font-bold tracking-tight">Made for {t.name.toLowerCase()}.</h2>
          <ul className="mt-6 grid grid-cols-1 gap-3 sm:grid-cols-2">
            {t.features.map((f) => (
              <li key={f.title} className="flex gap-3 rounded-2xl border border-hairline bg-white p-4 shadow-card">
                <span className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-brand-soft text-brand">
                  <LucideIcon name={f.icon} className="h-5 w-5" />
                </span>
                <span>
                  <span className="block text-sm font-bold text-paper">{f.title}</span>
                  <span className="mt-0.5 block text-xs leading-relaxed text-dim">{f.body}</span>
                </span>
              </li>
            ))}
          </ul>
        </Reveal>
      </section>

      {/* the app itself */}
      <section className="bg-brand-soft/50 py-14">
        <div className="mx-auto grid max-w-7xl grid-cols-1 items-center gap-10 px-6 lg:grid-cols-2">
          <Reveal>
            <p className={eyebrow}>And everything else</p>
            <h2 className="mt-2 font-display text-3xl font-bold tracking-tight">The whole shop, not just the bill.</h2>
            <ul className="mt-6 space-y-3 text-sm">
              {["Works without internet, syncs by itself", "GST bills and the return files", "Staff logins with limits", "Phone and PC on one account", "In 11 Indian languages", "Help on WhatsApp"].map((b) => (
                <li key={b} className="flex items-center gap-2.5">
                  <span className="inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-brand text-white"><Check className="h-3 w-3" /></span>
                  {b}
                </li>
              ))}
            </ul>
            <Link href="/features" className="mt-6 inline-flex items-center gap-1.5 text-sm font-semibold text-brand hover:text-brand-2">
              See every feature <ArrowRight className="h-4 w-4" />
            </Link>
          </Reveal>
          <Reveal delay={0.1}>
            {t.shot.kind === "phone" ? (
              <div className="mx-auto w-56">
                <PhoneFrame>
                  <Image src={t.shot.shot.src} width={t.shot.shot.width} height={t.shot.shot.height} alt={t.shot.shot.alt} sizes="224px" className="h-auto w-full" />
                </PhoneFrame>
              </div>
            ) : (
              <LaptopFrame>
                <Image src={t.shot.shot.src} width={t.shot.shot.width} height={t.shot.shot.height} alt={t.shot.shot.alt}
                  sizes="(max-width: 1024px) 90vw, 560px" className="h-auto w-full" />
              </LaptopFrame>
            )}
          </Reveal>
        </div>
      </section>

      <section className="mx-auto max-w-7xl px-6 py-14">
        <p className={eyebrow}>Questions</p>
        <h2 className="mt-2 font-display text-2xl font-bold tracking-tight sm:text-3xl">From {t.name.toLowerCase()} owners.</h2>
        <div className="mt-6"><FaqGrid items={t.faqs} /></div>
      </section>

      <section className="mx-auto max-w-7xl px-6 pb-14">
        <p className="text-sm font-semibold text-dim">Other trades</p>
        <ul className="mt-3 flex flex-wrap gap-2">
          {others.map((o) => (
            <li key={o.slug}>
              <Link href={`/shops/${o.slug}`} className="inline-flex rounded-full border border-hairline bg-white px-3 py-1.5 text-sm font-medium text-dim hover:border-brand/40 hover:text-brand">
                {o.name}
              </Link>
            </li>
          ))}
        </ul>
      </section>

      <ClosingCta info={info}
        waText={`Hi, I have a ${t.name.toLowerCase()} shop and want to know more about Dukania.`} />
    </>
  );
}
