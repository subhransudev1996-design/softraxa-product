import type { Metadata } from "next";
import Link from "next/link";
import LegalPage from "@/components/legal-page";

// The web page app stores ask for: how to delete a Dukania account without
// the app. The in-app route is Business profile → Delete my account
// (request_account_deletion, migration 0058).
export const metadata: Metadata = {
  title: "Delete your account — Dukania by Softraxa",
  description: "How to delete your Dukania account and data.",
};

export default function DeleteAccountPage() {
  return (
    <LegalPage eyebrow="Your data" title="Delete your Dukania account" updated="1 October 2026">
      <section className="space-y-3">
        <h2>From the app</h2>
        <p>
          The shop owner opens <b>More</b> and taps the shop&apos;s name at the top (on a computer:{" "}
          <b>Business settings</b> in the sidebar), then taps <b>Delete my account</b> at the bottom. The request
          reaches us straight away.
        </p>
      </section>

      <section className="space-y-3">
        <h2>Without the app</h2>
        <p>
          Email <a href="mailto:support@softraxa.com?subject=Delete%20my%20Dukania%20account">support@softraxa.com</a>{" "}
          from the email address of the owner&apos;s login, with your shop&apos;s name. We may ask you to confirm
          it is you before deleting anything.
        </p>
      </section>

      <section className="space-y-3">
        <h2>What happens</h2>
        <ul>
          <li>We delete the shop, all its logins, products, stock, customers, suppliers and settings.</li>
          <li>Bills and payments that the law requires to be kept (such as GST invoices) are kept only for that period, then deleted.</li>
          <li>We confirm by email or WhatsApp when it is done, within 30 days of your request.</li>
          <li>Want a copy first? Use <b>Export all data</b> on the same screen before asking.</li>
        </ul>
        <p>
          More about what we keep: <Link href="/privacy">privacy policy</Link>.
        </p>
      </section>
    </LegalPage>
  );
}
