import type { Metadata } from "next";
import Link from "next/link";
import LegalPage from "@/components/legal-page";

// Help page for the Dukania AI assistant (supabase/functions/shop-mcp,
// migration 0086). The same steps are in the app: More → ChatGPT & Claude.
export const metadata: Metadata = {
  title: "Use Dukania from ChatGPT or Claude — Dukania by Softraxa",
  description:
    "Connect your Dukania shop to ChatGPT or Claude and ask about sales, stock, dues and bills in plain words.",
};

const CONNECTOR_URL = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/shop-mcp`;

export default function AiHelpPage() {
  return (
    <LegalPage eyebrow="Dukania AI" title="Use Dukania from ChatGPT or Claude" updated="26 October 2026">
      <p>
        Connect your shop to ChatGPT or Claude once, then just ask: <i>&quot;How is my shop doing today?&quot;</i>,{" "}
        <i>&quot;Who owes me money?&quot;</i>, <i>&quot;What is running low?&quot;</i>,{" "}
        <i>&quot;Show this week&apos;s sales.&quot;</i>, <i>&quot;Bill Ramesh 2 Parle-G, paid by UPI.&quot;</i>,{" "}
        <i>&quot;Add Maggi 70g at ₹14, GST 12%.&quot;</i>, or share a photo of a supplier&apos;s bill and say{" "}
        <i>&quot;enter this purchase&quot;</i>. You can ask in Hindi or your own language too.
      </p>

      <section className="space-y-3">
        <h2>Before you start</h2>
        <ul>
          <li>The AI assistant must be in your shop&apos;s plan. If it isn&apos;t, <Link href="/contact">contact us</Link> to add it.</li>
          <li>Staff can use it only if the shop owner allows them (Staff &amp; Permissions in the app).</li>
          <li>Some ChatGPT and Claude plans don&apos;t allow connectors.</li>
        </ul>
      </section>

      <section className="space-y-3">
        <h2>Your connection link</h2>
        <p>
          In the Dukania app open <b>More → ChatGPT &amp; Claude</b> and press <b>Copy link</b>. It is the same for
          every shop:
        </p>
        <p className="break-all rounded-lg border border-white/15 px-4 py-3 font-mono text-sm text-paper">{CONNECTOR_URL}</p>
      </section>

      <section className="space-y-3">
        <h2>Add it to ChatGPT</h2>
        <ol className="ml-5 list-decimal space-y-1">
          <li>In ChatGPT (chatgpt.com), open <b>Plugins</b> and press <b>Add</b>.</li>
          <li>Paste the link as the <b>Server URL</b>, choose <b>OAuth</b>, tick <b>I understand</b>, then press <b>Create</b>.</li>
          <li>Sign in with your Dukania email and password, then press <b>Allow</b>.</li>
        </ol>
      </section>

      <section className="space-y-3">
        <h2>Add it to Claude</h2>
        <ol className="ml-5 list-decimal space-y-1">
          <li>In Claude (claude.ai), open <b>Settings → Connectors</b> and press <b>Add custom connector</b>.</li>
          <li>Name it Dukania, paste the link, then press <b>Add</b>.</li>
          <li>Press <b>Connect</b>, sign in with your Dukania email and password, then press <b>Allow</b>.</li>
        </ol>
      </section>

      <section className="space-y-3">
        <h2>What it can see and do</h2>
        <p>
          It sees only what you can see in the Dukania app: products and stock, customers and dues, bills,
          purchases and reports. It can also make bills, take customer payments, pay suppliers, add expenses,
          cancel or change bills, make quotations and cash memos, split a payment (cash + UPI), use discount cards
          and coupons, create offers, take returns, correct stock, add or change products, customers and suppliers, and enter a
          supplier&apos;s bill from a photo or PDF (new items are added and remembered for next time) — but it always
          shows you a preview first and
          saves only after you say yes, and it follows the same rules as the app (staff permissions, discount
          limits, GST). Everything it saves is marked as made by AI. It never sees your password, and you can
          disconnect it any time from ChatGPT or Claude.
        </p>
        <p>
          Gemini isn&apos;t supported yet: Google doesn&apos;t let people in India add their own connectors to Gemini.
        </p>
      </section>
    </LegalPage>
  );
}
