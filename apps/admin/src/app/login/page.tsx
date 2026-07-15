"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Button, Card, CardBody, Input, Label } from "@/components/ui";

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
    <main className="flex min-h-screen items-center justify-center bg-zinc-100 p-6">
      <Card className="w-full max-w-sm">
        <CardBody>
          <h1 className="text-xl font-bold text-zinc-900">SOFTRAXA Admin</h1>
          <p className="mb-6 text-sm text-zinc-500">Inventory software control panel</p>
          <form onSubmit={login} className="space-y-4">
            <div>
              <Label>Email</Label>
              <Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
            </div>
            <div>
              <Label>Password</Label>
              <Input type="password" value={password} onChange={(e) => setPassword(e.target.value)} required />
            </div>
            {error && <p className="text-sm text-red-600">{error}</p>}
            <Button type="submit" disabled={busy} className="w-full justify-center">
              {busy ? "Signing in…" : "Sign in"}
            </Button>
          </form>
        </CardBody>
      </Card>
    </main>
  );
}
