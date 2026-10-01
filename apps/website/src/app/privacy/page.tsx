import type { Metadata } from "next";
import Link from "next/link";
import LegalPage from "@/components/legal-page";

// Draft written from what the software actually does (October 2026).
// Have a lawyer review it before launch.
export const metadata: Metadata = {
  title: "Privacy policy — Dukania by Softraxa",
  description: "What data the Dukania app keeps, why, who processes it, and how to have it deleted.",
};

export default function PrivacyPage() {
  return (
    <LegalPage eyebrow="Legal" title="Privacy policy" updated="1 October 2026">
      <p>
        This policy explains what Softraxa (&quot;we&quot;) collects when a shop uses the Dukania app and website,
        why, and what you can ask us to do with it. Dukania is billing and stock software for shops; the shop
        that uses it decides what goes into it.
      </p>

      <section className="space-y-3">
        <h2>What we keep</h2>
        <ul>
          <li><b>Your account:</b> the owner&apos;s and staff members&apos; names, email addresses and phone numbers, and their logins.</li>
          <li><b>Your shop:</b> name, address, GSTIN, UPI ID, logo and settings.</li>
          <li><b>Your business records:</b> products, stock, bills, purchases, expenses, payments, and the customers and suppliers you enter (names, phone numbers, addresses, GSTINs, amounts due).</li>
          <li><b>Your subscription:</b> plan, payments to us, payment references you send us, and support conversations.</li>
          <li><b>Technical data:</b> a device identifier for notifications, and crash reports (the error, the app version, your shop&apos;s ID and the user&apos;s role — not your bills or customers).</li>
        </ul>
      </section>

      <section className="space-y-3">
        <h2>Why</h2>
        <p>
          To run the app for you: keep your records, make your bills and GST reports, sync between your devices,
          send you notifications you turned on, handle your subscription and answer your support requests.
          We do not sell your data and we do not use your business records for advertising.
        </p>
      </section>

      <section className="space-y-3">
        <h2>Shared product list</h2>
        <p>
          When you add a product, its name, brand, category, unit, HSN code, GST rate and barcode are added to a
          product list other shops can pick from, so they don&apos;t have to type it again. Your prices, stock,
          product codes, descriptions and photos are never shared, and no other shop can see that a product came
          from you.
        </p>
      </section>

      <section className="space-y-3">
        <h2>Your customers&apos; data</h2>
        <p>
          The customers and suppliers you enter are your records. You are responsible for having their
          permission to keep their details; we keep them only to provide the app to you.
        </p>
      </section>

      <section className="space-y-3">
        <h2>Who processes it for us</h2>
        <ul>
          <li>Supabase — database and logins</li>
          <li>ImageKit — shop logos and product photos</li>
          <li>Google Firebase — notifications to your phone</li>
          <li>Sentry — crash reports</li>
          <li>Resend — account emails</li>
        </ul>
        <p>They process data only to provide their service to us.</p>
      </section>

      <section className="space-y-3">
        <h2>How long we keep it</h2>
        <p>
          While your account is open. After you ask us to delete your account we delete it, except records the
          law requires us or you to keep (for example GST invoices), which we keep only for that period.
          You can export all your data from the app at any time.
        </p>
      </section>

      <section className="space-y-3">
        <h2>Your choices</h2>
        <p>
          You can see and correct your data in the app, export it, and ask us to delete your account — see{" "}
          <Link href="/delete-account">Delete your account</Link>. For anything else write to{" "}
          <a href="mailto:support@softraxa.com">support@softraxa.com</a>.
        </p>
      </section>
    </LegalPage>
  );
}
