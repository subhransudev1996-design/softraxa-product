import type { Metadata } from "next";
import PayLoader from "@/components/pay/pay-loader";
import { getSiteInfo } from "@/lib/site-info";
import { eyebrow } from "@/lib/ui";

// Personal to each shop: never cached.
export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Pay for your Dukania plan",
  description: "Renew or buy your Dukania plan online by UPI, card or netbanking.",
  robots: { index: false, follow: false },
};

/** Online payment (migration 0105): the app opens this with ?t=<pay link>. */
export default async function PayPage({ searchParams }: { searchParams: Promise<{ t?: string }> }) {
  const { t } = await searchParams;
  const info = await getSiteInfo();
  const token = typeof t === "string" && /^[0-9a-f]{32}$/.test(t) ? t : null;
  return (
    <section className="mx-auto max-w-6xl px-4 py-12 sm:px-6">
      <p className={eyebrow}>Dukania plans</p>
      <h1 className="mt-2 font-display text-3xl font-bold tracking-tight sm:text-4xl">Pay for your plan</h1>
      <p className="mt-2 max-w-xl text-dim">Your plan turns on as soon as you pay — in the app too.</p>
      <div className="mt-8">
        <PayLoader initialToken={token} whatsapp={info.whatsapp} />
      </div>
    </section>
  );
}
