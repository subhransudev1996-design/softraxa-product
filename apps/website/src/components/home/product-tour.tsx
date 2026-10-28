"use client";

import { useState } from "react";
import Image from "next/image";
import {
  ChevronLeft, ChevronRight, ReceiptText, FileText, Boxes, BarChart3, Wallet, Wrench,
  Monitor, Smartphone, House, ShoppingCart, Package, type LucideIcon,
} from "lucide-react";
import { desktopShots, mobileShots, type Shot } from "@/lib/shots";
import { PhoneFrame } from "@/components/device-frame";

type View = { label: string; icon: LucideIcon; shot: Shot; title: string; body: string };

const DESKTOP: View[] = [
  { label: "Billing", icon: ReceiptText, shot: desktopShots.newBill, title: "Fast and simple billing", body: "Search or scan, press F12, and the bill is done — with GST, discounts and the UPI QR worked out for you." },
  { label: "Invoices", icon: FileText, shot: desktopShots.invoices, title: "Every bill in one list", body: "Filter by paid, part-paid or credit, find any bill in seconds, and print or share it again." },
  { label: "Stock", icon: Boxes, shot: desktopShots.stock, title: "Stock that stays right", body: "Live counts for every product and size, with low and out-of-stock lists before they cost you a sale." },
  { label: "Reports", icon: BarChart3, shot: desktopShots.reports, title: "Know how the shop is doing", body: "Sales, profit, stock value and dues — on screen or exported for your accountant." },
  { label: "Expenses", icon: Wallet, shot: desktopShots.expenses, title: "Every rupee spent, noted", body: "Rent, salaries, electricity and tea — all the shop's expenses in one place, in the day's closing too." },
  { label: "Service catalog", icon: Wrench, shot: desktopShots.serviceCatalog, title: "Repairs and services", body: "Your price list for labour and services, ready to add to any bill or job card." },
];

const MOBILE: View[] = [
  { label: "Home", icon: House, shot: mobileShots.dashboard, title: "Your shop in your pocket", body: "Today's sales, dues and low stock the moment you open the app." },
  { label: "New bill", icon: ReceiptText, shot: mobileShots.newBill, title: "Bill from the phone", body: "Scan with the camera, tap to add, and bill at the counter or at the customer's door." },
  { label: "Checkout", icon: ShoppingCart, shot: mobileShots.checkout, title: "Cash, UPI, card or credit", body: "Choose how they paid — UPI shows a QR with the amount already filled in." },
  { label: "Products", icon: Package, shot: mobileShots.products, title: "Products and stock", body: "Prices, stock and variants for every item, with photos." },
  { label: "Reports", icon: BarChart3, shot: mobileShots.reports, title: "Reports anywhere", body: "Check sales and profit from home, even when you are not in the shop." },
  { label: "Job card", icon: Wrench, shot: mobileShots.jobCard, title: "Repair job cards", body: "Take in a device or vehicle, give an estimate and track it to delivery." },
];

export default function ProductTour() {
  const [mode, setMode] = useState<"desktop" | "mobile">("desktop");
  const [i, setI] = useState(0);
  const views = mode === "desktop" ? DESKTOP : MOBILE;
  const view = views[i];
  const go = (d: number) => setI((v) => (v + d + views.length) % views.length);

  return (
    <div>
      <div className="flex flex-wrap items-end justify-between gap-6">
        <div>
          <p className="text-xs font-bold uppercase tracking-[0.16em] text-brand-2">Product tour</p>
          <h2 className="mt-2 font-display text-3xl font-bold tracking-tight sm:text-4xl">See Dukania in action</h2>
          <p className="mt-2 text-dim">Explore the key screens on the PC and the phone.</p>
        </div>
        <div role="tablist" aria-label="Device" className="flex rounded-full border border-hairline bg-white p-1 shadow-card">
          {([["desktop", "Desktop", Monitor], ["mobile", "Mobile", Smartphone]] as const).map(([key, label, Icon]) => (
            <button
              key={key}
              role="tab"
              aria-selected={mode === key}
              onClick={() => { setMode(key); setI(0); }}
              className={`inline-flex min-h-11 items-center gap-2 rounded-full px-6 text-sm font-semibold transition-colors ${
                mode === key ? "bg-brand text-white" : "text-dim hover:text-paper"
              }`}
            >
              <Icon className="h-4 w-4" aria-hidden="true" /> {label}
            </button>
          ))}
        </div>
      </div>

      <div className="mt-10 grid grid-cols-1 items-center gap-8 lg:grid-cols-[220px_1fr_240px]">
        {/* screens list */}
        <ul className="flex gap-2 overflow-x-auto pb-1 lg:flex-col lg:overflow-visible lg:rounded-2xl lg:border lg:border-hairline lg:bg-white lg:p-3 lg:shadow-card">
          {views.map((v, n) => (
            <li key={v.label} className="shrink-0">
              <button
                type="button"
                onClick={() => setI(n)}
                className={`flex min-h-11 w-full items-center gap-3 rounded-xl px-3 text-sm font-medium transition-colors ${
                  n === i ? "bg-brand-soft text-brand" : "text-dim hover:bg-elevated hover:text-paper"
                }`}
              >
                <v.icon className="h-4 w-4" aria-hidden="true" /> {v.label}
              </button>
            </li>
          ))}
        </ul>

        {/* the screen */}
        <div className="relative flex items-center gap-2">
          <button type="button" onClick={() => go(-1)} aria-label="Previous screen"
            className="hidden h-10 w-10 shrink-0 items-center justify-center rounded-full text-dim hover:bg-white hover:text-paper sm:inline-flex">
            <ChevronLeft className="h-6 w-6" />
          </button>
          <div className="min-w-0 flex-1">
            {mode === "desktop" ? (
              <div className="shadow-float overflow-hidden rounded-2xl border-[6px] border-[#211a33] bg-white">
                <Image key={view.shot.src} src={view.shot.src} width={view.shot.width} height={view.shot.height}
                  alt={view.shot.alt} sizes="(max-width: 1024px) 100vw, 640px" className="h-auto w-full" />
              </div>
            ) : (
              <PhoneFrame className="mx-auto max-w-[250px]">
                <Image key={view.shot.src} src={view.shot.src} width={view.shot.width} height={view.shot.height}
                  alt={view.shot.alt} sizes="250px" className="h-auto w-full" />
              </PhoneFrame>
            )}
          </div>
          <button type="button" onClick={() => go(1)} aria-label="Next screen"
            className="hidden h-10 w-10 shrink-0 items-center justify-center rounded-full text-dim hover:bg-white hover:text-paper sm:inline-flex">
            <ChevronRight className="h-6 w-6" />
          </button>
        </div>

        {/* caption */}
        <div aria-live="polite">
          <h3 className="font-display text-2xl font-bold tracking-tight">{view.title}</h3>
          <p className="mt-3 text-dim">{view.body}</p>
          <div className="mt-6 flex gap-1.5">
            {views.map((v, n) => (
              <span key={v.label} className={`h-1.5 rounded-full transition-all ${n === i ? "w-6 bg-brand" : "w-1.5 bg-hairline"}`} />
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
