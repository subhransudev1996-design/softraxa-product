import { supabase } from "./supabase-client";
import type { Metadata } from "next";

// --- Static Default Fallbacks ---
const DEFAULTS: Record<string, Record<string, any>> = {
  home: {
    hero: {
      content: {
        badge: "Software agency · India",
        title: "Software that runs\nthe business, not just the browser.",
        description: "Softraxa builds practical, offline-first business software. Our flagship product, Dukania, handles billing, stock and reporting for real shops across India — online or off.",
        primary_cta: "Book a free demo",
        secondary_cta: "See Dukania",
      }
    },
    stats: {
      items: [
        { value: 100, suffix: "%", label: "Works offline" },
        { value: 30, suffix: "d", label: "Expiry alert window" },
        { value: 3, suffix: "+", label: "Staff roles built in" },
        { value: 2, suffix: "", label: "Platforms (Android · Windows)" },
      ]
    }
  },
  about: {
    hero: {
      content: {
        eyebrow: "About",
        title: "We're Softraxa.",
        lead: "A small software studio building practical, offline-first business software for the way work actually happens in India."
      }
    },
    story: {
      paragraphs: [
        "Softraxa started from a simple frustration: most business software assumes a fast, always-on internet connection and a person sitting at a desk. Real shops don't work like that. The connection drops. The counter is busy. Staff need an answer in seconds.",
        "So we build software that survives bad connections and keeps up with a busy shop floor — starting with Dukania, our offline-first billing and inventory app. Everything we make is held to the same bar: it works offline, it's priced for real margins, and the people who built it are the ones who support it.",
        "We're a small, focused team. That's deliberate — it's how one group of people can own a whole product, end to end, and stay accountable for it."
      ]
    },
    values: {
      items: [
        { title: "Offline-first, always", body: "We build for the real world, where the network drops mid-sale. The software has to keep working anyway.", icon: "WifiOff" },
        { title: "India-first", body: "Priced and designed for Indian shops and businesses — their margins, their workflows, their languages.", icon: "IndianRupee" },
        { title: "Direct support", body: "You talk to the people who wrote the code. No call centre, no ticket lottery.", icon: "MessageCircle" },
        { title: "Ship, then improve", body: "We'd rather put working software in your hands early and improve it with you than disappear for six months.", icon: "Compass" }
      ]
    }
  },
  dukania: {
    hero: {
      content: {
        eyebrow: "Softraxa product",
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
  },
  services: {
    hero: {
      content: {
        eyebrow: "Services",
        title: "What we build.",
        lead: "Softraxa is a small studio that ships complete products. Here's the work we take on, end to end."
      }
    },
    list: {
      items: [
        {
          title: "Product engineering",
          body: "We design and build the whole product as one system — mobile app, backend and admin panel — so nothing falls through the cracks between three separate vendors.",
          points: ["End-to-end architecture", "Mobile + web + backend", "One team, one roadmap"],
          icon: "Layers"
        },
        {
          title: "Offline-first mobile apps",
          body: "Apps that keep working with no signal. Local-first data, background sync and conflict handling built in from the start — not bolted on later.",
          points: ["Works fully offline", "Automatic background sync", "Android & Windows builds"],
          icon: "WifiOff"
        },
        {
          title: "Business software (POS & inventory)",
          body: "Billing, stock, purchases, returns and job cards modelled on how a real business runs its day — the domain we know best from building Dukania.",
          points: ["Billing & POS", "Stock + expiry tracking", "Returns & purchases"],
          icon: "Store"
        },
        {
          title: "Data & reporting",
          body: "Turn raw sales and stock data into reports people actually use — daily takings, top products, expenses — and export them cleanly when needed.",
          points: ["Sales & stock reports", "Expense tracking", "PDF export"],
          icon: "BarChart3"
        },
        {
          title: "Admin & operations tooling",
          body: "The back-office half of a product — client management, plans, subscriptions and support queues — so you can run the business, not just ship the app.",
          points: ["Client & plan management", "Subscriptions & billing", "Support workflows"],
          icon: "Settings"
        },
        {
          title: "Support & maintenance",
          body: "A direct line to the people who built your software. Fixes, updates and new features handled by the same team — not passed to a stranger.",
          points: ["Direct WhatsApp-speed support", "Ongoing updates", "New features on request"],
          icon: "LifeBuoy"
        }
      ]
    },
    stack: {
      items: ["Flutter", "Supabase", "Next.js", "Postgres", "Edge Functions", "Row-level security"]
    }
  }
};

const SEO_DEFAULTS: Record<string, { title: string; description: string; keywords: string[]; og_image?: string; structured_data?: any }> = {
  "/": {
    title: "Softraxa — software for businesses that don't stop moving",
    description: "Softraxa is a software agency building practical, offline-first business software. Dukania, our flagship product, runs billing, stock and reporting for real shops across India.",
    keywords: ["offline-first", "flutter", "supabase", "billing software", "inventory system"]
  },
  "/about": {
    title: "About — Softraxa",
    description: "Softraxa is a small software studio building practical, offline-first business software for India — makers of Dukania.",
    keywords: ["software studio", "odisha tech", "offline mobile apps"]
  },
  "/contact": {
    title: "Contact — Softraxa",
    description: "Get in touch with Softraxa. Book a free demo for Dukania, or talk to us about custom offline-first billing & inventory software.",
    keywords: ["contact softraxa", "dukania demo", "custom software india"]
  },
  "/dukania": {
    title: "Dukania — inventory & billing that puts you in control | Softraxa",
    description: "Dukania is Softraxa's offline-first POS and inventory app: billing, stock and expiry tracking, staff roles, reports and low-stock alerts. Android & Windows.",
    keywords: ["pos app", "gst billing app", "offline billing", "stock tracking"]
  },
  "/services": {
    title: "Services — Softraxa software agency",
    description: "What Softraxa builds: product engineering, offline-first mobile apps, business software, data & reporting, admin tooling and ongoing support.",
    keywords: ["custom app development", "offline mobile apps", "supabase dashboard nextjs"]
  },
  "/products": {
    title: "Products — Softraxa",
    description: "Explore the software products built by Softraxa, including Dukania, our offline-first inventory & stock management software.",
    keywords: ["business apps", "dukania billing"]
  }
};

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
export async function getPageContentMap(page: string): Promise<Record<string, any>> {
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
export function buildPageMetadata(seo: any): Metadata {
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
      .replace(/%sitedesc%/g, "Softraxa is a software studio building practical, offline-first business software.");
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
      images: seo.og_image ? [{ url: seo.og_image }] : undefined,
      type: "website",
    },
    twitter: {
      card: "summary_large_image",
      title: twitterTitle,
      description: twitterDescription,
      images: seo.og_image ? [seo.og_image] : undefined,
    },
  };
}
