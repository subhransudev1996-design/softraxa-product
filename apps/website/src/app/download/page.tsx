import type { Metadata } from "next";
import { Smartphone, Monitor, Download, MessageCircle, Check, ShieldAlert } from "lucide-react";
import PageHero from "@/components/page-hero";
import Reveal from "@/components/reveal";
import { getSiteInfo, whatsappLink, type SiteInfo } from "@/lib/site-info";

export const metadata: Metadata = {
  title: "Download Dukania — Android app & Windows software | Softraxa",
  description:
    "Download Dukania billing and inventory software for Android phones and Windows PCs. Start with a free trial — no card, no payment.",
  alternates: { canonical: "/download" },
};

/**
 * Where shops get the app. The links come from the admin panel's Settings
 * (public_site_info); without a link, the card offers WhatsApp instead.
 */
export default async function DownloadPage() {
  const info = await getSiteInfo();
  const trial = info.trialDays ? `${info.trialDays}-day free trial` : "Free trial";

  return (
    <>
      <PageHero
        eyebrow="Download"
        title="Get Dukania on your phone or PC."
        lead={`${trial} on every new shop — no card, no payment. The same account works on Android and Windows.`}
      />

      <section className="mx-auto grid max-w-5xl gap-6 px-6 py-14 md:grid-cols-2">
        <Reveal>
          <PlatformCard
            icon={<Smartphone className="h-6 w-6" />}
            name="Android app"
            needs="Android 7.0 or newer"
            url={info.androidUrl}
            file="Dukania.apk"
            info={info}
            points={[
              "Bill at the counter, check stock anywhere",
              "Scan barcodes with the camera",
              "Print on Bluetooth thermal printers",
              "Works without internet",
            ]}
            steps={[
              "Tap Download and open the file when it finishes.",
              "If Android asks, allow installing apps from your browser (Settings → Install unknown apps).",
              "Tap Install, open Dukania and sign up with your email.",
            ]}
          />
        </Reveal>
        <Reveal delay={0.1}>
          <PlatformCard
            icon={<Monitor className="h-6 w-6" />}
            name="Windows software"
            needs="Windows 10 or 11, 64-bit"
            url={info.windowsUrl}
            file="Dukania-Setup.exe"
            info={info}
            points={[
              "Fast keyboard billing (F2 search, F12 checkout)",
              "Barcode scanner and any printer, thermal or A4",
              "Sales chart, top products and reports",
              "Installs without administrator rights",
            ]}
            steps={[
              "Download and run Dukania-Setup.exe.",
              "Windows may say “Windows protected your PC” — click More info → Run anyway. (Our installer isn't from the Microsoft Store yet.)",
              "Finish the setup, open Dukania from the Start menu and log in.",
            ]}
          />
        </Reveal>
      </section>

      <section className="mx-auto max-w-5xl px-6 pb-20">
        <Reveal>
          <div className="glass rounded-3xl p-8">
            <h2 className="font-display text-2xl font-bold tracking-tight">After you install</h2>
            <ol className="mt-6 grid gap-6 sm:grid-cols-3">
              {[
                ["1", "Sign up", "Use your email and a password. We send a link to confirm the email."],
                ["2", "Set up your shop", "Shop name, GST details and your type of shop — about two minutes."],
                ["3", "Start billing", "Add products (or pick them from our product list) and make your first bill."],
              ].map(([n, title, body]) => (
                <li key={n} className="flex gap-4">
                  <span className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-paper text-sm font-bold text-bg">{n}</span>
                  <div>
                    <p className="font-semibold text-paper">{title}</p>
                    <p className="mt-1 text-sm text-dim">{body}</p>
                  </div>
                </li>
              ))}
            </ol>
            {info.whatsapp && (
              <p className="mt-8 text-sm text-dim">
                Stuck anywhere?{" "}
                <a className="font-semibold text-sky underline" href={whatsappLink(info, "Hi, I need help installing Dukania.")} target="_blank" rel="noreferrer">
                  Message us on WhatsApp
                </a>{" "}
                and we&apos;ll set it up with you over a call.
              </p>
            )}
          </div>
        </Reveal>
      </section>
    </>
  );
}

function PlatformCard({
  icon, name, needs, url, file, info, points, steps,
}: {
  icon: React.ReactNode;
  name: string;
  needs: string;
  url: string;
  file: string;
  info: SiteInfo;
  points: string[];
  steps: string[];
}) {
  const wa = whatsappLink(info, `Hi, please send me the Dukania ${name}.`);
  return (
    <div className="glass flex h-full flex-col rounded-3xl p-7">
      <div className="flex items-center gap-4">
        <span className="inline-flex h-12 w-12 items-center justify-center rounded-2xl bg-gradient-to-br from-violet to-sky text-white shadow-lg">
          {icon}
        </span>
        <div>
          <h2 className="font-display text-xl font-bold tracking-tight">{name}</h2>
          <p className="text-sm text-dim">{needs}</p>
        </div>
      </div>

      <ul className="mt-6 space-y-2.5 text-sm">
        {points.map((p) => (
          <li key={p} className="flex items-start gap-2.5 text-paper">
            <Check className="mt-0.5 h-4 w-4 shrink-0 text-teal" /> {p}
          </li>
        ))}
      </ul>

      <div className="mt-7">
        {url ? (
          <a
            href={url}
            download={file}
            className="stamp-press inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-xl bg-paper px-5 text-sm font-semibold text-bg hover:bg-paper/90"
          >
            <Download className="h-4 w-4" /> Download for {name.split(" ")[0]}
          </a>
        ) : wa ? (
          <a
            href={wa}
            target="_blank"
            rel="noreferrer"
            className="inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-xl bg-emerald-600 px-5 text-sm font-semibold text-white hover:bg-emerald-700"
          >
            <MessageCircle className="h-4 w-4" /> Get it on WhatsApp
          </a>
        ) : (
          <p className="rounded-xl border border-hairline px-4 py-3 text-center text-sm text-dim">Coming soon</p>
        )}
      </div>

      <div className="mt-7 border-t border-hairline pt-5">
        <p className="flex items-center gap-2 text-xs font-semibold uppercase tracking-wider text-dim">
          <ShieldAlert className="h-3.5 w-3.5" /> How to install
        </p>
        <ol className="mt-3 list-decimal space-y-2 pl-5 text-sm text-dim">
          {steps.map((s) => <li key={s}>{s}</li>)}
        </ol>
      </div>
    </div>
  );
}
