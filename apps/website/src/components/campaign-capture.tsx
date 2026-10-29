"use client";

import { useEffect } from "react";

const KEY = "dk_campaign";
const DAYS = 30;

/**
 * A visitor who came through a campaign link (?utm_source=…&utm_campaign=…,
 * made on the admin panel's Marketing → Campaigns) is remembered for 30
 * days, first link wins, so the contact form can say which campaign brought
 * them (migration 0101). Nothing is sent anywhere until they send the form.
 */
export default function CampaignCapture() {
  useEffect(() => {
    try {
      const q = new URLSearchParams(window.location.search);
      const source = q.get("utm_source")?.trim() ?? "";
      const campaign = q.get("utm_campaign")?.trim() ?? "";
      if (!source && !campaign) return;
      const old = readCampaign();
      if (old) return;
      localStorage.setItem(KEY, JSON.stringify({ source, campaign, at: Date.now() }));
    } catch {
      // Private window or storage blocked: the form just has no campaign.
    }
  }, []);
  return null;
}

/** The remembered campaign, if it is less than 30 days old. */
export function readCampaign(): { source: string; campaign: string } | null {
  try {
    const v = JSON.parse(localStorage.getItem(KEY) ?? "null");
    if (!v || Date.now() - Number(v.at) > DAYS * 86400000) return null;
    return { source: String(v.source ?? "").slice(0, 60), campaign: String(v.campaign ?? "").slice(0, 120) };
  } catch {
    return null;
  }
}

const PARTNER_KEY = "dk_partner";

/**
 * A visitor who opened an influencer partner's link (dukania.in/r/CODE,
 * migration 0104). Unlike other campaign links the partner's link wins, so
 * the code they last followed is the one the contact form and the download
 * page show.
 */
export function rememberPartner(code: string) {
  try {
    localStorage.setItem(KEY, JSON.stringify({ source: "partner", campaign: code, at: Date.now() }));
    localStorage.setItem(PARTNER_KEY, JSON.stringify({ code, at: Date.now() }));
  } catch {
    // Storage blocked: the page still shows the code to type in.
  }
}

/** The partner code remembered from a link, if it is less than 30 days old. */
export function readPartnerCode(): string | null {
  try {
    const v = JSON.parse(localStorage.getItem(PARTNER_KEY) ?? "null");
    if (!v || Date.now() - Number(v.at) > DAYS * 86400000) return null;
    return /^[A-Z0-9_-]{3,20}$/.test(String(v.code)) ? String(v.code) : null;
  } catch {
    return null;
  }
}
