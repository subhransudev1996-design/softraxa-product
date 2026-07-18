"use client";

import {
  Store, Truck, Boxes, Gauge, Code2, Shield,
  Wifi, WifiOff, Cloud, Server, ArrowRight,
  CheckCircle2, Zap, Headphones, Layers
} from "lucide-react";
import Reveal from "@/components/reveal";
import SectionHeading from "@/components/section-heading";
import ContactForm from "@/components/contact-form";

/* ── capabilities ── */
const CAPABILITIES = [
  {
    icon: Store,
    title: "Custom POS & Billing",
    body: "Point-of-sale tuned to a specific trade — pharmacy, grocery, hardware, garments. GST-ready invoicing built in.",
    accent: "from-amber-500/15 to-amber-500/5",
    iconColor: "text-amber-500",
  },
  {
    icon: Truck,
    title: "Field-Sales & CRM",
    body: "Lead pipelines, visit logging, follow-ups and territory maps for teams that sell on the road.",
    accent: "from-sky-500/15 to-sky-500/5",
    iconColor: "text-sky-500",
  },
  {
    icon: Boxes,
    title: "Inventory Systems",
    body: "Multi-location stock, purchase orders, returns, batch tracking and expiry management.",
    accent: "from-violet-500/15 to-violet-500/5",
    iconColor: "text-violet-500",
  },
  {
    icon: Gauge,
    title: "Operations Dashboards",
    body: "One screen for the numbers that run the business — live data, alerts, and daily reports.",
    accent: "from-teal-500/15 to-teal-500/5",
    iconColor: "text-teal-500",
  },
];

/* ── what you get ── */
const INCLUDES = [
  { icon: Code2, text: "Source code ownership — you own everything we build" },
  { icon: Shield, text: "Security-first architecture with role-based access" },
  { icon: WifiOff, text: "Offline-first design — works without internet" },
  { icon: Cloud, text: "Cloud sync when connectivity is available" },
  { icon: Server, text: "Self-hosted or cloud deployment — your choice" },
  { icon: Headphones, text: "Dedicated support channel after launch" },
];

/* ── process ── */
const PROCESS = [
  {
    step: "01",
    title: "Discovery",
    body: "We map your real workflow and identify the gaps software can close.",
    color: "border-violet-500/30 bg-violet-500/5",
  },
  {
    step: "02",
    title: "Architecture",
    body: "We design the database, screens and integrations before writing code.",
    color: "border-sky-500/30 bg-sky-500/5",
  },
  {
    step: "03",
    title: "Build & Test",
    body: "Working software delivered in short sprints — you review every week.",
    color: "border-amber-500/30 bg-amber-500/5",
  },
  {
    step: "04",
    title: "Launch & Support",
    body: "We deploy, train your team and stay available for fixes and improvements.",
    color: "border-teal-500/30 bg-teal-500/5",
  },
];

