import type { MetadataRoute } from "next";

const SITE = process.env.NEXT_PUBLIC_SITE_URL || "https://www.softraxa.in";

/** /sitemap.xml — the public pages, Dukania first. */
export default function sitemap(): MetadataRoute.Sitemap {
  const pages: [string, number][] = [
    ["/", 1],
    ["/dukania", 1],
    ["/download", 0.9],
    ["/contact", 0.8],
    ["/products", 0.6],
    ["/services", 0.6],
    ["/services/custom-solutions", 0.5],
    ["/about", 0.5],
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
