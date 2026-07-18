"use client";

import { useState } from "react";
import {
  FileSearch, Code2, Rocket, MessageSquareDot, Check,
  Workflow, GitBranch, ArrowRight, Sparkles, Terminal
} from "lucide-react";
import Reveal from "./reveal";

const STEPS = [
  {
    n: "01",
    title: "Discover",
    body: "We map the real workflow of your business before writing a line of code.",
    accent: "group-hover:border-violet/30 hover:shadow-violet/5",
    badge: "bg-violet/10 text-violet border-violet/20",
    icon: FileSearch,
    visual: () => (
      <div className="relative w-full h-24 flex items-center justify-center bg-paper/4 rounded-xl border border-hairline overflow-hidden">
        <div className="absolute inset-0 bg-grid-pattern opacity-10" />
        <div className="relative flex items-center gap-3 z-10">
          <div className="flex h-10 w-10 items-center justify-center rounded-lg border border-hairline bg-surface shadow-sm">
            <Workflow className="h-5 w-5 text-violet" />
          </div>
          <ArrowRight className="h-4 w-4 text-dim" />
          <div className="flex h-10 w-10 items-center justify-center rounded-lg border border-hairline bg-surface shadow-sm">
            <GitBranch className="h-5 w-5 text-sky" />
          </div>
        </div>
      </div>
    )
  },
  {
    n: "02",
    title: "Build",
    body: "Working software shipped in weeks, with you testing early versions all the way.",
    accent: "group-hover:border-sky/30 hover:shadow-sky/5",
    badge: "bg-sky/10 text-sky border-sky/20",
    icon: Code2,
    visual: () => (
      <div className="relative w-full h-24 flex flex-col justify-between p-3 bg-paper/4 rounded-xl border border-hairline overflow-hidden font-mono text-[9px] text-dim">
        <div className="flex items-center gap-1.5 border-b border-hairline pb-1.5 mb-1.5">
          <Terminal className="h-3 w-3 text-sky" />
          <span className="text-[8px] uppercase tracking-wider">dukania-build.sh</span>
        </div>
        <div className="space-y-1">
          <p className="text-teal font-semibold">✓ Local tests passed (12/12)</p>
          <div className="flex items-center gap-2">
            <span>Syncing Supabase...</span>
            <span className="h-1.5 w-16 bg-paper/10 rounded-full overflow-hidden">
              <span className="block h-full bg-sky rounded-full animate-pulse" style={{ width: '80%' }} />
            </span>
          </div>
        </div>
      </div>
    )
  },
  {
    n: "03",
    title: "Launch",
    body: "Onboarding, data migration and staff training — live software on day one.",
    accent: "group-hover:border-teal/30 hover:shadow-teal/5",
    badge: "bg-teal/10 text-teal border-teal/20",
    icon: Rocket,
    visual: () => (
      <div className="relative w-full h-24 flex flex-col justify-center p-3 bg-paper/4 rounded-xl border border-hairline overflow-hidden text-[10px]">
        <div className="space-y-1.5">
          {[
            "Staff profiles configured",
            "Inventory CSV imported",
            "App live on counter"
          ].map((item, idx) => (
            <div key={item} className="flex items-center gap-2 text-paper">
              <span className="inline-flex h-4 w-4 shrink-0 items-center justify-center rounded-full bg-teal/20 text-teal">
                <Check className="h-2.5 w-2.5" />
              </span>
              <span>{item}</span>
            </div>
          ))}
        </div>
      </div>
    )
  },
  {
    n: "04",
    title: "Support",
    body: "A direct line to the developers who wrote the code. Issues get fixed immediately.",
    accent: "group-hover:border-amber/30 hover:shadow-amber/5",
    badge: "bg-amber/10 text-amber border-amber/20",
    icon: MessageSquareDot,
    visual: () => (
      <div className="relative w-full h-24 flex items-center justify-center bg-paper/4 rounded-xl border border-hairline overflow-hidden p-3">
        <div className="w-full space-y-2">
          <div className="flex justify-end">
            <span className="rounded-lg bg-sky/15 text-sky px-2.5 py-1 text-[9px] leading-tight">Low-stock counts aren&apos;t loading...</span>
          </div>
          <div className="flex justify-start items-center gap-1.5">
            <span className="h-4 w-4 rounded-full bg-gradient-to-br from-amber to-violet text-white text-[8px] flex items-center justify-center font-bold">SX</span>
            <span className="rounded-lg bg-surface text-paper border border-hairline px-2.5 py-1 text-[9px] leading-tight font-semibold flex items-center gap-1">
              <Sparkles className="h-2.5 w-2.5 text-amber" /> Fixed. Refreshing database now!
            </span>
          </div>
        </div>
      </div>
    )
  }
];

export default function ProcessSteps() {
  return (
    <div className="relative mt-12 grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
      {/* connecting horizontal line on desktop view */}
      <div className="pointer-events-none absolute left-0 right-0 top-1/2 -translate-y-12 hidden h-px bg-gradient-to-r from-violet/30 via-sky/30 to-teal/30 lg:block opacity-50" />
      
      {STEPS.map((step, i) => (
        <Reveal key={step.n} delay={i * 0.08}>
          <div className={`glass group relative h-full flex flex-col justify-between overflow-hidden rounded-3xl p-6 transition-all hover:border-paper/20 hover:shadow-lg ${step.accent}`}>
            <div>
              {/* Step header */}
              <div className="flex items-center justify-between">
                <span className={`inline-flex h-9 w-9 items-center justify-center rounded-xl border font-mono text-sm font-bold ${step.badge}`}>
                  {step.n}
                </span>
                <step.icon className="h-5 w-5 text-dim transition-colors group-hover:text-paper" />
              </div>

              {/* Title & Body */}
              <h3 className="mt-5 font-display text-lg font-bold tracking-tight text-paper transition-colors group-hover:text-paper">
                {step.title}
              </h3>
              <p className="mt-2 text-sm leading-relaxed text-dim">
                {step.body}
              </p>
            </div>

            {/* Visual Graphic representation */}
            <div className="mt-6">
              <step.visual />
            </div>
          </div>
        </Reveal>
      ))}
    </div>
  );
}
