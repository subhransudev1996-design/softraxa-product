"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, CardBody, PageHeader, Spinner, StatCard, Table } from "@/components/ui";
import { dateTimeStr } from "@/lib/format";

// Nightly reconciliation (migration 0050): stored stock and balances
// recomputed from their ledgers. The pilot ends only with zero
// unexplained mismatches (LAUNCH_SPECIFICATION, pilot exit criteria).

const CHECKS: Record<string, string> = {
  stock_product: "Product stock ≠ stock ledger",
  stock_variant: "Variant stock ≠ stock ledger",
  customer_due: "Customer due ≠ open bills",
  customer_advance: "Customer advance ≠ advance ledger",
  supplier_due: "Supplier due ≠ purchases",
  pieces_exceed: "Cut pieces exceed stock",
  invoice_amounts: "Bill paid/credit out of range",
};

/* eslint-disable @typescript-eslint/no-explicit-any */
export default function ReconciliationPage() {
  const supabase = createClient();
  const [runs, setRuns] = useState<any[] | null>(null);
  const [runId, setRunId] = useState<string | null>(null);
  const [issues, setIssues] = useState<any[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  // Bumped after a run or an explanation to reload both lists.
  const [refresh, setRefresh] = useState(0);

  useEffect(() => {
    supabase
      .from("reconciliation_runs")
      .select("*")
      .order("started_at", { ascending: false })
      .limit(20)
      .then(({ data }) => {
        setRuns(data ?? []);
        setRunId((current) => current ?? data?.[0]?.id ?? null);
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [refresh]);

  useEffect(() => {
    if (!runId) return;
    supabase
      .from("reconciliation_issues")
      .select("*, businesses(name)")
      .eq("run_id", runId)
      .order("explained_note", { ascending: true })
      .order("created_at", { ascending: true })
      .then(({ data }) => setIssues(data ?? []));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [runId, refresh]);

  async function runNow() {
    setBusy(true);
    setError("");
    const { data, error } = await supabase.rpc("run_reconciliation");
    setBusy(false);
    if (error) {
      setError(error.message);
      return;
    }
    setRunId((data as any)?.run_id ?? null);
    setRefresh((n) => n + 1);
  }

  async function explain(issue: any) {
    const note = window.prompt(
      `What explains this mismatch?\n${issue.businesses?.name ?? ""} — ${issue.entity_label}`,
      issue.explained_note || "",
    );
    if (!note?.trim()) return;
    const { error } = await supabase.rpc("explain_reconciliation_issue", {
      p_issue: issue.id,
      p_note: note.trim(),
    });
    if (error) {
      setError(error.message);
      return;
    }
    setRefresh((n) => n + 1);
  }

  const current = runs?.find((r) => r.id === runId);

  return (
    <div className="space-y-6">
      <PageHeader
        title="Reconciliation"
        subtitle="Stock and balances checked against their ledgers every night at 02:00 IST"
        actions={
          <Button onClick={runNow} disabled={busy}>
            {busy ? "Running…" : "Run now"}
          </Button>
        }
      />
      {error && <p className="text-sm text-red-600">{error}</p>}

      {!runs ? (
        <Spinner />
      ) : runs.length === 0 ? (
        <Card>
          <CardBody>
            <p className="text-sm text-zinc-500">
              No runs yet. Press “Run now”, or enable pg_cron so it runs nightly.
            </p>
          </CardBody>
        </Card>
      ) : (
        <>
          {current && (
            <div className="grid gap-4 sm:grid-cols-3">
              <StatCard label="Shops checked" value={current.businesses} hint={dateTimeStr(current.started_at)} />
              <StatCard label="Mismatches" value={current.issues} />
              <StatCard
                label="Unexplained"
                value={current.unexplained}
                hint={current.unexplained === 0 ? "Pilot criterion met" : "Must be 0 to end the pilot"}
              />
            </div>
          )}

          <div className="flex flex-wrap gap-2">
            {runs.map((r) => (
              <button
                key={r.id}
                onClick={() => setRunId(r.id)}
                className={`rounded-full px-3 py-1 text-xs font-semibold ring-1 ring-inset ${
                  r.id === runId ? "bg-brand text-white ring-brand" : "bg-white text-zinc-600 ring-zinc-200"
                }`}
              >
                {dateTimeStr(r.started_at)} · {r.unexplained}/{r.issues}
              </button>
            ))}
          </div>

          {!issues ? (
            <Spinner />
          ) : (
            <Card>
              <Table headers={["Client", "Check", "Record", "Expected", "Stored", "Explanation", ""]}>
                {issues.map((i) => (
                  <tr key={i.id} className="hover:bg-zinc-50">
                    <td className="px-4 py-3">{i.businesses?.name ?? "—"}</td>
                    <td className="px-4 py-3">
                      <Badge color={i.explained_note ? "zinc" : "red"}>{CHECKS[i.check_name] ?? i.check_name}</Badge>
                    </td>
                    <td className="px-4 py-3">
                      {i.entity_label}
                      {i.detail && <p className="text-xs text-zinc-500">{i.detail}</p>}
                    </td>
                    <td className="px-4 py-3 tabular-nums">{i.expected}</td>
                    <td className="px-4 py-3 tabular-nums">{i.actual}</td>
                    <td className="max-w-xs px-4 py-3 text-xs text-zinc-500">{i.explained_note || "—"}</td>
                    <td className="px-4 py-3">
                      <button onClick={() => explain(i)} className="text-sm font-medium text-brand hover:underline">
                        {i.explained_note ? "Edit" : "Explain"}
                      </button>
                    </td>
                  </tr>
                ))}
                {issues.length === 0 && (
                  <tr>
                    <td colSpan={7} className="px-4 py-10 text-center text-zinc-500">
                      No mismatches — every shop&apos;s stock and balances match their ledgers.
                    </td>
                  </tr>
                )}
              </Table>
            </Card>
          )}
        </>
      )}
    </div>
  );
}
