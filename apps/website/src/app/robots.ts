import type { MetadataRoute } from "next";

const SITE = process.env.NEXT_PUBLIC_SITE_URL || "https://www.softraxa.in";

/** /robots.txt — everything public except the CMS editor and auth pages. */
export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: "*", allow: "/", disallow: ["/cms", "/auth/", "/api/"] },
    sitemap: `${SITE}/sitemap.xml`,
  };
}
