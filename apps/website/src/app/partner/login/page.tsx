import type { Metadata } from "next";
import PartnerLoginClient from "@/components/account/partner-login-client";

export const metadata: Metadata = {
  title: "Partner sign in — Dukania",
  robots: { index: false, follow: false },
};

/** Influencer partners sign in (migration 0107). */
export default function PartnerLoginPage() {
  return (
    <section className="px-4 pb-20 pt-12 sm:px-6">
      <PartnerLoginClient />
    </section>
  );
}
