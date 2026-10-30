"use client";

import { useState } from "react";
import { Button, Card, CardBody, Input, Label, Select } from "@/components/ui";
import { waLink } from "@/components/ops";
import { inr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */

/** The website price: the list price less the website discount (0096). */
export const webPrice = (list: number, pct: number) => Math.round(list * (1 - pct / 100));
export const hasAi = (p: any) => Array.isArray(p?.included_features) && p.included_features.includes("ai_assistant");

/**
 * A quote from the plan prices (Plans page). Shows the list, website and —
 * for whoever may see it — the lowest price. With [phone], a WhatsApp
 * button sends it; [onSent] is told the text and the quoted amount.
 */
export function QuoteCalculator({
  plans,
  discount,
  showLowest = true,
  phone,
  greeting = "",
  initialPlanId,
  onSent,
}: {
  plans: any[];
  discount: number;
  showLowest?: boolean;
  phone?: string;
  greeting?: string;
  initialPlanId?: string | null;
  onSent?: (text: string, amount: number) => void;
}) {
  const [planId, setPlanId] = useState(
    plans.some((p) => p.id === initialPlanId) ? (initialPlanId as string) : plans[0]?.id ?? ""
  );
  const [staff, setStaff] = useState("0");
  const [ai, setAi] = useState(false);
  const [copied, setCopied] = useState(false);
  const plan = plans.find((p) => p.id === planId);
  if (!plan) return null;
  const n = Math.max(0, Math.floor(Number(staff) || 0));
  const aiOk = !hasAi(plan) && Number(plan.ai_addon_price) > 0;
  const addons = n * Number(plan.extra_staff_price) + (ai && aiOk ? Number(plan.ai_addon_price) : 0);
  const list = Number(plan.list_price) + addons;
  const web = webPrice(Number(plan.list_price), discount) + addons;
  const lowest = Number(plan.lowest_price) + addons;
  const per = plan.billing === "lifetime" ? "one time" : "for one year";
  const text =
    greeting +
    `Dukania ${plan.name}: ${inr(web)} ${per} (list ${inr(list)}). ` +
    `${plan.user_limit ? `${Number(plan.user_limit) + n} logins (owner + ${Number(plan.user_limit) - 1 + n} staff)` : "Unlimited logins"}` +
    `${hasAi(plan) || (ai && aiOk) ? ", AI assistant included" : ""}. ` +
    `${n > 0 || (ai && aiOk) ? `Add-ons renew every year. ` : ""}Start with a free trial — no card needed.`;

  async function copy() {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      window.prompt("Copy this quote:", text);
    }
  }

  return (
    <Card>
      <CardBody>
        <h2 className="mb-3 text-sm font-semibold text-zinc-700">{phone ? "Send a quote" : "Quick quote"}</h2>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <div>
            <Label>Plan</Label>
            <Select value={planId} onChange={(e) => { setPlanId(e.target.value); setAi(false); }}>
              {plans.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </Select>
          </div>
          <div>
            <Label>Extra staff logins</Label>
            <Input type="number" min={0} max={50} value={staff} onChange={(e) => setStaff(e.target.value)} />
          </div>
          {aiOk && (
            <label className="mt-6 flex items-center gap-2 text-sm">
              <input type="checkbox" checked={ai} onChange={(e) => setAi(e.target.checked)} /> AI add-on ({inr(plan.ai_addon_price)}/year)
            </label>
          )}
        </div>
        <div className={`mt-4 grid ${showLowest ? "grid-cols-3" : "grid-cols-2"} gap-2 rounded-lg bg-zinc-50 p-3 text-center text-sm`}>
          <div><span className="block text-xs text-zinc-500">List</span><b className="tabular-nums">{inr(list)}</b></div>
          <div><span className="block text-xs text-zinc-500">Website ({discount}% off)</span><b className="tabular-nums text-brand">{inr(web)}</b></div>
          {showLowest && (
            <div><span className="block text-xs text-zinc-500">Your lowest</span><b className="tabular-nums text-amber-700">{inr(lowest)}</b></div>
          )}
        </div>
        <p className="mt-3 rounded-lg border border-zinc-200 px-4 py-3 text-sm text-zinc-700">{text}</p>
        <div className="mt-3 flex flex-wrap justify-end gap-2">
          <Button variant="outline" onClick={copy}>{copied ? "Copied" : "Copy quote"}</Button>
          {phone && (
            <a href={waLink(phone, text)} target="_blank" rel="noreferrer" onClick={() => onSent?.(text, web)}>
              <Button>WhatsApp quote</Button>
            </a>
          )}
        </div>
      </CardBody>
    </Card>
  );
}
