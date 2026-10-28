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
