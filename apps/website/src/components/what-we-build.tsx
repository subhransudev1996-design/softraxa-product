"use client";

import { useState, useEffect } from "react";
import Link from "next/link";
import {
  Layers, WifiOff, Store, BarChart3, Database, Server, Monitor,
  Smartphone, Check, RefreshCw, ArrowUpRight, TrendingUp, IndianRupee
} from "lucide-react";
import Reveal from "./reveal";

export default function WhatWeBuild() {
  // Simulating live database syncing status
  const [syncedCount, setSyncedCount] = useState(537);
  const [syncStatus, setSyncStatus] = useState("Idle");

  useEffect(() => {
    const timer = setInterval(() => {
      setSyncStatus("Syncing...");
      setTimeout(() => {
        setSyncedCount(c => c + 1);
        setSyncStatus("Idle");
      }, 1000);
    }, 5000);
    return () => clearInterval(timer);
  }, []);

  return (
    <div className="grid gap-6 md:grid-cols-2">
      {/* 1. Product Engineering */}
      <Reveal>
        <Link href="/services" className="group block h-full">
          <div className="glass h-full flex flex-col justify-between overflow-hidden rounded-3xl p-8 transition-all hover:border-paper/20 hover:shadow-xl hover:shadow-violet/5">
            <div>
              <div className="inline-flex h-11 w-11 items-center justify-center rounded-xl bg-gradient-to-br from-violet/25 to-sky/20 ring-1 ring-paper/10">
                <Layers className="h-5 w-5 text-violet" />
              </div>
              <h3 className="mt-5 flex items-center gap-2 font-display text-xl font-bold tracking-tight text-paper">
                Product engineering
                <ArrowUpRight className="h-4 w-4 text-dim transition-transform group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />
              </h3>
              <p className="mt-2.5 max-w-sm text-sm leading-relaxed text-dim">
                The whole product — mobile app, backend APIs, and admin dashboards — designed and built together as one unified system.
              </p>
            </div>

            {/* Visual: Connected Node system */}
            <div className="relative mt-8 flex h-40 items-center justify-center rounded-2xl border border-hairline bg-paper/4 px-4 overflow-hidden">
              <div className="absolute inset-0 bg-grid-pattern opacity-10" />
              
              <div className="relative flex items-center justify-between w-full max-w-xs z-10">
                {/* Node 1: Client App */}
                <div className="flex flex-col items-center gap-1">
                  <div className="flex h-12 w-12 items-center justify-center rounded-xl border border-hairline bg-surface shadow-md">
                    <Monitor className="h-5 w-5 text-sky" />
                  </div>
                  <span className="font-mono text-[9px] text-dim uppercase">Frontend</span>
                </div>

                {/* Connection line 1 */}
                <div className="relative flex-1 h-0.5 bg-hairline mx-3">
                  <div className="absolute top-1/2 left-0 -translate-y-1/2 h-1.5 w-1.5 rounded-full bg-violet animate-ping" style={{ animationDelay: '0s' }} />
                  <div className="absolute top-1/2 left-1/2 -translate-y-1/2 h-1.5 w-1.5 rounded-full bg-sky animate-ping" style={{ animationDelay: '1s' }} />
                </div>

                {/* Node 2: Server API */}
                <div className="flex flex-col items-center gap-1">
                  <div className="flex h-14 w-14 items-center justify-center rounded-xl bg-gradient-to-br from-violet to-sky text-white shadow-lg shadow-violet/20">
                    <Server className="h-6 w-6" />
                  </div>
                  <span className="font-mono text-[9px] text-paper font-semibold uppercase">API Gateway</span>
                </div>

                {/* Connection line 2 */}
                <div className="relative flex-1 h-0.5 bg-hairline mx-3">
                  <div className="absolute top-1/2 right-0 -translate-y-1/2 h-1.5 w-1.5 rounded-full bg-teal animate-ping" style={{ animationDelay: '0.5s' }} />
                  <div className="absolute top-1/2 right-1/2 -translate-y-1/2 h-1.5 w-1.5 rounded-full bg-sky animate-ping" style={{ animationDelay: '1.5s' }} />
                </div>

                {/* Node 3: Database */}
                <div className="flex flex-col items-center gap-1">
                  <div className="flex h-12 w-12 items-center justify-center rounded-xl border border-hairline bg-surface shadow-md">
                    <Database className="h-5 w-5 text-teal" />
                  </div>
                  <span className="font-mono text-[9px] text-dim uppercase">Postgres</span>
                </div>
              </div>
            </div>
          </div>
        </Link>
      </Reveal>

      {/* 2. Offline-First Mobile */}
      <Reveal delay={0.08}>
        <Link href="/services" className="group block h-full">
          <div className="glass h-full flex flex-col justify-between overflow-hidden rounded-3xl p-8 transition-all hover:border-paper/20 hover:shadow-xl hover:shadow-teal/5">
            <div>
              <div className="inline-flex h-11 w-11 items-center justify-center rounded-xl bg-gradient-to-br from-teal/25 to-sky/20 ring-1 ring-paper/10">
                <WifiOff className="h-5 w-5 text-teal" />
              </div>
              <h3 className="mt-5 flex items-center gap-2 font-display text-xl font-bold tracking-tight text-paper">
                Offline-first mobile
                <ArrowUpRight className="h-4 w-4 text-dim transition-transform group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />
              </h3>
              <p className="mt-2.5 max-w-sm text-sm leading-relaxed text-dim">
                Apps that keep working with no signal and sync database tables automatically the moment a connection is restored.
              </p>
            </div>

            {/* Visual: Mobile Offline frame */}
            <div className="relative mt-8 flex h-40 items-end justify-center rounded-2xl border border-hairline bg-paper/4 overflow-hidden pt-4">
              <div className="relative w-44 rounded-t-xl border-t border-x border-hairline bg-surface p-2 shadow-2xl flex flex-col gap-1.5 h-full">
                {/* Phone Header */}
                <div className="flex justify-between items-center px-1 text-[8px] text-dim font-mono">
                  <span className="flex items-center gap-0.5"><WifiOff className="h-2 w-2 text-amber" /> Offline</span>
                  <div className="flex items-center gap-1">
                    <span className="h-1.5 w-3 rounded-sm bg-paper/20" />
                    <span>8:00 AM</span>
                  </div>
                </div>

                {/* Queue status */}
                <div className="flex items-center justify-between rounded-lg bg-amber/10 border border-amber/20 px-2 py-1 text-[10px]">
                  <span className="font-semibold text-amber flex items-center gap-1">
                    <span className="h-1 w-1 rounded-full bg-amber animate-pulse" /> 1 pending sync
                  </span>
                  <span className="font-mono text-[8px] text-dim">{syncStatus}</span>
                </div>

                {/* Item List */}
                <div className="space-y-1.5">
                  <div className="flex justify-between items-center rounded border border-hairline p-1.5 bg-paper/2">
                    <div>
                      <p className="text-[10px] font-semibold text-paper leading-none">Invoice #0482</p>
                      <p className="text-[7px] text-dim mt-0.5">3 items · Local storage</p>
                    </div>
                    <span className="text-[9px] font-mono font-bold text-paper">₹2,450</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </Link>
      </Reveal>

      {/* 3. Business Software */}
      <Reveal delay={0.12}>
        <Link href="/services" className="group block h-full">
          <div className="glass h-full flex flex-col justify-between overflow-hidden rounded-3xl p-8 transition-all hover:border-paper/20 hover:shadow-xl hover:shadow-amber/5">
            <div>
              <div className="inline-flex h-11 w-11 items-center justify-center rounded-xl bg-gradient-to-br from-amber/25 to-violet/20 ring-1 ring-paper/10">
                <Store className="h-5 w-5 text-amber" />
              </div>
              <h3 className="mt-5 flex items-center gap-2 font-display text-xl font-bold tracking-tight text-paper">
                Business software
                <ArrowUpRight className="h-4 w-4 text-dim transition-transform group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />
              </h3>
              <p className="mt-2.5 max-w-sm text-sm leading-relaxed text-dim">
                POS, inventory counters, billing screens, and barcode registers designed for the speed of a busy real-world checkout counter.
              </p>
            </div>

            {/* Visual: Checkout Memo Receipt */}
            <div className="relative mt-8 flex h-40 items-center justify-center rounded-2xl border border-hairline bg-paper/4 overflow-hidden px-4">
              <div className="w-56 rounded-xl border border-hairline bg-surface p-3.5 shadow-lg relative transform rotate-1">
                <div className="flex justify-between items-start border-b border-dashed border-hairline pb-2">
                  <div>
                    <h4 className="text-xs font-bold text-paper">Dukania POS</h4>
                    <p className="text-[8px] text-dim">Pune Main Outlet</p>
                  </div>
                  <span className="rounded bg-teal/20 px-2 py-0.5 text-[8px] font-bold text-teal uppercase tracking-wider">PAID</span>
                </div>
                
                <div className="mt-2.5 space-y-1 text-[10px]">
                  <div className="flex justify-between text-dim">
                    <span>Neo 10 R Router</span>
                    <span className="font-mono text-paper">₹30,000</span>
                  </div>
                  <div className="flex justify-between text-dim">
                    <span>GST (18%)</span>
                    <span className="font-mono text-paper">₹5,400</span>
                  </div>
                </div>

                <div className="mt-2 border-t border-dashed border-hairline pt-2 flex justify-between items-center text-xs font-bold">
                  <span className="text-paper">Total</span>
                  <span className="font-mono text-teal">₹35,400</span>
                </div>
              </div>
            </div>
          </div>
        </Link>
      </Reveal>

      {/* 4. Data & Reporting */}
      <Reveal delay={0.16}>
        <Link href="/services" className="group block h-full">
          <div className="glass h-full flex flex-col justify-between overflow-hidden rounded-3xl p-8 transition-all hover:border-paper/20 hover:shadow-xl hover:shadow-sky/5">
            <div>
              <div className="inline-flex h-11 w-11 items-center justify-center rounded-xl bg-gradient-to-br from-sky/25 to-violet/20 ring-1 ring-paper/10">
                <BarChart3 className="h-5 w-5 text-sky" />
              </div>
              <h3 className="mt-5 flex items-center gap-2 font-display text-xl font-bold tracking-tight text-paper">
                Data &amp; reporting
                <ArrowUpRight className="h-4 w-4 text-dim transition-transform group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />
              </h3>
              <p className="mt-2.5 max-w-sm text-sm leading-relaxed text-dim">
                Real-time stock values, expiry windows, expense metrics, and tax summaries packed into charts that owners actually read.
              </p>
            </div>

            {/* Visual: Chart & Metrics */}
            <div className="relative mt-8 flex h-40 items-center justify-center rounded-2xl border border-hairline bg-paper/4 overflow-hidden px-4">
              <div className="flex gap-3.5 w-full max-w-xs">
                {/* Card A: Goal Progress */}
                <div className="flex-1 rounded-xl border border-hairline bg-surface p-3 shadow-md flex flex-col justify-between h-28">
                  <p className="text-[9px] uppercase tracking-wider text-dim">Daily Sales</p>
                  <div>
                    <span className="inline-flex items-center gap-0.5 text-xs font-bold text-teal">
                      <TrendingUp className="h-3 w-3" /> +14%
                    </span>
                    <p className="font-display text-lg font-bold text-paper mt-0.5">₹48,290</p>
                  </div>
                  <div className="h-1 w-full bg-paper/10 rounded-full overflow-hidden">
                    <div className="h-full bg-sky rounded-full" style={{ width: '74%' }} />
                  </div>
                </div>

                {/* Card B: Bar Chart Illustration */}
                <div className="flex-1 rounded-xl border border-hairline bg-surface p-3 shadow-md flex flex-col justify-between h-28">
                  <p className="text-[9px] uppercase tracking-wider text-dim">Stock Value</p>
                  <div className="flex items-end gap-1.5 h-12" aria-hidden="true">
                    {[30, 48, 65, 40, 80, 55].map((h, i) => (
                      <div
                        key={i}
                        className={`flex-1 rounded-sm bg-gradient-to-t ${
                          i === 4 ? "from-violet to-sky" : "from-paper/10 to-paper/20"
                        }`}
                        style={{ height: `${h}%` }}
                      />
                    ))}
                  </div>
                  <p className="font-mono text-xs font-bold text-paper text-right">₹2.8L</p>
                </div>
              </div>
            </div>
          </div>
        </Link>
      </Reveal>
    </div>
  );
}
