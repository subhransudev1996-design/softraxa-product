import type { Metadata } from "next";
import PartnerMeClient from "@/components/account/partner-me-client";

export const metadata: Metadata = {
  title: "Your partner numbers — Dukania",
  robots: { index: false, follow: false },
};

/** The signed-in influencer partner's page (migration 0107). */
export default function PartnerMePage() {
  return (
    <section className="mx-auto max-w-5xl px-4 py-12 sm:px-6">
      <PartnerMeClient />
    </section>
  );
}
