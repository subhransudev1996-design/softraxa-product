import type { Metadata } from "next";
import Image from "next/image";
import { HeartHandshake, Languages, Lock, MessageCircle, Receipt, WifiOff } from "lucide-react";
import Reveal from "@/components/reveal";
import PageHero from "@/components/page-hero";
import ClosingCta from "@/components/site/closing-cta";
import { getPageSeo, buildPageMetadata } from "@/lib/cms";
import { getSiteInfo } from "@/lib/site-info";
import { eyebrow } from "@/lib/ui";

export async function generateMetadata(): Promise<Metadata> {
  return buildPageMetadata(await getPageSeo("/about"));
}

const BELIEFS = [
  { icon: WifiOff, title: "The counter never waits", body: "Internet drops; customers don't. So billing works offline and catches up on its own." },
  { icon: Languages, title: "Your language, your way", body: "Dukania speaks 11 Indian languages and sells by kg, metre, piece or pack — the way you already work." },
  { icon: Receipt, title: "Honest prices", body: "A free trial first, one clear price, every feature included. No surprise charges." },
  { icon: Lock, title: "Your data is yours", body: "Each shop's data is kept apart, and you can export it to Excel any time." },
  { icon: MessageCircle, title: "Real people to talk to", body: "Help on WhatsApp from people who know the app — not a call centre script." },
  { icon: HeartHandshake, title: "Only what really works", body: "Nothing goes on this website before it ships in the app." },
];

/** Who we are and what we stand for — no made-up numbers. */
export default async function AboutPage() {
  const info = await getSiteInfo();
  return (
    <>
      <PageHero
        eyebrow="About Dukania"
        title={"Software made for\nIndian shop owners."}
        lead="Dukania started with a simple question: why do so many good shops still run on a notebook and a calculator? Because most software wasn't made for them. Dukania is."
        aside={
          <Image src="/images/site/hero-shopkeeper.jpg" alt="A shop owner at his counter" width={1672} height={941} priority
            sizes="(max-width: 1024px) 90vw, 560px" className="aspect-[4/3] h-auto w-full rounded-3xl object-cover object-right shadow-card" />
        }
      />

      <section className="mx-auto grid max-w-7xl grid-cols-1 gap-10 px-6 py-14 lg:grid-cols-2 lg:items-center">
        <Reveal>
          <p className={eyebrow}>Why Dukania</p>
          <h2 className="mt-2 font-display text-3xl font-bold tracking-tight">Built at the counter, not in a boardroom.</h2>
          <div className="mt-4 space-y-4 text-dim">
            <p>
              A kirana owner bills a hundred customers before lunch. A mobile shop tracks every IMEI. A hardware shop
              cuts wire from a roll. A workshop juggles ten vehicles at once. They all need the same things: fast bills,
              stock they can trust, GST without panic, and money owed written down somewhere safer than a notebook.
            </p>
            <p>
              Dukania puts all of that on the phone you already have — and on the counter PC when you want it — in your
              language, working even when the internet doesn&apos;t.
            </p>
          </div>
        </Reveal>
        <Reveal delay={0.1}>
          <div className="rounded-3xl border border-hairline bg-[#fff8e6] p-6 shadow-card sm:p-8">
            <p className="hand -rotate-2 text-3xl leading-snug text-paper">
              &ldquo;Make the shop owner&apos;s day easier — every single feature.&rdquo;
            </p>
            <p className="mt-4 text-sm font-semibold text-dim">— the one rule we build Dukania by</p>
          </div>
        </Reveal>
      </section>

      <section className="bg-brand-soft/50 py-14">
        <div className="mx-auto max-w-7xl px-6">
          <p className={eyebrow}>What we believe</p>
          <h2 className="mt-2 font-display text-3xl font-bold tracking-tight">Six promises we keep.</h2>
          <ul className="mt-8 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {BELIEFS.map((b) => (
              <li key={b.title} className="rounded-2xl border border-hairline bg-white p-5 shadow-card">
                <span className="inline-flex h-10 w-10 items-center justify-center rounded-xl bg-brand-soft text-brand"><b.icon className="h-5 w-5" /></span>
                <p className="mt-3 font-bold text-paper">{b.title}</p>
                <p className="mt-1 text-sm text-dim">{b.body}</p>
              </li>
            ))}
          </ul>
        </div>
      </section>

      {(info.address || info.email) && (
        <section className="mx-auto max-w-7xl px-6 pt-14">
          <div className="rounded-3xl border border-hairline bg-white p-6 shadow-card">
            <p className={eyebrow}>Find us</p>
            {info.address && <p className="mt-2 text-paper">{info.address}</p>}
            {info.email && <p className="mt-1 text-dim">{info.email}</p>}
          </div>
        </section>
      )}

      <div className="pt-14" />
      <ClosingCta info={info} />
    </>
  );
}
