"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Button, Card, CardBody, Input, Label, Select } from "@/components/ui";

export default function NewClientPage() {
  const router = useRouter();
  type Plan = { id: string; name: string; monthly_price: number; yearly_price: number };
  type Product = { id: string; name: string; status: string; trial_days: number };
  const [plans, setPlans] = useState<Plan[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [leadId, setLeadId] = useState<string | null>(null);
  // True only after the first client render. The subscription/expiry UI depends
  // on fetched data and `new Date()`, which differ between the server pass and
  // the client — gating on this keeps SSR HTML identical to first client HTML
  // and avoids a hydration mismatch.
  const [mounted, setMounted] = useState(false);
  // "monthly" | "yearly" — billing cycle for a paid plan.
  const [billingCycle, setBillingCycle] = useState<"monthly" | "yearly">("monthly");
  // When true, the admin overrides the auto-computed expiry with a manual date.
  const [overrideExpiry, setOverrideExpiry] = useState(false);
  const [form, setForm] = useState({
    email: "",
    password: "",
    ownerName: "",
    businessName: "",
    type: "mobile",
    phone: "",
    address: "",
    gstNumber: "",
    invoicePrefix: "INV",
    taxPreference: "gst",
    planId: "",
    productId: "",
    expiryDate: "",
  });

  const selectedPlan = plans.find((p) => p.id === form.planId) || null;
  const selectedProduct = products.find((p) => p.id === form.productId) || null;
  // Which billing cycles this plan is actually priced for (> 0).
  const availableCycles = selectedPlan
    ? ([
        selectedPlan.monthly_price > 0 ? "monthly" : null,
        selectedPlan.yearly_price > 0 ? "yearly" : null,
      ].filter(Boolean) as ("monthly" | "yearly")[])
    : [];

  // Auto-computed expiry (yyyy-mm-dd). Paid plan → today + cycle; trial → today
  // + product trial_days (default 14).
  function computedExpiry(): string {
    const d = new Date();
    if (selectedPlan && availableCycles.length) {
      const cycle = availableCycles.includes(billingCycle) ? billingCycle : availableCycles[0];
      if (cycle === "yearly") d.setFullYear(d.getFullYear() + 1);
      else d.setMonth(d.getMonth() + 1);
    } else {
      d.setDate(d.getDate() + (selectedProduct?.trial_days ?? 14));
    }
    return d.toISOString().slice(0, 10);
  }
  const effectiveExpiry = overrideExpiry && form.expiryDate ? form.expiryDate : computedExpiry();

  useEffect(() => {
    // Deferred so the state update doesn't run synchronously in the effect
    // body (react-hooks/set-state-in-effect).
    Promise.resolve().then(() => setMounted(true));
    const supabase = createClient();
    supabase
      .from("plans")
      .select("id, name, monthly_price, yearly_price")
      .eq("is_active", true)
      .order("name")
      .then(({ data }) => setPlans((data as Plan[]) ?? []));

    // Softraxa software products. Default the picker to the first live one
    // (Dukania today) so the common case needs no extra click.
    // (software_products, NOT products — `products` is shop inventory items.)
    supabase
      .from("software_products")
      .select("id, name, status, trial_days")
      .eq("is_active", true)
      .order("sort_order")
      .then(({ data }) => {
        const list = (data as Product[]) ?? [];
        setProducts(list);
        const live = list.find((p) => p.status === "live") ?? list[0];
        if (live) setForm((f) => (f.productId ? f : { ...f, productId: live.id }));
      });

    // Prefill when arriving from a lead's "Convert to client" button.
    // (window.location instead of useSearchParams — avoids the Suspense
    // boundary Next.js requires around useSearchParams in client pages.)
    // Deferred out of the synchronous effect body so these state updates
    // don't run during the effect (react-hooks/set-state-in-effect).
    let active = true;
    const q = new URLSearchParams(window.location.search);
    if (q.get("leadId")) {
      Promise.resolve().then(() => {
        if (!active) return;
        setLeadId(q.get("leadId"));
        setForm((f) => ({
          ...f,
          businessName: q.get("businessName") ?? f.businessName,
          ownerName: q.get("ownerName") ?? f.ownerName,
          phone: q.get("phone") ?? f.phone,
          type: q.get("type") || f.type,
          planId: q.get("planId") ?? f.planId,
        }));
      });
    }
    return () => { active = false; };
  }, []);

  const set = (k: string, v: string) => setForm((f) => ({ ...f, [k]: v }));

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const res = await fetch("/api/clients", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        email: form.email,
        password: form.password,
        ownerName: form.ownerName,
        planId: form.planId || null,
        productId: form.productId || null,
        expiryDate: effectiveExpiry,
        billingCycle: selectedPlan && availableCycles.length ? billingCycle : null,
        business: {
          name: form.businessName,
          type: form.type,
          phone: form.phone,
          address: form.address,
          gstNumber: form.gstNumber,
          invoicePrefix: form.invoicePrefix,
          taxPreference: form.taxPreference,
        },
      }),
    });
    const json = await res.json();
    if (!res.ok) {
      setError(json.error ?? "Failed");
      setBusy(false);
      return;
    }
    // Came from a lead → mark it converted and link it to the new client.
    if (leadId) {
      const supabase = createClient();
      await supabase.from("leads").update({
        status: "converted",
        converted_business_id: json.businessId,
        converted_at: new Date().toISOString(),
      }).eq("id", leadId);
      const { data: { user } } = await supabase.auth.getUser();
      await supabase.from("lead_activities").insert({
        lead_id: leadId,
        activity_type: "status_change",
        note: `Converted to client "${form.businessName}"`,
        created_by: user?.id ?? null,
      });
    }
    router.push(`/clients/${json.businessId}`);
  }

  return (
    <div className="max-w-2xl space-y-6">
      <h1 className="text-2xl font-bold text-zinc-900">Create client account</h1>
      {leadId && (
        <p className="rounded-lg bg-blue-50 px-4 py-2 text-sm text-blue-800">
          Converting a lead — the lead will be marked as converted automatically after this account is created.
        </p>
      )}
      <Card>
        <CardBody>
          <form onSubmit={submit} className="space-y-4">
            <h2 className="text-sm font-semibold text-zinc-700">Login credentials</h2>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <Label>Email *</Label>
                <Input type="email" required value={form.email} onChange={(e) => set("email", e.target.value)} />
              </div>
              <div>
                <Label>Password *</Label>
                <Input type="text" required minLength={6} value={form.password} onChange={(e) => set("password", e.target.value)} />
              </div>
            </div>
            <h2 className="pt-2 text-sm font-semibold text-zinc-700">Business details</h2>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <Label>Business name *</Label>
                <Input required value={form.businessName} onChange={(e) => set("businessName", e.target.value)} />
              </div>
              <div>
                <Label>Owner name</Label>
                <Input value={form.ownerName} onChange={(e) => set("ownerName", e.target.value)} />
              </div>
              <div>
                <Label>Business type</Label>
                <Select value={form.type} onChange={(e) => set("type", e.target.value)}>
                  <option value="mobile">Mobile shop</option>
                  <option value="garment">Garment shop</option>
                  <option value="hardware">Hardware shop</option>
                  <option value="other">Other</option>
                </Select>
              </div>
              <div>
                <Label>Phone</Label>
                <Input value={form.phone} onChange={(e) => set("phone", e.target.value)} />
              </div>
              <div className="col-span-2">
                <Label>Address</Label>
                <Input value={form.address} onChange={(e) => set("address", e.target.value)} />
              </div>
              <div>
                <Label>GSTIN</Label>
                <Input value={form.gstNumber} onChange={(e) => set("gstNumber", e.target.value)} />
              </div>
              <div>
                <Label>Invoice prefix</Label>
                <Input value={form.invoicePrefix} onChange={(e) => set("invoicePrefix", e.target.value)} />
              </div>
              <div>
                <Label>Tax preference</Label>
                <Select value={form.taxPreference} onChange={(e) => set("taxPreference", e.target.value)}>
                  <option value="gst">GST</option>
                  <option value="non_gst">Non-GST</option>
                </Select>
              </div>
            </div>
            <h2 className="pt-2 text-sm font-semibold text-zinc-700">Subscription</h2>
            {!mounted ? (
              <p className="text-sm text-zinc-400">Loading plans…</p>
            ) : (
            <div className="grid grid-cols-2 gap-4">
              <div className="col-span-2">
                <Label>Software</Label>
                <Select value={form.productId} onChange={(e) => set("productId", e.target.value)}>
                  {products.length === 0 && <option value="">—</option>}
                  {products.map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.name}{p.status !== "live" ? " (coming soon)" : ""}
                    </option>
                  ))}
                </Select>
              </div>
              <div>
                <Label>Plan (blank = trial)</Label>
                <Select
                  value={form.planId}
                  onChange={(e) => {
                    const id = e.target.value;
                    set("planId", id);
                    // Reset cycle to the first one this plan is priced for.
                    const p = plans.find((x) => x.id === id);
                    if (p) setBillingCycle(p.monthly_price > 0 ? "monthly" : "yearly");
                    setOverrideExpiry(false);
                  }}
                >
                  <option value="">Trial</option>
                  {plans.map((p) => (
                    <option key={p.id} value={p.id}>{p.name}</option>
                  ))}
                </Select>
              </div>

              {/* Billing cycle — only for a paid plan, only cycles it's priced for */}
              {selectedPlan && availableCycles.length > 0 && (
                <div>
                  <Label>Billing cycle</Label>
                  <Select
                    value={availableCycles.includes(billingCycle) ? billingCycle : availableCycles[0]}
                    onChange={(e) => setBillingCycle(e.target.value as "monthly" | "yearly")}
                  >
                    {availableCycles.includes("monthly") && (
                      <option value="monthly">Monthly — ₹{selectedPlan.monthly_price}</option>
                    )}
                    {availableCycles.includes("yearly") && (
                      <option value="yearly">Yearly — ₹{selectedPlan.yearly_price}</option>
                    )}
                  </Select>
                </div>
              )}

              {/* Expiry — auto-computed, read-only, with an override toggle */}
              <div className="col-span-2">
                <div className="flex items-center justify-between">
                  <Label>
                    {selectedPlan && availableCycles.length ? "Expiry (auto from cycle)" : "Trial expiry (auto)"}
                  </Label>
                  <label className="flex items-center gap-1.5 text-xs text-zinc-500">
                    <input
                      type="checkbox"
                      checked={overrideExpiry}
                      onChange={(e) => {
                        setOverrideExpiry(e.target.checked);
                        if (e.target.checked && !form.expiryDate) set("expiryDate", computedExpiry());
                      }}
                    />
                    Set a custom date
                  </label>
                </div>
                {overrideExpiry ? (
                  <Input type="date" value={form.expiryDate} onChange={(e) => set("expiryDate", e.target.value)} />
                ) : (
                  <Input type="date" value={effectiveExpiry} readOnly className="bg-zinc-50 text-zinc-500" />
                )}
              </div>
            </div>
            )}
            {error && <p className="text-sm text-red-600">{error}</p>}
            <Button type="submit" disabled={busy}>
              {busy ? "Creating…" : "Create client"}
            </Button>
          </form>
        </CardBody>
      </Card>
    </div>
  );
}
