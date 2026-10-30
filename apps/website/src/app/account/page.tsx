import type { Metadata } from "next";
import AccountLoader from "@/components/account/account-loader";
import { getSiteInfo } from "@/lib/site-info";

// Personal to each shop: never cached.
export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "My account — Dukania",
  robots: { index: false, follow: false },
};

/** The shop's account (migration 0106). The app can open it with ?t=<pay link>. */
export default async function AccountPage({ searchParams }: { searchParams: Promise<{ t?: string }> }) {
  const { t } = await searchParams;
  const info = await getSiteInfo();
  const token = typeof t === "string" && /^[0-9a-f]{32}$/.test(t) ? t : null;
  return (
    <section className="mx-auto max-w-6xl px-4 pb-20 pt-10 sm:px-6">
      <AccountLoader initialToken={token} whatsapp={info.whatsapp} />
    </section>
  );
}
