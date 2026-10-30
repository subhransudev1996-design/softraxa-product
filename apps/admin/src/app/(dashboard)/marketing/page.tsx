"use client";

import { useState } from "react";
import { PageHeader } from "@/components/ui";
import { ShopGroups } from "./shops";
import { Announcements } from "./announcements";
import { PromoCodes } from "./promos";
import { Referrals } from "./referrals";
import { Campaigns } from "./campaigns";

const TABS = [
  ["shops", "Shops & messages"],
  ["announcements", "Announcements"],
  ["promos", "Promo codes"],
  ["referrals", "Referrals"],
  ["campaigns", "Campaigns"],
] as const;

/** Marketing (migration 0101): reach groups of shops, offers, referrals and what campaigns brought. */
export default function MarketingPage() {
  const [tab, setTab] = useState<string>("shops");
  return (
    <div className="space-y-6">
      <PageHeader title="Marketing" subtitle="Reach your shops, run offers and see what your campaigns bring." />
      <div className="flex flex-wrap gap-2">
        {TABS.map(([key, label]) => (
          <button
            key={key}
            onClick={() => setTab(key)}
            aria-pressed={tab === key}
            className={`cursor-pointer rounded-md px-3 py-1.5 text-sm font-medium ring-1 ring-inset transition-colors ${tab === key ? "bg-brand-tint text-brand-deep ring-brand/30" : "bg-white text-zinc-600 ring-zinc-200 hover:bg-zinc-50"}`}
          >
            {label}
          </button>
        ))}
      </div>
      {tab === "shops" && <ShopGroups />}
      {tab === "announcements" && <Announcements />}
      {tab === "promos" && <PromoCodes />}
      {tab === "referrals" && <Referrals />}
      {tab === "campaigns" && <Campaigns />}
    </div>
  );
}
