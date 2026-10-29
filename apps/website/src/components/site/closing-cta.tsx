import Image from "next/image";
import Link from "next/link";
import { ArrowRight, MessageCircle } from "lucide-react";
import { whatsappLink, type SiteInfo } from "@/lib/site-info";
import { eyebrow } from "@/lib/ui";

/** The purple "start free trial" panel with WhatsApp help beside it — the end of most pages. */
export default function ClosingCta({
  info,
  title = "Ready to run your shop on Dukania?",
  waText = "Hi, I want to know more about Dukania for my shop.",
}: {
  info: SiteInfo;
  title?: string;
  waText?: string;
}) {
  const trial = info.trialDays ? `${info.trialDays}-day free trial` : "free trial";
  const wa = whatsappLink(info, waText);
  return (
    <section className="mx-auto mb-12 grid max-w-7xl grid-cols-1 gap-4 px-6 lg:grid-cols-[1.4fr_1fr]">
      <div className="flex flex-col justify-center gap-5 rounded-3xl bg-brand px-8 py-10 text-white sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h2 className="font-display text-2xl font-bold tracking-tight sm:text-3xl">{title}</h2>
          <p className="mt-2 text-white/80">Start your {trial.toLowerCase()} today — we&apos;ll help you set it up.</p>
        </div>
        <Link href="/download" className="stamp-press inline-flex min-h-12 shrink-0 items-center gap-2 rounded-xl bg-white px-6 text-sm font-semibold text-brand hover:bg-brand-soft">
          Start free trial <ArrowRight className="h-4 w-4" />
        </Link>
      </div>
      <div className="relative flex items-center gap-4 overflow-hidden rounded-3xl border border-hairline bg-white p-5 shadow-card">
        <Image src="/images/site/support-person.jpg" alt="Dukania support on WhatsApp" width={1536} height={1024} sizes="120px"
          className="h-28 w-28 shrink-0 rounded-2xl object-cover object-[50%_25%]" />
        <div>
          <p className={eyebrow}>WhatsApp help</p>
          <p className="mt-1 font-semibold">Talk to us on WhatsApp.</p>
          <p className="mt-1 text-sm text-dim">Questions? Get an honest answer and we&apos;ll help you start.</p>
          {wa ? (
            <a href={wa} target="_blank" rel="noreferrer" className="mt-3 inline-flex min-h-10 items-center gap-2 rounded-xl bg-[#25d366] px-4 text-sm font-semibold text-white">
              <MessageCircle className="h-4 w-4" /> Chat on WhatsApp
            </a>
          ) : (
            <Link href="/contact" className="mt-3 inline-flex min-h-10 items-center rounded-xl bg-brand px-4 text-sm font-semibold text-white">Contact us</Link>
          )}
        </div>
        <p className="hand absolute right-4 top-3 hidden rotate-6 text-xl text-paper/70 sm:block">Real people.<br />Real support.</p>
      </div>
    </section>
  );
}
