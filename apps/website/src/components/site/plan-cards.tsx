import Link from "next/link";
import { ArrowRight, Check } from "lucide-react";
import { rupees, whatsappLink, type SiteInfo } from "@/lib/site-info";
import { btnGhost, btnPrimary } from "@/lib/ui";

/**
 * The plans from the admin panel (public_site_info, migration 0096): the
 * website price, the list price crossed out, logins and add-on prices.
 * Without priced plans, one "ask for your price" card.
 */
export default function PlanCards({ info }: { info: SiteInfo }) {
  const wa = whatsappLink(info, "Hi, I want to know the price of Dukania for my shop.");
  const demoHref = wa || "/contact";

  if (info.plans.length === 0) {
    return (
      <div className="mt-8 max-w-md">
        <div className="rounded-2xl border border-marigold/40 bg-[#fff8e6] p-6 shadow-card">
          <h3 className="font-display text-2xl font-bold text-amber">
            {info.fromYearly ? <>From {rupees(info.fromYearly)} <span className="text-base font-semibold text-dim">/ year</span></> : "Yearly plans"}
          </h3>
          <ul className="mt-4 space-y-2 text-sm">
            {["Billing, GST, stock, reports", "Printing on every plan", "Android + Windows on one account", "Updates and WhatsApp support", "Pay by UPI, cash or bank"].map((p) => (
              <li key={p} className="flex items-start gap-2"><Check className="mt-0.5 h-4 w-4 shrink-0 text-amber" /> {p}</li>
            ))}
          </ul>
          <a href={demoHref} target={wa ? "_blank" : undefined} rel="noreferrer"
            className="stamp-press mt-6 inline-flex min-h-12 w-full items-center justify-center rounded-xl border-2 border-amber/60 bg-white text-sm font-semibold text-amber hover:bg-[#fff2cc]">
            Ask for your price
          </a>
        </div>
      </div>
    );
  }

  return (
    <ul className="mt-8 grid grid-cols-1 gap-5 md:grid-cols-3">
      {info.plans.map((p) => (
        <li key={p.name}
          className={`relative flex flex-col rounded-3xl bg-white p-6 shadow-card ${p.isRecommended ? "border-2 border-brand" : "border border-hairline"}`}>
          {p.isRecommended && (
            <span className="absolute -top-3 left-6 rounded-full bg-brand px-3 py-1 text-xs font-bold text-white">Most popular</span>
          )}
          <h3 className="font-display text-xl font-bold">{p.name}</h3>
          {p.description && <p className="mt-1 text-sm text-dim">{p.description}</p>}
          <div className="mt-5 flex items-end gap-2">
            <span className="font-display text-4xl font-bold text-brand">{rupees(p.websitePrice)}</span>
            <span className="pb-1 text-sm font-semibold text-dim">{p.billing === "lifetime" ? "one time" : "/ year"}</span>
          </div>
          {p.listPrice > p.websitePrice && (
            <p className="mt-1 text-sm">
              <span className="text-dim line-through">{rupees(p.listPrice)}</span>{" "}
              <span className="font-semibold text-emerald-700">Save {rupees(p.listPrice - p.websitePrice)}</span>
            </p>
          )}
          <ul className="mt-5 flex-1 space-y-2 text-sm">
            {p.highlights.map((h) => (
              <li key={h} className="flex items-start gap-2"><Check className="mt-0.5 h-4 w-4 shrink-0 text-brand-2" /> {h}</li>
            ))}
          </ul>
          <p className="mt-5 rounded-xl bg-elevated/60 px-3 py-2 text-xs text-dim">
            {p.users ? `${p.users} logins (owner + ${p.users - 1} staff)` : "Unlimited logins"}
            {p.extraStaffPrice > 0 ? ` · extra staff ${rupees(p.extraStaffPrice)} a year` : ""}
            {!p.includesAi && p.aiAddonPrice > 0 ? ` · AI assistant ${rupees(p.aiAddonPrice)} a year` : ""}
          </p>
          <div className="mt-5 grid grid-cols-1 gap-2">
            <Link href="/download" className={`${p.isRecommended ? btnPrimary : btnGhost} w-full justify-center`}>
              Start free trial <ArrowRight className="h-4 w-4" />
            </Link>
            <a href={demoHref} target={wa ? "_blank" : undefined} rel="noreferrer"
              className="py-1 text-center text-sm font-semibold text-brand hover:underline">
              Talk to us on WhatsApp
            </a>
          </div>
        </li>
      ))}
    </ul>
  );
}
