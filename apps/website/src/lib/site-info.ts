import { supabase } from "./supabase-client";

/**
 * Facts the website shows that live in the admin panel's Settings
 * (migration 0059, public_site_info): contact details, the app download
 * links, Dukania's starting price and trial length. Changing them in the
 * admin panel reaches the site at the next hourly re-render.
 */
export type SiteInfo = {
  /** Digits with country code, e.g. 919876543210 ("" when not set). */
  whatsapp: string;
  phone: string;
  email: string;
  address: string;
  androidUrl: string;
  windowsUrl: string;
  /** Cheapest paid Dukania plan, per year / per month (null when unknown). */
  fromYearly: number | null;
  fromMonthly: number | null;
  trialDays: number | null;
  /** Discount on list prices shown on the website, in % (migration 0096). */
  discountPct: number;
  /** The plans with list and website prices; empty before migration 0096. */
  plans: SitePlan[];
};

export type SitePlan = {
  name: string;
  description: string;
  highlights: string[];
  billing: "yearly" | "lifetime";
  isRecommended: boolean;
  includesAi: boolean;
  users: number | null;
  listPrice: number;
  websitePrice: number;
  extraStaffPrice: number;
  aiAddonPrice: number;
};

const EMPTY: SiteInfo = {
  whatsapp: "", phone: "", email: "", address: "",
  androidUrl: "", windowsUrl: "",
  fromYearly: null, fromMonthly: null, trialDays: null,
  discountPct: 0, plans: [],
};

const num = (v: unknown) => (typeof v === "number" && v > 0 ? v : typeof v === "string" && Number(v) > 0 ? Number(v) : null);
const str = (v: unknown) => (typeof v === "string" ? v.trim() : "");

export async function getSiteInfo(): Promise<SiteInfo> {
  try {
    const { data, error } = await supabase.rpc("public_site_info");
    if (error || !data) return EMPTY;
    const d = data as Record<string, unknown>;
    return {
      whatsapp: str(d.whatsapp).replace(/\D/g, ""),
      phone: str(d.phone),
      email: str(d.email),
      address: str(d.address),
      androidUrl: str(d.android_download_url),
      windowsUrl: str(d.windows_download_url),
      fromYearly: num(d.from_yearly),
      fromMonthly: num(d.from_monthly),
      trialDays: num(d.trial_days),
      discountPct: num(d.website_discount_pct) ?? 0,
      plans: Array.isArray(d.plans)
        ? (d.plans as Record<string, unknown>[]).map((p) => ({
            name: str(p.name),
            description: str(p.description),
            highlights: Array.isArray(p.highlights) ? p.highlights.map(String) : [],
            billing: p.billing === "lifetime" ? "lifetime" : "yearly",
            isRecommended: p.is_recommended === true,
            includesAi: p.includes_ai === true,
            users: num(p.users),
            listPrice: num(p.list_price) ?? 0,
            websitePrice: num(p.website_price) ?? 0,
            extraStaffPrice: num(p.extra_staff_price) ?? 0,
            aiAddonPrice: num(p.ai_addon_price) ?? 0,
          }))
        : [],
    };
  } catch {
    return EMPTY;
  }
}

/** wa.me link with an optional pre-filled message ("" when no number). */
export function whatsappLink(info: SiteInfo, text?: string) {
  if (!info.whatsapp) return "";
  return `https://wa.me/${info.whatsapp}${text ? `?text=${encodeURIComponent(text)}` : ""}`;
}

/** "+91 70080 21274" style display of the WhatsApp number. */
export function displayPhone(digits: string) {
  if (digits.length === 12 && digits.startsWith("91")) {
    return `+91 ${digits.slice(2, 7)} ${digits.slice(7)}`;
  }
  return digits ? `+${digits}` : "";
}

export const rupees = (n: number) => `₹${n.toLocaleString("en-IN")}`;
