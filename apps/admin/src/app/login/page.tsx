"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Button, Input, Label } from "@/components/ui";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function login(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) {
      setError(error.message);
      setBusy(false);
      return;
    }
    // only main-admin accounts may enter
    const { data: profile } = await supabase
      .from("profiles")
      .select("role")
      .eq("id", (await supabase.auth.getUser()).data.user!.id)
      .single();
    if (profile?.role !== "admin") {
      await supabase.auth.signOut();
      setError("This account is not an admin account.");
      setBusy(false);
      return;
    }
    router.push("/");
    router.refresh();
  }

  return (
    <main className="flex min-h-screen">
      {/* brand panel */}
      <section className="relative hidden flex-1 flex-col justify-between overflow-hidden bg-sidebar p-10 lg:flex">
        <div
          className="pointer-events-none absolute inset-0 opacity-60"
          style={{
            background:
              "radial-gradient(600px 400px at 20% 15%, rgba(124,58,237,0.32), transparent 65%), radial-gradient(500px 380px at 85% 90%, rgba(91,108,255,0.18), transparent 65%)",
          }}
        />
        <div className="relative flex items-center gap-3">
          <span className="grid h-10 w-10 place-items-center rounded-xl bg-gradient-to-br from-brand to-[#4c1d95] text-lg font-extrabold text-white shadow-[0_4px_14px_-4px_rgba(124,58,237,0.7)]">
            S
          </span>
          <p className="text-lg font-extrabold tracking-tight text-white">SOFTRAXA</p>
        </div>
        <div className="relative max-w-md">
          <h2 className="text-[34px] font-extrabold leading-tight tracking-tight text-white">
            Run your inventory software business from one panel.
          </h2>
          <p className="mt-4 text-sm leading-6 text-sidebar-muted">
            Clients, plans, subscriptions, leads, payments and support — the control
            room for SOFTRAXA Inventory.
          </p>
        </div>
        <p className="relative text-xs text-sidebar-muted">
          © {new Date().getFullYear()} SOFTRAXA
        </p>
      </section>

      {/* form panel */}
      <section className="flex flex-1 items-center justify-center bg-canvas p-6">
        <div className="animate-rise w-full max-w-sm">
          <div className="mb-8 lg:hidden">
            <span className="grid h-10 w-10 place-items-center rounded-xl bg-gradient-to-br from-brand to-[#4c1d95] text-lg font-extrabold text-white">
              S
            </span>
          </div>
          <h1 className="text-2xl font-extrabold tracking-tight text-ink">Welcome back</h1>
          <p className="mb-7 mt-1 text-sm text-zinc-500">Sign in to the admin panel</p>
          <form onSubmit={login} className="space-y-4">
            <div>
              <Label>Email</Label>
              <Input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@softraxa.com"
                required
              />
            </div>
            <div>
              <Label>Password</Label>
              <Input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                required
              />
            </div>
            {error && (
              <p className="rounded-xl bg-red-50 px-3.5 py-2.5 text-sm font-medium text-red-700">
                {error}
              </p>
            )}
            <Button type="submit" disabled={busy} className="w-full justify-center py-2.5">
              {busy ? "Signing in…" : "Sign in"}
            </Button>
          </form>
        </div>
      </section>
    </main>
  );
}
