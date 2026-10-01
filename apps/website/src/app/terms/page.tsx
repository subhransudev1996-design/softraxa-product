import type { Metadata } from "next";
import Link from "next/link";
import LegalPage from "@/components/legal-page";

// Draft written from how Dukania is sold (October 2026). Have a lawyer
// review it before launch.
export const metadata: Metadata = {
  title: "Terms of use — Dukania by Softraxa",
  description: "The terms for using the Dukania billing and stock app.",
};

export default function TermsPage() {
  return (
    <LegalPage eyebrow="Legal" title="Terms of use" updated="1 October 2026">
      <p>
        These terms apply when a shop uses Dukania, the billing and stock app made by Softraxa. By creating an
        account you accept them for your shop.
      </p>

      <section className="space-y-3">
        <h2>Your subscription</h2>
        <ul>
          <li>New shops get a free trial. After it, the app needs a paid plan.</li>
          <li>Plans and prices are agreed with Softraxa. You pay by UPI, cash or bank transfer; your plan is extended when we confirm the payment.</li>
          <li>When a subscription ends, you can still open the app, see your records and export them, but you cannot make new bills until you renew.</li>
          <li>Your plan sets how many users, products and bills a month you can have.</li>
        </ul>
      </section>

      <section className="space-y-3">
        <h2>Your responsibilities</h2>
        <ul>
          <li>The bills, GST returns and records you make are your responsibility. Check them, and ask your accountant when you are unsure.</li>
          <li>Keep your logins private and remove staff who leave.</li>
          <li>Only enter customer details you are allowed to keep.</li>
          <li>Don&apos;t use the app for anything illegal.</li>
        </ul>
      </section>

      <section className="space-y-3">
        <h2>Our responsibilities</h2>
        <ul>
          <li>We keep the service running and your data backed up, and fix problems you report.</li>
          <li>We may suspend an account that doesn&apos;t pay or that misuses the service, and will tell you why.</li>
          <li>We handle your data as our <Link href="/privacy">privacy policy</Link> says.</li>
        </ul>
      </section>

      <section className="space-y-3">
        <h2>Limits</h2>
        <p>
          The app is provided as it is. We are not liable for indirect losses, or for losses from wrong data you
          entered. Our total liability is limited to what you paid us in the twelve months before the problem.
        </p>
      </section>

      <section className="space-y-3">
        <h2>Ending</h2>
        <p>
          You can stop at any time and export your data. To close your account, see{" "}
          <Link href="/delete-account">Delete your account</Link>. These terms follow Indian law. Questions:{" "}
          <a href="mailto:support@softraxa.com">support@softraxa.com</a>.
        </p>
      </section>
    </LegalPage>
  );
}