export default function CustomSolutionsPageClient() {
  return (
    <>
      {/* ── Hero ── */}
      <section className="relative overflow-hidden py-20">
        <div className="mx-auto max-w-7xl px-6">
          <div className="grid items-center gap-12 lg:grid-cols-2">
            {/* Left — copy */}
            <Reveal>
              <p className="font-mono text-xs uppercase tracking-widest text-sky">
                Custom Solutions
              </p>
              <h1 className="mt-4 font-display text-4xl font-extrabold tracking-tight sm:text-5xl">
                Software shaped around
                <span className="bg-gradient-to-r from-violet to-sky bg-clip-text text-transparent"> your business.</span>
              </h1>
              <p className="mt-6 max-w-lg text-base text-dim leading-relaxed">
                Off-the-shelf tools force you to change how you work. We build software
                that fits your existing workflows — offline-first, GST-ready, and owned by you.
              </p>
              <div className="mt-8 flex flex-wrap items-center gap-4">
                <a
                  href="#inquiry-form"
                  className="stamp-press inline-flex min-h-11 items-center gap-2 rounded-lg bg-paper px-6 py-3 text-sm font-semibold text-bg hover:bg-paper/90 shadow-lg shadow-black/20"
                >
                  Start a project <ArrowRight className="h-4 w-4" />
                </a>
                <a
                  href="#how-it-works"
                  className="glass inline-flex min-h-11 items-center gap-2 rounded-lg px-6 py-3 text-sm font-semibold text-paper hover:bg-paper/5"
                >
                  See how it works
                </a>
              </div>
            </Reveal>

            {/* Right — visual illustration */}
            <Reveal delay={0.15}>
              <div className="glass relative rounded-3xl p-6 sm:p-8">
                {/* mini terminal header */}
                <div className="flex items-center gap-2 mb-5">
                  <span className="h-3 w-3 rounded-full bg-red-400/70" />
                  <span className="h-3 w-3 rounded-full bg-amber-400/70" />
                  <span className="h-3 w-3 rounded-full bg-teal-400/70" />
                  <span className="ml-2 text-xs text-dim font-mono">your-business.softraxa.app</span>
                </div>
                {/* mock dashboard cards */}
                <div className="grid grid-cols-3 gap-3">
                  <div className="rounded-xl border border-hairline bg-paper/4 p-4 text-center">
                    <p className="text-2xl font-bold text-amber-500">₹14L</p>
                    <p className="mt-1 text-[10px] text-dim">Today&apos;s Sales</p>
                  </div>
                  <div className="rounded-xl border border-hairline bg-paper/4 p-4 text-center">
                    <p className="text-2xl font-bold text-teal-400">847</p>
                    <p className="mt-1 text-[10px] text-dim">Active SKUs</p>
                  </div>
                  <div className="rounded-xl border border-hairline bg-paper/4 p-4 text-center">
                    <p className="text-2xl font-bold text-violet-400">23</p>
                    <p className="mt-1 text-[10px] text-dim">Low Stock</p>
                  </div>
                </div>
                {/* mock table rows */}
                <div className="mt-4 space-y-2">
                  {["Invoice #4821 — ₹2,340", "Purchase Order — 48 items", "GST Return — Q2 filed"].map((row, i) => (
                    <div key={i} className="flex items-center justify-between rounded-lg border border-hairline bg-paper/2 px-4 py-2.5 text-xs">
                      <span className="text-dim">{row}</span>
                      <CheckCircle2 className="h-3.5 w-3.5 text-teal-400" />
                    </div>
                  ))}
                </div>
                {/* status bar */}
                <div className="mt-4 flex items-center gap-2 rounded-lg bg-teal-500/10 px-3 py-2 text-xs text-teal-400">
                  <Wifi className="h-3.5 w-3.5" />
                  <span>Synced · Last update 2 seconds ago</span>
                </div>
              </div>
            </Reveal>
          </div>
        </div>
      </section>

      {/* ── What We Can Build ── */}
      <section className="mx-auto max-w-7xl px-6 py-20">
        <SectionHeading
          eyebrow="What we build"
          title="Four pillars of business software."
          lead="Each solution is custom-built for your trade, your team size and your daily workflow."
        />
        <div className="mt-14 grid gap-6 md:grid-cols-2">

          {/* ── 1. Custom POS & Billing ── */}
          <Reveal>
            <div className="group relative h-full overflow-hidden rounded-3xl border border-hairline bg-surface transition-all hover:border-amber-500/20 hover:shadow-xl hover:shadow-amber-500/5">
              <div className="p-8">
                <div className="inline-flex h-11 w-11 items-center justify-center rounded-xl bg-amber-500/10 text-amber-500">
                  <Store className="h-5 w-5" />
                </div>
                <h3 className="mt-5 font-display text-xl font-bold">Custom POS & Billing</h3>
                <p className="mt-2 text-sm text-dim leading-relaxed max-w-sm">
                  Point-of-sale tuned to your specific trade — pharmacy, grocery, hardware, garments. GST-ready invoicing built in.
                </p>
              </div>
              {/* Mini POS receipt illustration */}
              <div className="relative mx-8 mb-8 rounded-2xl border border-hairline bg-paper/3 p-5 overflow-hidden">
                <div className="flex items-center justify-between border-b border-dashed border-hairline pb-3 mb-3">
                  <span className="text-[10px] font-bold uppercase tracking-wider text-dim/60">Invoice #4821</span>
                  <span className="text-[10px] font-mono text-amber-500">₹ 2,340.00</span>
                </div>
                {[
                  ["Basmati Rice 5kg", "₹385", "x2"],
                  ["Toor Dal 1kg", "₹160", "x3"],
                  ["Refined Oil 1L", "₹175", "x1"],
                ].map(([item, price, qty]) => (
                  <div key={item} className="flex items-center justify-between py-1.5 text-[11px]">
                    <span className="text-dim">{item}</span>
                    <div className="flex items-center gap-3">
                      <span className="text-dim/50">{qty}</span>
                      <span className="font-medium text-paper/70 w-12 text-right">{price}</span>
                    </div>
                  </div>
                ))}
                <div className="mt-3 flex items-center justify-between border-t border-dashed border-hairline pt-3">
                  <span className="text-[10px] text-dim/50">GST @5%</span>
                  <span className="text-[11px] font-bold text-amber-500">Total ₹2,340</span>
                </div>
                {/* barcode */}
                <div className="mt-4 flex items-center justify-center gap-[2px]">
                  {[3,1,2,1,3,2,1,3,1,2,3,1,2,1,3,2,1,2,3,1].map((w, i) => (
                    <span key={i} className="bg-paper/20 rounded-sm" style={{ width: `${w}px`, height: "18px" }} />
                  ))}
                </div>
              </div>
            </div>
          </Reveal>

          {/* ── 2. Field-Sales & CRM ── */}
          <Reveal delay={0.08}>
            <div className="group relative h-full overflow-hidden rounded-3xl border border-hairline bg-surface transition-all hover:border-sky-500/20 hover:shadow-xl hover:shadow-sky-500/5">
              <div className="p-8">
                <div className="inline-flex h-11 w-11 items-center justify-center rounded-xl bg-sky-500/10 text-sky-500">
                  <Truck className="h-5 w-5" />
                </div>
                <h3 className="mt-5 font-display text-xl font-bold">Field-Sales & CRM</h3>
                <p className="mt-2 text-sm text-dim leading-relaxed max-w-sm">
                  Lead pipelines, visit logging, follow-ups and territory maps for teams that sell on the road.
                </p>
              </div>
              {/* Mini CRM pipeline illustration */}
              <div className="relative mx-8 mb-8 rounded-2xl border border-hairline bg-paper/3 p-5 overflow-hidden">
                <div className="flex items-center gap-2 mb-4">
                  <span className="text-[10px] font-bold uppercase tracking-wider text-dim/60">Pipeline</span>
                  <span className="ml-auto rounded-full bg-sky-500/15 px-2 py-0.5 text-[9px] font-bold text-sky-500">12 leads</span>
                </div>
                <div className="grid grid-cols-3 gap-2">
                  {[
                    { stage: "New", count: 5, color: "border-sky-500/30 bg-sky-500/5" },
                    { stage: "Meeting", count: 4, color: "border-amber-500/30 bg-amber-500/5" },
                    { stage: "Closed", count: 3, color: "border-teal-500/30 bg-teal-500/5" },
                  ].map((col) => (
                    <div key={col.stage} className="space-y-1.5">
                      <div className="flex items-center justify-between">
                        <span className="text-[9px] font-semibold text-dim/60 uppercase">{col.stage}</span>
                        <span className="text-[9px] text-dim/40">{col.count}</span>
                      </div>
                      {Array.from({ length: col.count }).map((_, j) => (
                        <div key={j} className={`rounded-lg border p-2 ${col.color}`}>
                          <div className="h-1.5 w-3/4 rounded bg-paper/10" />
                          <div className="mt-1 h-1 w-1/2 rounded bg-paper/5" />
                        </div>
                      ))}
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </Reveal>

          {/* ── 3. Inventory Systems ── */}
          <Reveal delay={0.16}>
            <div className="group relative h-full overflow-hidden rounded-3xl border border-hairline bg-surface transition-all hover:border-violet-500/20 hover:shadow-xl hover:shadow-violet-500/5">
              <div className="p-8">
                <div className="inline-flex h-11 w-11 items-center justify-center rounded-xl bg-violet-500/10 text-violet-500">
                  <Boxes className="h-5 w-5" />
                </div>
                <h3 className="mt-5 font-display text-xl font-bold">Inventory Systems</h3>
                <p className="mt-2 text-sm text-dim leading-relaxed max-w-sm">
                  Multi-location stock, purchase orders, returns, batch tracking and expiry management.
                </p>
              </div>
              {/* Mini warehouse shelf illustration */}
              <div className="relative mx-8 mb-8 rounded-2xl border border-hairline bg-paper/3 p-5 overflow-hidden">
                <div className="flex items-center gap-2 mb-4">
                  <span className="text-[10px] font-bold uppercase tracking-wider text-dim/60">Stock Levels</span>
                  <span className="ml-auto rounded-full bg-red-500/15 px-2 py-0.5 text-[9px] font-bold text-red-400">3 low</span>
                </div>
                <div className="space-y-2">
                  {[
                    { name: "Paracetamol 500mg", stock: 92, color: "bg-teal-400" },
                    { name: "Amoxicillin 250mg", stock: 15, color: "bg-amber-400" },
                    { name: "Cetrizine 10mg", stock: 8, color: "bg-red-400" },
                    { name: "Azithromycin 500mg", stock: 67, color: "bg-violet-400" },
                    { name: "ORS Sachets", stock: 45, color: "bg-sky-400" },
                  ].map((item) => (
                    <div key={item.name} className="flex items-center gap-3">
                      <span className="text-[10px] text-dim w-28 truncate">{item.name}</span>
                      <div className="flex-1 h-2 rounded-full bg-paper/5 overflow-hidden">
                        <div className={`h-full rounded-full ${item.color} transition-all`} style={{ width: `${item.stock}%` }} />
                      </div>
                      <span className={`text-[10px] font-mono w-6 text-right ${item.stock < 20 ? "text-red-400 font-bold" : "text-dim/50"}`}>{item.stock}</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </Reveal>

          {/* ── 4. Operations Dashboards ── */}
          <Reveal delay={0.24}>
            <div className="group relative h-full overflow-hidden rounded-3xl border border-hairline bg-surface transition-all hover:border-teal-500/20 hover:shadow-xl hover:shadow-teal-500/5">
              <div className="p-8">
                <div className="inline-flex h-11 w-11 items-center justify-center rounded-xl bg-teal-500/10 text-teal-500">
                  <Gauge className="h-5 w-5" />
                </div>
                <h3 className="mt-5 font-display text-xl font-bold">Operations Dashboards</h3>
                <p className="mt-2 text-sm text-dim leading-relaxed max-w-sm">
                  One screen for the numbers that run the business — live data, alerts, and daily reports.
                </p>
              </div>
              {/* Mini dashboard chart illustration */}
              <div className="relative mx-8 mb-8 rounded-2xl border border-hairline bg-paper/3 p-5 overflow-hidden">
                <div className="flex items-center gap-2 mb-4">
                  <span className="text-[10px] font-bold uppercase tracking-wider text-dim/60">Weekly Revenue</span>
                  <span className="ml-auto text-[10px] font-bold text-teal-400">↑ 12.4%</span>
                </div>
                {/* bar chart */}
                <div className="flex items-end gap-2 h-20">
                  {[
                    { day: "M", h: 45, color: "bg-teal-400/60" },
                    { day: "T", h: 62, color: "bg-teal-400/70" },
                    { day: "W", h: 38, color: "bg-teal-400/50" },
                    { day: "T", h: 75, color: "bg-teal-400/80" },
                    { day: "F", h: 90, color: "bg-teal-400" },
                    { day: "S", h: 100, color: "bg-gradient-to-t from-teal-500 to-sky-400" },
                    { day: "S", h: 55, color: "bg-teal-400/60" },
                  ].map((bar, i) => (
                    <div key={i} className="flex items-gradient flex-1 flex-col items-center gap-1">
                      <div className={`w-full rounded-t-md ${bar.color} transition-all`} style={{ height: `${bar.h}%` }} />
                      <span className="text-[8px] text-dim/40">{bar.day}</span>
                    </div>
                  ))}
                </div>
                {/* KPI row */}
                <div className="mt-4 grid grid-cols-3 gap-2">
                  {[
                    ["₹8.2L", "Revenue"],
                    ["324", "Orders"],
                    ["₹2,531", "Avg. Order"],
                  ].map(([val, label]) => (
                    <div key={label} className="rounded-lg bg-paper/3 px-2 py-1.5 text-center">
                      <p className="text-[11px] font-bold text-paper/70">{val}</p>
                      <p className="text-[8px] text-dim/40">{label}</p>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </Reveal>

        </div>
      </section>

      {/* ── What's Included ── */}
      <section className="mx-auto max-w-7xl px-6 py-16">
        <div className="glass rounded-3xl p-8 sm:p-12">
          <SectionHeading eyebrow="What you get" title="Every project ships with these built in." />
          <div className="mt-10 grid gap-x-8 gap-y-5 sm:grid-cols-2 lg:grid-cols-3">
            {INCLUDES.map((item) => (
              <Reveal key={item.text}>
                <div className="flex items-start gap-3">
                  <div className="mt-0.5 inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-paper/5">
                    <item.icon className="h-4 w-4 text-sky" />
                  </div>
                  <p className="text-sm text-dim leading-relaxed">{item.text}</p>
                </div>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      {/* ── How It Works ── */}
      <section id="how-it-works" className="mx-auto max-w-7xl px-6 py-20">
        <SectionHeading
          eyebrow="How it works"
          title="From idea to live software in weeks."
          align="center"
        />
        <div className="relative mt-14">
          {/* connecting line */}
          <div className="absolute left-1/2 top-0 hidden h-full w-px -translate-x-1/2 bg-hairline lg:block" aria-hidden="true" />
          <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
            {PROCESS.map((p, i) => (
              <Reveal key={p.step} delay={i * 0.1}>
                <div className={`relative h-full rounded-2xl border p-6 ${p.color}`}>
                  <span className="font-mono text-xs font-bold text-dim/50">{p.step}</span>
                  <h3 className="mt-3 font-display text-lg font-semibold">{p.title}</h3>
                  <p className="mt-2 text-sm text-dim leading-relaxed">{p.body}</p>
                </div>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      {/* ── Why Us stats bar ── */}
      <section className="mx-auto max-w-7xl px-6 pb-16">
        <Reveal>
          <div className="grid grid-cols-2 gap-8 rounded-2xl border border-hairline bg-paper/4 px-8 py-10 text-center sm:grid-cols-4">
            {[
              ["5+", "Years building business software"],
              ["100%", "Code ownership — you keep everything"],
              ["< 4 wks", "Average time to first working build"],
              ["24/7", "Offline-first — works without internet"],
            ].map(([n, l]) => (
              <div key={n}>
                <p className="font-display text-3xl font-extrabold bg-gradient-to-r from-violet to-sky bg-clip-text text-transparent">{n}</p>
                <p className="mt-1 text-xs text-dim">{l}</p>
              </div>
            ))}
          </div>
        </Reveal>
      </section>

      {/* ── Inquiry Form ── */}
      <section id="inquiry-form" className="mx-auto max-w-7xl px-6 py-20">
        <div className="grid gap-12 lg:grid-cols-[1.2fr_0.8fr]">
          <Reveal>
            <div className="mb-6">
              <p className="font-mono text-xs uppercase tracking-widest text-sky">Start a project</p>
              <h2 className="mt-3 font-display text-3xl font-bold tracking-tight">
                Tell us what you need built.
              </h2>
              <p className="mt-3 text-sm text-dim leading-relaxed max-w-lg">
                Describe your business and the problem you&apos;re solving. We&apos;ll get back within
                one business day with an honest assessment — no sales pitch.
              </p>
            </div>
            <ContactForm />
          </Reveal>

          <Reveal delay={0.1}>
            <div className="space-y-6 lg:mt-14">
              {/* why work with us cards */}
              {[
                { icon: Zap, title: "Fast turnaround", body: "Working software in weeks, not months. You review every sprint." },
                { icon: Layers, title: "Built on proven foundations", body: "We use the same stack that powers Dukania — battle-tested in production." },
                { icon: Headphones, title: "Direct developer access", body: "Talk to the engineers building your software. No project managers in between." },
              ].map((card) => (
                <div key={card.title} className="glass rounded-2xl p-5">
                  <div className="flex items-start gap-4">
                    <div className="inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-paper/4 ring-1 ring-paper/10">
                      <card.icon className="h-5 w-5 text-sky" />
                    </div>
                    <div>
                      <p className="font-semibold text-paper text-sm">{card.title}</p>
                      <p className="mt-1 text-xs text-dim leading-relaxed">{card.body}</p>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </Reveal>
        </div>
      </section>
    </>
  );
}
