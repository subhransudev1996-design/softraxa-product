import { supabase } from "./supabase-client";
import type { Metadata } from "next";
import type { CmsJson } from "./cms-types";

// --- Static Default Fallbacks ---
const DEFAULTS: Record<string, Record<string, CmsJson>> = {
  dukania: {
    hero: {
      content: {
        eyebrow: "Billing & stock software",
        title: "Inventory & billing\nthat puts you in control.",
        lead: "Know exactly what's in stock, bill online or completely offline, and reorder before you run out — with Dukania.",
        primary_cta: "Book a free demo",
        secondary_cta: "Watch it work"
      }
    },
    compare: {
      items: [
        "Bill a customer with no internet",
        "Spot low stock instantly",
        "Track expiry dates automatically",
        "GST reports in one tap",
        "Staff logins with limited access",
        "Sync across desktop and mobile"
      ]
    },
    builtin: {
      items: [
        { title: "Barcode scanning", body: "Scan to bill and to add stock — no add-on hardware app to wire up.", icon: "ScanLine" },
        { title: "Reports & GST", body: "Sales, profit, stock value and GST, all exportable as a clean PDF.", icon: "BarChart3" },
        { title: "Android + Windows", "body": "Run it on the counter desktop and in your pocket, in sync.", icon: "Boxes" }
      ]
    },
    faqs: {
      items: [
        { q: "Does it really work with no internet?", a: "Yes. Billing, stock updates and job cards all work fully offline. Once a connection is available, everything syncs automatically in the background — no manual step." },
        { q: "Is my shop's data secure?", a: "Every business's data is isolated at the database level using row-level security, so one shop's data is never visible to another — even on shared infrastructure." },
        { q: "What platforms does Dukania run on?", a: "Dukania runs on Android today, with a Windows desktop build for back-office use. Get in touch if you need something else." },
        { q: "Can my staff have their own logins?", a: "Yes. You can create separate logins for staff with different levels of access, so a billing assistant sees only what they need and the owner keeps full control." },
        { q: "Does it handle GST?", a: "Yes — GST on bills and services, plus a GST report showing output and input tax by rate. You can also raise non-GST bills, cash memos and estimates." }
      ]
    }
  }
};

const SEO_DEFAULTS: Record<string, { title: string; description: string; keywords: string[]; og_image?: string; structured_data?: CmsJson }> = {
  "/": {
    title: "Dukania — billing, stock & GST software for Indian shops",
    description: "Dukania runs billing, stock, GST and khata for Indian shops — on Android phones and Windows PCs, online or completely offline. Free trial.",
    keywords: ["gst billing app", "billing software for shops", "offline billing", "inventory app india", "pos app"]
  },
  "/contact": {
    title: "Contact — Dukania",
    description: "Talk to Dukania. Book a free demo, or ask anything about billing, stock and GST for your shop.",
    keywords: ["dukania demo", "billing software demo", "gst billing help"]
  },
  "/features": {
    title: "Features — Dukania billing, stock & GST software",
    description: "Everything Dukania does for your shop: fast billing, barcode, offline mode, stock and expiry, GST returns, khata, staff logins, repairs, offers and an AI assistant.",
    keywords: ["billing software features", "pos features india", "gst billing features", "inventory software features"]
  },
  "/pricing": {
    title: "Pricing — Dukania plans for shops",
    description: "Simple yearly and lifetime plans for Dukania billing and stock software. Free trial first, pay by UPI, cash or bank.",
    keywords: ["billing software price", "gst software price", "pos software cost india", "dukania price"]
  },
  "/shops": {
    title: "Billing software for your type of shop — Dukania",
    description: "Dukania is set up for grocery, mobile, hardware, garments, workshops, book stores and every retail counter in India.",
    keywords: ["billing software for shops", "retail billing software", "shop software india"]
  },
  "/gst": {
    title: "GST billing and GST returns for shops — Dukania",
    description: "GST bills with HSN, CGST/SGST/IGST, GSTR-1 JSON for the portal, GSTR-3B, GSTR-2B matching, composition and e-way bill files — from your shop's billing.",
    keywords: ["gst billing software", "gstr-1 json", "gstr-3b", "gstr-2b reconciliation", "composition scheme billing"]
  },
  "/ai": {
    title: "Run your shop from ChatGPT or Claude — Dukania AI",
    description: "Connect your Dukania shop to ChatGPT or Claude. Ask in plain words, enter supplier bills from a photo, make bills — nothing is saved until you say yes.",
    keywords: ["ai billing software", "chatgpt billing", "claude shop assistant", "ai for shops india"]
  },
  "/about": {
    title: "About Dukania",
    description: "Dukania is billing, stock and GST software made for Indian shop owners — honest pricing, works offline, real people on WhatsApp.",
    keywords: ["about dukania", "indian billing software company"]
  },
  "/refer": {
    title: "Refer a shop — earn free months of Dukania",
    description: "Share your Dukania code with another shop owner. When they join and take a plan, you get free months on yours.",
    keywords: ["dukania referral", "refer a shop"]
  },
  "/help": {
    title: "Help — Dukania questions answered",
    description: "Answers about starting with Dukania, billing and printing, stock, GST, staff, plans and payment, and your data.",
    keywords: ["dukania help", "billing app help", "gst billing faq"]
  },
  "/download": {
    title: "Download Dukania — Android app & Windows software",
    description: "Download Dukania billing and inventory software for Android phones and Windows PCs. Start with a free trial — no card, no payment.",
    keywords: ["download billing app", "billing software for windows", "billing app android"]
  }
};

