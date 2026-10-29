import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { ArrowRight, Check, Info, MessageCircle } from "lucide-react";
import Reveal from "@/components/reveal";
import PageHero from "@/components/page-hero";
import FaqGrid from "@/components/home/faq-grid";
import ClosingCta from "@/components/site/closing-cta";
import LucideIcon, { type IconName } from "@/components/site/lucide-icon";
import { LaptopFrame } from "@/components/device-frame";
import { desktopShots } from "@/lib/shots";
import { getPageSeo, buildPageMetadata } from "@/lib/cms";
import { getSiteInfo, whatsappLink } from "@/lib/site-info";
import { btnGhost, btnPrimary, eyebrow } from "@/lib/ui";

export async function generateMetadata(): Promise<Metadata> {
  return buildPageMetadata(await getPageSeo("/gst"));
}

const ON_THE_BILL = [
  "HSN code and GST rate from the product",
  "CGST + SGST in your state, IGST outside it",
  "Place of supply worked out for you",
  "The customer's GSTIN on B2B bills",
  "Non-GST bills, cash memos and estimates too",
];

const MONTH_END: { n: string; title: string; body: string }[] = [
  { n: "1", title: "Bill as usual", body: "Every sale and purchase goes in with its GST — nothing extra to do through the month." },
  { n: "2", title: "Open GST returns", body: "Pick the month. Dukania shows GSTR-1 and GSTR-3B, and matches your purchases with GSTR-2B." },
  { n: "3", title: "Download and upload", body: "Download the GSTR-1 file and upload it on the GST portal — or send the workbook to your CA." },
];

const MORE: { icon: IconName; title: string; body: string }[] = [
  { icon: "FileJson", title: "GSTR-1 file for the portal", body: "B2B, B2C, credit notes, HSN summary and documents — in the portal's format." },
  { icon: "Calculator", title: "GSTR-3B with the cash to pay", body: "Output tax, input tax credit, and what's left to pay in cash." },
  { icon: "GitCompare", title: "GSTR-2B matching", body: "Find purchases your suppliers haven't filed before you claim the credit." },
  { icon: "Repeat", title: "Reverse charge", body: "RCM purchases recorded and counted where they belong." },
  { icon: "Store", title: "Composition shops", body: "Bills of supply and the CMP-08 figures." },
  { icon: "Route", title: "E-way bill files", body: "Make the e-way bill file for goods on the move and upload it." },
  { icon: "FileSpreadsheet", title: "A workbook for your CA", body: "GSTR-1, GSTR-3B and the purchase register in one Excel file." },
  { icon: "Percent", title: "GST 2.0 rates", body: "Ready for the new GST rate slabs." },
];

export default async function GstPage() {
  const info = await getSiteInfo();
  const wa = whatsappLink(info, "Hi, I want to see how Dukania handles GST for my shop.");

  const faqs = [
    { q: "Does Dukania file my return on the portal?", a: "Dukania makes the files and the figures; you or your CA upload them on the GST portal. That keeps you in control of what is filed." },
    { q: "Do I need to know GST to use it?", a: "No. Set the GST rate and HSN on the product once — every bill after that is right by itself." },
    { q: "Can I make bills without GST?", a: "Yes. Non-GST bills, cash memos and estimates are there for when you need them." },
    { q: "Does it make e-invoices (IRN)?", a: "Not yet. Dukania makes GST bills, the GSTR-1 file and e-way bill files; e-invoicing with an IRN is not supported yet." },
  ];

  return (
    <>
      <PageHero
        eyebrow="GST"
        title={"GST from the bill\nto the return."}
        lead="Right GST on every bill, and the files your return needs at month end — from the billing you already do."
        actions={
          <>
            <Link href="/download" className={btnPrimary}>Start free trial <ArrowRight className="h-4 w-4" /></Link>
            <a href={wa || "/contact"} target={wa ? "_blank" : undefined} rel="noreferrer" className={btnGhost}>
              <MessageCircle className="h-4 w-4" /> Ask about GST
            </a>
          </>
        }
        aside={
          <LaptopFrame>
            <Image src={desktopShots.reports.src} width={desktopShots.reports.width} height={desktopShots.reports.height}
              alt={desktopShots.reports.alt} priority sizes="(max-width: 1024px) 90vw, 560px" className="h-auto w-full" />
          </LaptopFrame>
        }
      />

      <section className="mx-auto grid max-w-7xl grid-cols-1 gap-8 px-6 py-14 lg:grid-cols-2 lg:items-start">
        <Reveal>
          <p className={eyebrow}>On every bill</p>
          <h2 className="mt-2 font-display text-3xl font-bold tracking-tight">The right tax, without thinking about it.</h2>
          <ul className="mt-6 space-y-3 text-sm">
            {ON_THE_BILL.map((b) => (
              <li key={b} className="flex items-center gap-2.5">
                <span className="inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-brand text-white"><Check className="h-3 w-3" /></span>
                {b}
              </li>
            ))}
          </ul>
        </Reveal>
        <Reveal delay={0.1}>
          <p className={eyebrow}>At month end</p>
          <h2 className="mt-2 font-display text-3xl font-bold tracking-tight">Three steps, not three days.</h2>
          <ol className="mt-6 space-y-3">
            {MONTH_END.map((s) => (
              <li key={s.n} className="flex gap-4 rounded-2xl border border-hairline bg-white p-4 shadow-card">
                <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-brand font-display text-lg font-bold text-white">{s.n}</span>
                <span>
                  <span className="block font-bold text-paper">{s.title}</span>
                  <span className="mt-0.5 block text-sm text-dim">{s.body}</span>
                </span>
              </li>
            ))}
          </ol>
        </Reveal>
      </section>

      <section className="bg-brand-soft/50 py-14">
        <div className="mx-auto max-w-7xl px-6">
          <p className={eyebrow}>What Dukania makes for you</p>
          <h2 className="mt-2 font-display text-3xl font-bold tracking-tight">Everything your GST needs.</h2>
          <ul className="mt-8 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {MORE.map((m) => (
              <li key={m.title} className="rounded-2xl border border-hairline bg-white p-5 shadow-card">
                <span className="inline-flex h-10 w-10 items-center justify-center rounded-xl bg-brand-soft text-brand">
                  <LucideIcon name={m.icon} className="h-5 w-5" />
                </span>
                <p className="mt-3 font-bold text-paper">{m.title}</p>
                <p className="mt-1 text-sm text-dim">{m.body}</p>
              </li>
            ))}
          </ul>
          <p className="mt-6 flex items-start gap-2 text-sm text-dim">
            <Info className="mt-0.5 h-4 w-4 shrink-0 text-brand" />
            Dukania makes the files and figures; you or your accountant check and upload them on the GST portal. E-invoicing (IRN) is not supported yet.
          </p>
        </div>
      </section>

      <section className="mx-auto max-w-7xl px-6 py-14">
        <p className={eyebrow}>Questions</p>
        <h2 className="mt-2 font-display text-2xl font-bold tracking-tight sm:text-3xl">About GST in Dukania.</h2>
        <div className="mt-6"><FaqGrid items={faqs} /></div>
      </section>

      <ClosingCta info={info} waText="Hi, I want to see how Dukania handles GST for my shop." />
    </>
  );
}
