import type { ReactNode } from "react";
import PageHero from "./page-hero";

/** Plain reading layout for the privacy policy, terms and account deletion pages. */
export default function LegalPage({
  eyebrow,
  title,
  updated,
  children,
}: {
  eyebrow: string;
  title: string;
  updated: string;
  children: ReactNode;
}) {
  return (
    <>
      <PageHero eyebrow={eyebrow} title={title} lead={`Last updated ${updated}`} />
      <article className="mx-auto max-w-3xl space-y-8 px-6 py-16 text-base leading-relaxed text-dim [&_h2]:font-display [&_h2]:text-2xl [&_h2]:font-bold [&_h2]:text-paper [&_li]:ml-5 [&_li]:list-disc [&_a]:text-sky [&_a]:underline">
        {children}
      </article>
    </>
  );
}
