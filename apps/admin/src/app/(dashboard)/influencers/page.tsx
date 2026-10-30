"use client";

import { Suspense, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { PageHeader, Spinner } from "@/components/ui";
import { Pipeline } from "./pipeline";
import { Partners } from "./partners";
import { PostsAndFees } from "./posts-fees";
import { Payouts } from "./payouts";
import { useCan } from "@/components/me";

/* eslint-disable @typescript-eslint/no-explicit-any */

function AllPostsAndFees() {
  const [partners, setPartners] = useState<any[] | null>(null);
  useEffect(() => {
    createClient().from("partners").select("id, name, code").order("name").then(({ data }) => setPartners(data ?? []));
  }, []);
  return partners ? <PostsAndFees partners={partners} /> : <Spinner />;
}

function Influencers() {
  const router = useRouter();
  const params = useSearchParams();
  const canMarket = useCan("marketing");
  const canPay = useCan("payments");
  // The pipeline is marketing's, payouts are payments' (they hold the PAN).
  const tabs: [string, string][] = [
    ...(canMarket ? [["pipeline", "Pipeline"] as [string, string]] : []),
    ["partners", "Partners"],
    ["posts", "Posts and fees"],
    ...(canPay ? [["payouts", "Payouts"] as [string, string]] : []),
  ];
  const asked = params.get("tab");
  const tab = tabs.some(([key]) => key === asked) ? asked : canMarket && !asked ? "pipeline" : canPay && !asked ? "payouts" : "partners";
  return (
    <div className="space-y-6">
      <PageHeader title="Influencers" subtitle="Who you're talking to, who's posting, and what each one really brings." />
      <div className="flex flex-wrap gap-2">
        {tabs.map(([key, label]) => (
          <button
            key={key}
            onClick={() => router.replace(`/influencers?tab=${key}`)}
            aria-pressed={tab === key}
            className={`cursor-pointer rounded-lg px-3 py-1.5 text-sm font-medium ring-1 ring-inset transition-colors ${tab === key ? "bg-brand-tint text-brand-deep ring-brand/30" : "bg-white text-zinc-600 ring-zinc-200 hover:bg-zinc-50"}`}
          >
            {label}
          </button>
        ))}
      </div>
      {tab === "pipeline" && <Pipeline />}
      {tab === "partners" && <Partners />}
      {tab === "posts" && <AllPostsAndFees />}
      {tab === "payouts" && <Payouts />}
    </div>
  );
}

/** Influencers (migrations 0104, 0107, 0108, 0109, 0110). */
export default function InfluencersPage() {
  return (
    <Suspense fallback={<Spinner />}>
      <Influencers />
    </Suspense>
  );
}
