import type { Metadata } from "next";
import Link from "next/link";
import { ArrowRight, Check, Hand, MessageCircle, ShieldCheck, Sparkles } from "lucide-react";
import Reveal from "@/components/reveal";
import PageHero from "@/components/page-hero";
import ClosingCta from "@/components/site/closing-cta";
import { getPageSeo, buildPageMetadata } from "@/lib/cms";
import { getSiteInfo, whatsappLink } from "@/lib/site-info";
import { btnGhost, btnPrimary, eyebrow } from "@/lib/ui";

// Dukania AI: the shop connector for ChatGPT and Claude (supabase/functions/
// shop-mcp, migration 0086). The same steps are in the app: More → ChatGPT & Claude.
export async function generateMetadata(): Promise<Metadata> {
  return buildPageMetadata(await getPageSeo("/ai"));
}

const CONNECTOR_URL = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/shop-mcp`;

const ASKS: [string, string][] = [
  ["How is my shop doing today?", "Today's sales, profit and bills."],
  ["Who owes me money?", "Customers with dues, biggest first."],
  ["What is running low?", "Low stock, ready to reorder."],
  ["Bill Ramesh 2 Parle-G, paid by UPI.", "A bill made from your words."],
  ["Enter this purchase.", "With a photo or PDF of the supplier's bill."],
  ["Add Maggi 70g at ₹14, GST 12%.", "A new product in seconds."],
];

const CAN_DO = [
  "Make bills, quotations and cash memos",
  "Enter supplier bills from a photo or PDF",
  "Take customer payments and pay suppliers",
  "Add expenses and correct stock",
  "Take returns, use discount cards and coupons",
  "Add or change products, customers and suppliers",
];

export default async function AiPage() {
  const info = await getSiteInfo();
  const wa = whatsappLink(info, "Hi, I want to add the Dukania AI assistant to my shop.");

  return (
    <>
      <PageHero
        eyebrow="Dukania AI"
        title={"Run your shop\nfrom ChatGPT or Claude."}
        lead="Connect your Dukania shop once, then just ask — in English, Hindi or your own language. Nothing is saved until you say yes."
        actions={
          <>
            <a href="#setup" className={btnPrimary}>Set it up <ArrowRight className="h-4 w-4" /></a>
            <a href={wa || "/contact"} target={wa ? "_blank" : undefined} rel="noreferrer" className={btnGhost}>
              <MessageCircle className="h-4 w-4" /> Add AI to my plan
            </a>
          </>
        }
        aside={
          <div className="mx-auto max-w-md rounded-3xl border border-hairline bg-white p-5 shadow-card">
            <p className="flex items-center gap-2 text-sm font-semibold">
              <span className="inline-flex h-7 w-7 items-center justify-center rounded-full bg-brand text-white"><Sparkles className="h-4 w-4" /></span>
              Dukania AI
            </p>
            <p className="ml-auto mt-4 w-fit rounded-2xl rounded-br-sm bg-brand-soft px-3 py-2 text-sm font-medium text-brand">
              Enter this purchase 📄
            </p>
            <div className="mt-3 rounded-2xl rounded-bl-sm bg-elevated/70 p-3 text-sm">
              <p className="text-dim">From the bill of <b className="text-paper">Gupta Traders</b>:</p>
              {[["Wheat atta 5 kg × 10", "₹2,450"], ["Sunflower oil 1 L × 12", "₹1,860"], ["Toor dal 1 kg × 8", "₹1,120"]].map(([n, v]) => (
                <p key={n} className="mt-2 flex justify-between gap-3 font-medium text-paper">{n} <span>{v}</span></p>
              ))}
              <p className="mt-3 border-t border-hairline pt-2 text-xs text-dim">Total ₹5,430 with GST. Save this purchase?</p>
            </div>
            <p className="ml-auto mt-3 w-fit rounded-2xl rounded-br-sm bg-brand px-3 py-2 text-sm font-semibold text-white">Yes</p>
            <p className="mt-3 flex items-center gap-1.5 text-xs font-semibold text-emerald-700"><Check className="h-3.5 w-3.5" /> Saved — stock updated</p>
          </div>
        }
      />

      <section className="mx-auto max-w-7xl px-6 py-14">
        <p className={eyebrow}>Just ask</p>
        <h2 className="mt-2 font-display text-3xl font-bold tracking-tight">Things shop owners ask every day.</h2>
        <ul className="mt-8 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {ASKS.map(([q, a], i) => (
            <Reveal key={q} delay={(i % 3) * 0.05}>
              <li className="h-full rounded-2xl border border-hairline bg-white p-5 shadow-card">
                <p className="w-fit rounded-2xl rounded-br-sm bg-brand-soft px-3 py-2 text-sm font-semibold text-brand">“{q}”</p>
                <p className="mt-3 text-sm text-dim">{a}</p>
              </li>
            </Reveal>
          ))}
        </ul>
      </section>

      <section className="bg-brand-soft/50 py-14">
        <div className="mx-auto grid max-w-7xl grid-cols-1 gap-8 px-6 lg:grid-cols-2">
          <Reveal>
            <p className={eyebrow}>What it can do</p>
            <h2 className="mt-2 font-display text-3xl font-bold tracking-tight">Real work inside your shop.</h2>
            <ul className="mt-6 space-y-3 text-sm">
              {CAN_DO.map((b) => (
                <li key={b} className="flex items-center gap-2.5">
                  <span className="inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-brand text-white"><Check className="h-3 w-3" /></span>
                  {b}
                </li>
              ))}
            </ul>
          </Reveal>
          <Reveal delay={0.1}>
            <div className="grid grid-cols-1 gap-4">
              {[
                { icon: Hand, title: "You say yes first", body: "It always shows a preview and saves only after you agree. Everything it saves is marked as made by AI." },
                { icon: ShieldCheck, title: "Same rules as the app", body: "It sees only what you can see, follows staff permissions, discount limits and GST, and never sees your password." },
                { icon: Sparkles, title: "In your plan", body: "Included in the Standard + AI plan, or an add-on for other plans. Staff use it only if the owner allows." },
              ].map((c) => (
                <div key={c.title} className="flex gap-4 rounded-2xl border border-hairline bg-white p-5 shadow-card">
                  <span className="inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-brand-soft text-brand"><c.icon className="h-5 w-5" /></span>
                  <span>
                    <span className="block font-bold text-paper">{c.title}</span>
                    <span className="mt-1 block text-sm text-dim">{c.body}</span>
                  </span>
                </div>
              ))}
            </div>
          </Reveal>
        </div>
      </section>

      {/* setup — the same steps as in the app (More → ChatGPT & Claude) */}
      <section id="setup" className="mx-auto max-w-4xl scroll-mt-24 px-6 py-14">
        <p className={eyebrow}>Set it up</p>
        <h2 className="mt-2 font-display text-3xl font-bold tracking-tight">Connect in two minutes.</h2>
        <p className="mt-3 text-dim">
          In the Dukania app open <b className="text-paper">More → ChatGPT &amp; Claude</b> and press <b className="text-paper">Copy link</b>. It is the same for every shop:
        </p>
        <p className="mt-3 break-all rounded-xl border border-hairline bg-white px-4 py-3 font-mono text-sm text-paper shadow-card">{CONNECTOR_URL}</p>

        <div className="mt-8 grid grid-cols-1 gap-5 md:grid-cols-2">
          <div className="rounded-2xl border border-hairline bg-white p-5 shadow-card">
            <h3 className="font-display text-lg font-bold">Add it to ChatGPT</h3>
            <ol className="mt-3 list-decimal space-y-1.5 pl-5 text-sm text-dim">
              <li>In ChatGPT (chatgpt.com), open <b className="text-paper">Plugins</b> and press <b className="text-paper">Add</b>.</li>
              <li>Paste the link as the <b className="text-paper">Server URL</b>, choose <b className="text-paper">OAuth</b>, tick <b className="text-paper">I understand</b>, then press <b className="text-paper">Create</b>.</li>
              <li>Sign in with your Dukania email and password, then press <b className="text-paper">Allow</b>.</li>
            </ol>
          </div>
          <div className="rounded-2xl border border-hairline bg-white p-5 shadow-card">
            <h3 className="font-display text-lg font-bold">Add it to Claude</h3>
            <ol className="mt-3 list-decimal space-y-1.5 pl-5 text-sm text-dim">
              <li>In Claude (claude.ai), open <b className="text-paper">Settings → Connectors</b> and press <b className="text-paper">Add custom connector</b>.</li>
              <li>Name it Dukania, paste the link, then press <b className="text-paper">Add</b>.</li>
              <li>Press <b className="text-paper">Connect</b>, sign in with your Dukania email and password, then press <b className="text-paper">Allow</b>.</li>
            </ol>
          </div>
        </div>

        <div className="mt-6 rounded-2xl bg-[#fff8e6] p-5 text-sm text-dim">
          <p><b className="text-paper">Before you start:</b> the AI assistant must be in your shop&apos;s plan — if it isn&apos;t,{" "}
            <Link href="/contact" className="font-semibold text-brand underline">contact us</Link> to add it. Some ChatGPT and Claude plans don&apos;t allow connectors.</p>
          <p className="mt-2">Gemini isn&apos;t supported yet: Google doesn&apos;t let people in India add their own connectors to Gemini. You can disconnect Dukania any time from ChatGPT or Claude.</p>
        </div>
      </section>

      <ClosingCta info={info} title="Let Dukania AI do the busywork." waText="Hi, I want to add the Dukania AI assistant to my shop." />
    </>
  );
}
