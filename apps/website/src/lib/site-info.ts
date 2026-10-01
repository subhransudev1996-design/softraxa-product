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
};

const EMPTY: SiteInfo = {
  whatsapp: "", phone: "", email: "", address: "",
  androidUrl: "", windowsUrl: "",
  fromYearly: null, fromMonthly: null, trialDays: null,
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
