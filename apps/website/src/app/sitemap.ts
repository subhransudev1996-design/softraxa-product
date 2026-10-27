import type { MetadataRoute } from "next";

const SITE = process.env.NEXT_PUBLIC_SITE_URL || "https://www.dukania.in";

/** /sitemap.xml — the public pages. */
export default function sitemap(): MetadataRoute.Sitemap {
  const pages: [string, number][] = [
    ["/", 1],
    ["/download", 0.9],
    ["/ai", 0.7],
    ["/contact", 0.8],
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