/** Shown when a page link is shared on WhatsApp and elsewhere. */
const SHARE_IMAGE = "/images/site/share-image.jpg";

// --- API Helpers ---

/**
 * Fetches SEO metadata for a path, falling back to static defaults if not found.
 */
export async function getPageSeo(path: string) {
  try {
    const { data, error } = await supabase
      .from("website_seo")
      .select("*")
      .eq("path", path)
      .maybeSingle();

    if (error) {
      console.warn(`Supabase SEO query warning for path [${path}]:`, error.message);
    }
    
    const defaults = SEO_DEFAULTS[path] || SEO_DEFAULTS["/"];
    return {
      title: data?.title || defaults.title,
      description: data?.description || defaults.description,
      keywords: data?.keywords || defaults.keywords,
      og_image: data?.og_image || defaults.og_image || null,
      structured_data: data?.structured_data || defaults.structured_data || null,
      focus_keyphrase: data?.focus_keyphrase || "",
      canonical_url: data?.canonical_url || "",
      meta_robots_noindex: !!data?.meta_robots_noindex,
      meta_robots_nofollow: !!data?.meta_robots_nofollow,
      og_title: data?.og_title || "",
      og_description: data?.og_description || "",
      twitter_title: data?.twitter_title || "",
      twitter_description: data?.twitter_description || "",
      schema_type: data?.schema_type || "WebPage",
    };
  } catch (err) {
    console.error(`Error querying website_seo for path [${path}]:`, err);
    return SEO_DEFAULTS[path] || SEO_DEFAULTS["/"];
  }
}

/**
 * Fetches all section content for a page, merging it with static defaults.
 */
export async function getPageContentMap(page: string): Promise<Record<string, CmsJson>> {
  const pageDefaults = DEFAULTS[page] || {};
  try {
    const { data, error } = await supabase
      .from("website_content")
      .select("section, key, value")
      .eq("page", page);

    if (error) {
      console.warn(`Supabase content query warning for page [${page}]:`, error.message);
      return pageDefaults;
    }

    if (!data || data.length === 0) {
      return pageDefaults;
    }

    // Merge DB values over defaults
    const map = { ...pageDefaults };
    data.forEach((item) => {
      if (!map[item.section]) {
        map[item.section] = {};
      }
      map[item.section][item.key] = item.value;
    });

    return map;
  } catch (err) {
    console.error(`Error querying website_content for page [${page}]:`, err);
    return pageDefaults;
  }
}

/**
 * Maps the Yoast SEO Pro parameters returned by getPageSeo to a standard Next.js Metadata object.
 */
export function buildPageMetadata(seo: CmsJson): Metadata {
  const robots = [];
  if (seo.meta_robots_noindex) robots.push("noindex");
  if (seo.meta_robots_nofollow) robots.push("nofollow");
  const robotsStr = robots.length > 0 ? robots.join(", ") : "index, follow";

  // Template tag resolver
  const resolveTemplate = (text: string) => {
    if (!text) return "";
    return text
      .replace(/%title%/g, seo.title || "")
      .replace(/%separator%/g, "—")
      .replace(/%sitedesc%/g, "Dukania is billing, stock and GST software for Indian shops.");
  };

  const resolvedTitle = resolveTemplate(seo.title);
  const resolvedDescription = resolveTemplate(seo.description);

  const ogTitle = resolveTemplate(seo.og_title || seo.title);
  const ogDescription = resolveTemplate(seo.og_description || seo.description);
  const twitterTitle = resolveTemplate(seo.twitter_title || seo.og_title || seo.title);
  const twitterDescription = resolveTemplate(seo.twitter_description || seo.og_description || seo.description);

  return {
    title: resolvedTitle,
    description: resolvedDescription,
    keywords: seo.keywords,
    alternates: seo.canonical_url ? { canonical: seo.canonical_url } : undefined,
    robots: robotsStr,
    openGraph: {
      title: ogTitle,
      description: ogDescription,
      // The Dukania share picture unless the page has its own (CMS).
      images: [seo.og_image ? { url: seo.og_image } : { url: SHARE_IMAGE, width: 1200, height: 630 }],
      type: "website",
    },
    twitter: {
      card: "summary_large_image",
      title: twitterTitle,
      description: twitterDescription,
      images: [seo.og_image || SHARE_IMAGE],
    },
  };
}
