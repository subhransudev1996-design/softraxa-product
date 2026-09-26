import type { Metadata } from "next";
import PageHero from "@/components/page-hero";
import SectionHeading from "@/components/section-heading";
import Reveal from "@/components/reveal";
import CtaBand from "@/components/cta-band";
import { getPageContentMap, getPageSeo, buildPageMetadata } from "@/lib/cms";
import { cmsIcon, type CmsItem } from "@/lib/cms-types";

export async function generateMetadata(): Promise<Metadata> {
  const seo = await getPageSeo("/about");
  return buildPageMetadata(seo);
}

export default async function AboutPage() {
  const content = await getPageContentMap("about");
  const seo = await getPageSeo("/about");

  const heroContent = content.hero?.content || {
    eyebrow: "About",
    title: "We're Softraxa.",
    lead: "A small software studio building practical, offline-first business software for the way work actually happens in India."
  };

  const storyParagraphs = content.story?.paragraphs || [
    "Softraxa started from a simple frustration: most business software assumes a fast, always-on internet connection and a person sitting at a desk. Real shops don't work like that. The connection drops. The counter is busy. Staff need an answer in seconds.",
    "So we build software that survives bad connections and keeps up with a busy shop floor — starting with Dukania, our offline-first billing and inventory app. Everything we make is held to the same bar: it works offline, it's priced for real margins, and the people who built it are the ones who support it.",
    "We're a small, focused team. That's deliberate — it's how one group of people can own a whole product, end to end, and stay accountable for it."
  ];

  const valuesItems = content.values?.items || [
    { title: "Offline-first, always", body: "We build for the real world, where the network drops mid-sale. The software has to keep working anyway.", icon: "WifiOff" },
    { title: "India-first", body: "Priced and designed for Indian shops and businesses — their margins, their workflows, their languages.", icon: "IndianRupee" },
    { title: "Direct support", body: "You talk to the people who wrote the code. No call centre, no ticket lottery.", icon: "MessageCircle" },
    { title: "Ship, then improve", body: "We'd rather put working software in your hands early and improve it with you than disappear for six months.", icon: "Compass" }
  ];

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

      {/* story */}
      <section className="mx-auto max-w-3xl px-6 py-20">
        <Reveal>
          <div className="space-y-6 text-lg leading-relaxed text-dim">
            {storyParagraphs.map((paragraph: string, idx: number) => {
              // Highlight "Dukania" if it matches
              if (paragraph.includes("Dukania")) {
                const parts = paragraph.split("Dukania");
                return (
                  <p key={idx}>
                    {parts[0]}
                    <span className="text-paper">Dukania</span>
                    {parts[1]}
                  </p>
                );
              }
              return <p key={idx}>{paragraph}</p>;
            })}
          </div>
        </Reveal>
      </section>

      {/* values */}
      <section className="mx-auto max-w-7xl px-6 py-16">
        <SectionHeading eyebrow="What we believe" title="The principles behind every build." />
        <div className="mt-12 grid gap-6 sm:grid-cols-2">
          {valuesItems.map((v: CmsItem, i: number) => {
            const IconComponent = cmsIcon(v.icon);
            return (
              <Reveal key={v.title} delay={(i % 2) * 0.08}>
                <div className="glass flex h-full gap-5 rounded-2xl p-6">
                  <div className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-violet/25 to-sky/20 ring-1 ring-paper/10">
                    <IconComponent className="h-5 w-5 text-sky" aria-hidden="true" />
                  </div>
                  <div>
                    <h3 className="font-display text-lg font-semibold">{v.title}</h3>
                    <p className="mt-2 text-sm text-dim">{v.body}</p>
                  </div>
                </div>
              </Reveal>
            );
          })}
        </div>
      </section>

      <CtaBand title="Want to build something with us?" cta="Get in touch" />
    </>
  );
}
