"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Button, Card, CardBody, Input, Label, Select } from "@/components/ui";

export default function NewClientPage() {
  const router = useRouter();
  const [plans, setPlans] = useState<{ id: string; name: string }[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [leadId, setLeadId] = useState<string | null>(null);
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
    expiryDate: "",
  });

  useEffect(() => {
    createClient()
      .from("plans")
      .select("id, name")
      .eq("is_active", true)
      .order("name")
      .then(({ data }) => setPlans(data ?? []));

    // Prefill when arriving from a lead's "Convert to client" button.
    // (window.location instead of useSearchParams — avoids the Suspense
    // boundary Next.js requires around useSearchParams in client pages.)
    const q = new URLSearchParams(window.location.search);
    if (q.get("leadId")) {
      setLeadId(q.get("leadId"));
      setForm((f) => ({
        ...f,
        businessName: q.get("businessName") ?? f.businessName,
        ownerName: q.get("ownerName") ?? f.ownerName,
        phone: q.get("phone") ?? f.phone,
        type: q.get("type") || f.type,
        planId: q.get("planId") ?? f.planId,
      }));
    }
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
        expiryDate: form.expiryDate || null,
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
            <div className="grid grid-cols-2 gap-4">
              <div>
                <Label>Plan (blank = 14-day trial)</Label>
                <Select value={form.planId} onChange={(e) => set("planId", e.target.value)}>
                  <option value="">Trial</option>
                  {plans.map((p) => (
                    <option key={p.id} value={p.id}>{p.name}</option>
                  ))}
                </Select>
              </div>
              <div>
                <Label>Expiry date</Label>
                <Input type="date" value={form.expiryDate} onChange={(e) => set("expiryDate", e.target.value)} />
              </div>
            </div>
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
