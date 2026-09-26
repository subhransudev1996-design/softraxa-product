import * as LucideIcons from "lucide-react";
import type { LucideIcon } from "lucide-react";

/**
 * CMS content is free-form JSON edited in /cms and merged over the static
 * defaults in lib/cms.ts. Its shape varies per page and section, so it is
 * deliberately untyped — this alias is the one place that says so, instead
 * of `any` scattered through every page.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type CmsJson = any;

/**
 * A card/list item as edited in the CMS (icon cards, stats, details, FAQs).
 * Fields vary by section (text, numbers, bullet lists), so values are CmsJson.
 */
export type CmsItem = Record<string, CmsJson>;

const ICONS = LucideIcons as unknown as Record<string, LucideIcon | undefined>;

/** The Lucide icon named in CMS content, or a neutral fallback. */
export function cmsIcon(name: unknown): LucideIcon {
  return (typeof name === "string" && ICONS[name]) || LucideIcons.HelpCircle;
}

/** Readable message from anything thrown. */
export function errorMessage(err: unknown, fallback: string): string {
  if (err instanceof Error && err.message) return err.message;
  if (err && typeof err === "object" && "message" in err && typeof err.message === "string") {
    return err.message;
  }
  return fallback;
}
