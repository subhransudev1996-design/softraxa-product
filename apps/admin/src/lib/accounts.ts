/** Business expense categories (migration 0103). */
export const EXPENSE_CATEGORIES: [string, string][] = [
  ["ads", "Ads & marketing"],
  ["salaries", "Salaries"],
  ["software", "Software & servers"],
  ["office", "Office & rent"],
  ["travel", "Travel"],
  ["commission", "Commission"],
  ["taxes", "Taxes & fees"],
  ["other", "Other"],
];

export const expenseLabel = (c: string) => EXPENSE_CATEGORIES.find(([k]) => k === c)?.[1] ?? c;

/** A CSV file from rows; values with commas, quotes or line breaks are quoted. */
export function toCsv(headers: string[], rows: (string | number | null | undefined)[][]): string {
  const cell = (v: string | number | null | undefined) => {
    const s = v === null || v === undefined ? "" : String(v);
    return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  return [headers, ...rows].map((r) => r.map(cell).join(",")).join("\r\n");
}

/** Starts a download of [text] as [name] (with a BOM so Excel reads ₹ and Indian names). */
export function download(name: string, text: string) {
  const url = URL.createObjectURL(new Blob(["\uFEFF" + text], { type: "text/csv;charset=utf-8" }));
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
