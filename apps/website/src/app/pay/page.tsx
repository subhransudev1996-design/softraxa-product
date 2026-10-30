import type { Metadata } from "next";
import { Lock } from "lucide-react";
import PayLoader from "@/components/pay/pay-loader";
import { getSiteInfo } from "@/lib/site-info";

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
    <section className="mx-auto max-w-6xl px-4 pb-28 pt-10 sm:px-6 lg:pb-20">
      <div className="mb-8 flex flex-wrap items-end justify-between gap-3">
        <h1 className="font-display text-3xl font-bold tracking-tight text-paper">Checkout</h1>
        <p className="inline-flex items-center gap-1.5 font-mono text-xs uppercase tracking-wider text-dim">
          <Lock className="h-3.5 w-3.5" /> Secure payment · dukania.in
        </p>
      </div>
      <PayLoader initialToken={token} whatsapp={info.whatsapp} />
    </section>
  );
}
