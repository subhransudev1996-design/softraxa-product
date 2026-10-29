import type { MetadataRoute } from "next";
import { TRADES } from "@/lib/trades";

const SITE = process.env.NEXT_PUBLIC_SITE_URL || "https://www.dukania.in";

/** /sitemap.xml — the public pages. */
export default function sitemap(): MetadataRoute.Sitemap {
  const pages: [string, number][] = [
    ["/", 1],
    ["/features", 0.9],
    ["/pricing", 0.9],
    ["/download", 0.9],
    ["/shops", 0.8],
    ...TRADES.map((t): [string, number] => [`/shops/${t.slug}`, 0.8]),
    ["/gst", 0.8],
    ["/ai", 0.7],
    ["/help", 0.7],
    ["/contact", 0.8],
    ["/about", 0.5],
    ["/refer", 0.5],
    ["/privacy", 0.3],
    ["/terms", 0.3],
    ["/delete-account", 0.2],
  ];
  return pages.map(([path, priority]) => ({
    url: `${SITE}${path}`,
    changeFrequency: "monthly",
    priority,
  }));
}
