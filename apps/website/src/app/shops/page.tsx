import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { ArrowRight } from "lucide-react";
import Reveal from "@/components/reveal";
import PageHero from "@/components/page-hero";
import ClosingCta from "@/components/site/closing-cta";
import { getPageSeo, buildPageMetadata } from "@/lib/cms";
import { getSiteInfo } from "@/lib/site-info";
import { TRADES } from "@/lib/trades";
import { eyebrow } from "@/lib/ui";

export async function generateMetadata(): Promise<Metadata> {
  return buildPageMetadata(await getPageSeo("/shops"));
}

/** Every trade Dukania is set up for, each with its own page. */
export default async function ShopsPage() {
  const info = await getSiteInfo();
  return (
    <>
      <PageHero
        eyebrow="For your shop"
        title={"Set up for the way\nyour trade works."}
        lead="Pick your type of shop when you sign up and Dukania switches on what you need — and fills in the products your trade sells."
      />

      <section className="mx-auto max-w-7xl px-6 py-14">
        <ul className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3">
          {TRADES.map((t, i) => (
            <Reveal key={t.slug} delay={(i % 3) * 0.06}>
              <li className="h-full">
                <Link href={`/shops/${t.slug}`}
                  className="group flex h-full flex-col overflow-hidden rounded-3xl border border-hairline bg-white shadow-card transition hover:-translate-y-0.5 hover:border-brand/40">
                  <Image src={t.image} alt={t.name} width={1672} height={941} sizes="(max-width: 640px) 100vw, (max-width: 1024px) 50vw, 33vw"
                    style={{ objectPosition: `${t.focus} 40%` }} className="aspect-[16/10] h-auto w-full object-cover" />
                  <div className="flex flex-1 flex-col p-5">
                    <h2 className="font-display text-xl font-bold text-paper">{t.name}</h2>
                    <p className="mt-1 flex-1 text-sm text-dim">{t.short}</p>
                    <span className="mt-4 inline-flex items-center gap-1.5 text-sm font-semibold text-brand group-hover:text-brand-2">
                      See how it works <ArrowRight className="h-4 w-4" />
                    </span>
                  </div>
                </Link>
              </li>
            </Reveal>
          ))}
        </ul>
      </section>

      <section className="bg-[#f6f0e2] py-14">
        <div className="mx-auto max-w-3xl px-6 text-center">
          <p className={eyebrow}>Not in the list?</p>
          <h2 className="mt-2 font-display text-3xl font-bold tracking-tight">Dukania works for any counter.</h2>
          <p className="mt-3 text-dim">
            Billing, stock, GST and khata are the same for every shop. Tell us how you sell and we&apos;ll show you how to set it up.
          </p>
        </div>
      </section>

      <div className="pt-14" />
      <ClosingCta info={info} />
    </>
  );
}
