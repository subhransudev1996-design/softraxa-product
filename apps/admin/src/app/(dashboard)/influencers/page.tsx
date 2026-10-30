"use client";

import { Suspense, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { PageHeader, Spinner } from "@/components/ui";
import { Pipeline } from "./pipeline";
import { Partners } from "./partners";
import { PostsAndFees } from "./posts-fees";

/* eslint-disable @typescript-eslint/no-explicit-any */

const TABS = [
  ["pipeline", "Pipeline"],
  ["partners", "Partners"],
  ["posts", "Posts and fees"],
] as const;

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
  const tab = params.get("tab") ?? "pipeline";
  return (
    <div className="space-y-6">
      <PageHeader title="Influencers" subtitle="Who you're talking to, who's posting, and what each one really brings." />
      <div className="flex flex-wrap gap-2">
        {TABS.map(([key, label]) => (
          <button
            key={key}
            onClick={() => router.replace(`/influencers?tab=${key}`)}
            aria-pressed={tab === key}
            className={`rounded-xl px-4 py-2 text-sm font-semibold transition ${tab === key ? "bg-brand text-white" : "bg-white text-zinc-600 ring-1 ring-inset ring-zinc-200 hover:bg-zinc-50"}`}
          >
            {label}
          </button>
        ))}
      </div>
      {tab === "pipeline" && <Pipeline />}
      {tab === "partners" && <Partners />}
      {tab === "posts" && <AllPostsAndFees />}
    </div>
  );
}

/** Influencers (migrations 0104, 0107, 0108, 0109). */
export default function InfluencersPage() {
  return (
    <Suspense fallback={<Spinner />}>
      <Influencers />
    </Suspense>
  );
}
