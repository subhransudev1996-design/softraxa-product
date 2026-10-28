"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Button, Card, CardBody, Table } from "@/components/ui";
import { Notice } from "@/components/ops";

/* eslint-disable @typescript-eslint/no-explicit-any */

type Field = "shop_name" | "contact_name" | "phone" | "city" | "business_type" | "source" | "temperature" | "campaign" | "notes";

// Column names people actually use, matched after lower-casing and dropping spaces and signs.
const ALIASES: Record<string, Field> = {
  shop: "shop_name", shopname: "shop_name", business: "shop_name", businessname: "shop_name", store: "shop_name", name: "shop_name",
  contact: "contact_name", contactname: "contact_name", contactperson: "contact_name", owner: "contact_name", ownername: "contact_name", person: "contact_name",
  phone: "phone", mobile: "phone", mobileno: "phone", phoneno: "phone", number: "phone", whatsapp: "phone", contactno: "phone",
  city: "city", area: "city", town: "city", location: "city",
  type: "business_type", businesstype: "business_type", shoptype: "business_type", category: "business_type",
  source: "source", from: "source",
  temperature: "temperature", temp: "temperature", hotwarmcold: "temperature",
  campaign: "campaign", ad: "campaign",
  notes: "notes", note: "notes", remarks: "notes", comment: "notes",
};

const TEMPLATE =
  "Shop name,Contact person,Phone,City,Business type,Source,Temperature,Campaign,Notes\n" +
  "Sharma General Store,Ramesh Sharma,9876543210,Bhubaneswar,grocery,field_visit,hot,Diwali visit,Wants GST billing\n";

/** Splits CSV text into rows (handles "quoted, fields" and "" inside quotes). */
function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = "";
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') { cell += '"'; i++; }
      else if (c === '"') quoted = false;
      else cell += c;
    } else if (c === '"') quoted = true;
    else if (c === ",") { row.push(cell); cell = ""; }
    else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(cell); rows.push(row); row = []; cell = "";
    } else cell += c;
  }
  if (cell || row.length) { row.push(cell); rows.push(row); }
  return rows.filter((r) => r.some((c) => c.trim()));
}

/**
 * Import leads from a spreadsheet saved as CSV (admin_import_leads, 0100).
 * Phone numbers already a lead or a client, or twice in the file, are skipped.
 */
export function LeadImport({ onDone }: { onDone: () => void }) {
  const [rows, setRows] = useState<Record<string, string>[] | null>(null);
  const [unknown, setUnknown] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [skipped, setSkipped] = useState<any[]>([]);

  async function read(file: File) {
    setNotice(null);
    setSkipped([]);
    if (!/\.csv$/i.test(file.name)) {
      setRows(null);
      return setNotice({ ok: false, text: "Choose a .csv file. In Excel: File → Save As → CSV (comma delimited)." });
    }
    const all = parseCsv((await file.text()).replace(/^﻿/, ""));
    if (all.length < 2) return setNotice({ ok: false, text: "The file has no rows under the header." });
    const header = all[0].map((h) => ALIASES[h.toLowerCase().replace(/[^a-z]/g, "")] ?? null);
    if (!header.includes("shop_name")) {
      return setNotice({ ok: false, text: 'No "Shop name" column found. Download the template to see the columns.' });
    }
    setUnknown(all[0].filter((_, i) => !header[i]));
    setRows(all.slice(1).map((r) => {
      const o: Record<string, string> = {};
      header.forEach((f, i) => { if (f && r[i]?.trim()) o[f] = r[i].trim(); });
      return o;
    }));
  }

  async function importRows() {
    if (!rows) return;
    setBusy(true);
    const { data, error } = await createClient().rpc("admin_import_leads", { p_rows: rows });
    setBusy(false);
    if (error) return setNotice({ ok: false, text: error.message });
    const d = data as { added: number; skipped: any[] };
    setNotice({ ok: true, text: `${d.added} lead${d.added === 1 ? "" : "s"} added${d.skipped.length ? `, ${d.skipped.length} skipped (below)` : ""}.` });
    setSkipped(d.skipped);
    setRows(null);
    onDone();
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardBody className="space-y-3">
          <h2 className="text-sm font-semibold text-zinc-700">Import leads from a spreadsheet</h2>
          <p className="text-sm text-zinc-600">
            Save your Excel sheet as CSV (File → Save As → CSV). Only <b>Shop name</b> is needed; the other columns
            are Contact person, Phone, City, Business type, Source, Temperature (hot / warm / cold), Campaign and Notes.
            A phone number that is already a lead or a client is skipped. Imported leads are yours.
          </p>
          <div className="flex flex-wrap items-center gap-3">
            <input
              type="file"
              accept=".csv,text/csv"
              onChange={(e) => e.target.files?.[0] && read(e.target.files[0])}
              className="text-sm file:mr-3 file:rounded-xl file:border-0 file:bg-brand file:px-4 file:py-2 file:text-sm file:font-semibold file:text-white"
            />
            <a
              href={`data:text/csv;charset=utf-8,${encodeURIComponent(TEMPLATE)}`}
              download="dukania-leads-template.csv"
              className="text-sm font-semibold text-brand hover:underline"
            >
              Download the template
            </a>
          </div>
          <Notice notice={notice} />
        </CardBody>
      </Card>

      {rows && (
        <Card>
          <CardBody className="space-y-3">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <p className="text-sm text-zinc-700">
                <b>{rows.length}</b> row{rows.length === 1 ? "" : "s"} ready. First {Math.min(rows.length, 5)} shown.
                {unknown.length > 0 && <span className="text-zinc-500"> Columns not used: {unknown.join(", ")}.</span>}
              </p>
              <Button onClick={importRows} disabled={busy || rows.length === 0}>{busy ? "Importing…" : `Import ${rows.length}`}</Button>
            </div>
            <Table headers={["Shop", "Contact", "Phone", "City", "Type", "Source", "Temp."]}>
              {rows.slice(0, 5).map((r, i) => (
                <tr key={i}>
                  <td className="px-4 py-2">{r.shop_name ?? <span className="text-red-600">missing</span>}</td>
                  <td className="px-4 py-2">{r.contact_name ?? "—"}</td>
                  <td className="px-4 py-2">{r.phone ?? "—"}</td>
                  <td className="px-4 py-2">{r.city ?? "—"}</td>
                  <td className="px-4 py-2">{r.business_type ?? "—"}</td>
                  <td className="px-4 py-2">{r.source ?? "import"}</td>
                  <td className="px-4 py-2">{r.temperature ?? "warm"}</td>
                </tr>
              ))}
            </Table>
          </CardBody>
        </Card>
      )}

      {skipped.length > 0 && (
        <Card>
          <CardBody>
            <h2 className="mb-3 text-sm font-semibold text-zinc-700">Skipped rows</h2>
            <Table headers={["Row", "Shop", "Why"]}>
              {skipped.map((s) => (
                <tr key={s.row}>
                  <td className="px-4 py-2 tabular-nums">{s.row + 1}</td>
                  <td className="px-4 py-2">{s.shop_name || "—"}</td>
                  <td className="px-4 py-2 text-zinc-600">{s.reason}</td>
                </tr>
              ))}
            </Table>
          </CardBody>
        </Card>
      )}
    </div>
  );
}
