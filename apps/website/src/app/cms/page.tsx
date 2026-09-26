"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase-client";
import {
  Globe,
  Plus,
  Trash2,
  Save,
  Sparkles,
  FileText,
  CheckCircle2,
  AlertCircle,
  ArrowRight,
  Lock,
  LogOut,
  User,
  Laptop,
  Smartphone,
  Share2,
  Info,
} from "lucide-react";
import { errorMessage, type CmsItem, type CmsJson } from "@/lib/cms-types";

type SeoRow = {
  id?: string;
  path: string;
  title: string;
  description: string;
  keywords: string[];
  og_image?: string | null;
  structured_data?: CmsJson;
  focus_keyphrase: string;
  canonical_url: string;
  meta_robots_noindex: boolean;
  meta_robots_nofollow: boolean;
  og_title: string;
  og_description: string;
  twitter_title: string;
  twitter_description: string;
  schema_type: string;
};

type ContentRow = {
  id?: string;
  page: string;
  section: string;
  key: string;
  value: CmsJson;
};

type PageSelector = {
  id: string;      // page copy ID (e.g. "home", "about", "dukania", "services", "contact", or null/empty)
  path: string;    // SEO route path
  label: string;   // UI Label
};

const PAGES_LIST: PageSelector[] = [
  { id: "home", path: "/", label: "Home Page" },
  { id: "about", path: "/about", label: "About Page" },
  { id: "dukania", path: "/dukania", label: "Dukania Product Page" },
  { id: "services", path: "/services", label: "Services Page" },
  { id: "contact", path: "/contact", label: "Contact Page" },
  { id: "", path: "/products", label: "Products Hub Portfolio" },
  { id: "", path: "/services/custom-solutions", label: "Custom Solutions" },
];

const PAGE_DEFAULTS: Record<string, Record<string, CmsJson>> = {
  home: {
    hero: {
      content: {
        badge: "Software agency · India",
        title: "Software that runs\nthe business, not just the browser.",
        description: "Softraxa builds practical, offline-first business software.",
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
        lead: "A small software studio building practical, offline-first business software."
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
        title: "Inventory & billing that puts you in control.",
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
    faqs: {
      items: [
        { q: "Does Dukania work without internet?", a: "Yes, Dukania runs fully offline. Sales, billing, and expiry tracking don't require an active connection." },
        { q: "What devices are supported?", a: "Dukania is built for Android and Windows devices." }
      ]
    }
  },
  services: {
    hero: {
      content: {
        eyebrow: "Services",
        title: "What we build.",
        lead: "Custom POS, billing, and offline-first mobile apps shaped around your business workflows."
      }
    },
    list: {
      items: [
        { title: "Product Engineering", icon: "Code2", body: "Full stack engineering...", points: ["Next.js & Supabase dashboards", "API Integrations", "Optimized databases"] },
        { title: "Offline Mobile Apps", icon: "Smartphone", body: "Practical utility apps...", points: ["Local storage sync", "Cross platform build", "Hardware integrations"] }
      ]
    },
    stack: {
      items: ["Flutter & Dart", "Next.js", "Supabase & Postgres", "Tailwind CSS", "TypeScript"]
    }
  },
  contact: {
    details: {
      items: [
        { icon: "Mail", label: "Email", value: "hello@softraxa.com", note: "Replace with your address" },
        { icon: "MessageCircle", label: "WhatsApp", value: "+91 00000 00000", note: "Replace with your number" },
        { icon: "Clock", label: "Response time", value: "Within 1 business day", note: "" }
      ]
    },
    faqs: {
      items: [
        { q: "What happens after I submit the form?", a: "Your request lands directly with our team and we reach out within one business day." },
        { q: "Is a demo free?", a: "Yes. The walkthrough is free and there's no obligation." }
      ]
    }
  }
};

export default function CMSPage() {
  const [loading, setLoading] = useState(true);
  const [authLoading, setAuthLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [authenticated, setAuthenticated] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [authError, setAuthError] = useState<string | null>(null);

  // Tabs
  const [activeTab, setActiveTab] = useState<"seo" | "content">("seo");
  const [seoSubTab, setSeoSubTab] = useState<"general" | "social" | "advanced">("general");
  const [previewDevice, setPreviewDevice] = useState<"desktop" | "mobile">("desktop");
  const [toast, setToast] = useState<{ type: "success" | "error"; message: string } | null>(null);

  // Selection
  const [selectedPageIndex, setSelectedPageIndex] = useState<number>(0);

  // Database lists
  const [seoRows, setSeoRows] = useState<SeoRow[]>([]);
  const [contentRows, setContentRows] = useState<ContentRow[]>([]);

  // Form bindings
  const [seoForm, setSeoForm] = useState<SeoRow>({
    path: "/",
    title: "",
    description: "",
    keywords: [],
    og_image: "",
    structured_data: {},
    focus_keyphrase: "",
    canonical_url: "",
    meta_robots_noindex: false,
    meta_robots_nofollow: false,
    og_title: "",
    og_description: "",
    twitter_title: "",
    twitter_description: "",
    schema_type: "WebPage",
  });
  const [pageContentMap, setPageContentMap] = useState<Record<string, CmsJson>>({});

  const showToast = (type: "success" | "error", message: string) => {
    setToast({ type, message });
    setTimeout(() => {
      setToast(null);
    }, 4500);
  };

  // Pages are pre-rendered; ask the server to re-render them so a save goes
  // live now (api/revalidate, admin-only). Returns whether that worked.
  const publishChanges = async (): Promise<boolean> => {
    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) return false;
      const res = await fetch("/api/revalidate", {
        method: "POST",
        headers: { Authorization: `Bearer ${session.access_token}` },
      });
      return res.ok;
    } catch {
      return false;
    }
  };

  const savedMessage = async (what: string) =>
    (await publishChanges())
      ? `${what} saved and published.`
      : `${what} saved. The live site will update within an hour.`;

  const checkSession = async () => {
    setAuthLoading(true);
    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (session) {
        const isAdmin = await verifyAdminRole(session.user.id);
        if (isAdmin) {
          setAuthenticated(true);
          await loadCmsData(0); // Load and select first page
        } else {
          await supabase.auth.signOut();
          setAuthError("Access denied. Only administrators can view this page.");
        }
      }
    } catch (e) {
      console.error(e);
    } finally {
      setAuthLoading(false);
    }
  };

  const verifyAdminRole = async (userId: string): Promise<boolean> => {
    try {
      const { data, error } = await supabase
        .from("profiles")
        .select("role")
        .eq("id", userId)
        .single();
      if (error || !data) return false;
      return data.role === "admin";
    } catch {
      return false;
    }
  };

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setAuthLoading(true);
    setAuthError(null);

    try {
      const { data, error } = await supabase.auth.signInWithPassword({
        email,
        password,
      });

      if (error) {
        setAuthError(error.message);
        setAuthLoading(false);
        return;
      }

      if (data.user) {
        const isAdmin = await verifyAdminRole(data.user.id);
        if (isAdmin) {
          setAuthenticated(true);
          await loadCmsData(0);
        } else {
          await supabase.auth.signOut();
          setAuthError("Unauthorized. This account does not have administrator privileges.");
        }
      }
    } catch (err: unknown) {
      setAuthError(errorMessage(err, "An error occurred during authentication."));
    } finally {
      setAuthLoading(false);
    }
  };

  const handleLogout = async () => {
    setLoading(true);
    await supabase.auth.signOut();
    setAuthenticated(false);
    setSeoRows([]);
    setContentRows([]);
    setLoading(false);
  };

  const loadCmsData = async (initialIdx: number) => {
    setLoading(true);
    try {
      // 1. Fetch SEO records
      const { data: seoData, error: seoErr } = await supabase
        .from("website_seo")
        .select("*")
        .order("path", { ascending: true });
      if (seoErr) throw seoErr;
      setSeoRows(seoData || []);

      // 2. Fetch Content records
      const { data: contentData, error: contentErr } = await supabase
        .from("website_content")
        .select("*");
      if (contentErr) throw contentErr;
      setContentRows(contentData || []);
      
      // Select the page
      selectPageByIndex(initialIdx, seoData || [], contentData || []);
    } catch (err: unknown) {
      console.error("Error loading CMS data:", err);
      showToast("error", `Failed to load data: ${errorMessage(err, "unknown error")}`);
    } finally {
      setLoading(false);
    }
  };

  // Central page selection handler
  const selectPageByIndex = (index: number, seoList = seoRows, contentList = contentRows) => {
    setSelectedPageIndex(index);
    const targetPage = PAGES_LIST[index];

    // 1. Populate SEO Form
    const foundSeo = seoList.find((r) => r.path === targetPage.path) || {
      path: targetPage.path,
      title: "",
      description: "",
      keywords: [],
      og_image: "",
      structured_data: {},
      focus_keyphrase: "",
      canonical_url: "",
      meta_robots_noindex: false,
      meta_robots_nofollow: false,
      og_title: "",
      og_description: "",
      twitter_title: "",
      twitter_description: "",
      schema_type: "WebPage",
    };

    setSeoForm({
      path: foundSeo.path,
      title: foundSeo.title || "",
      description: foundSeo.description || "",
      keywords: foundSeo.keywords || [],
      og_image: foundSeo.og_image || "",
      structured_data: foundSeo.structured_data || {},
      focus_keyphrase: foundSeo.focus_keyphrase || "",
      canonical_url: foundSeo.canonical_url || "",
      meta_robots_noindex: !!foundSeo.meta_robots_noindex,
      meta_robots_nofollow: !!foundSeo.meta_robots_nofollow,
      og_title: foundSeo.og_title || "",
      og_description: foundSeo.og_description || "",
      twitter_title: foundSeo.twitter_title || "",
      twitter_description: foundSeo.twitter_description || "",
      schema_type: foundSeo.schema_type || "WebPage",
    });

    // 2. Populate Page Content Form (with safety deep copies)
    if (targetPage.id) {
      const pageDefaults = PAGE_DEFAULTS[targetPage.id] || {};
      const filtered = contentList.filter((r) => r.page === targetPage.id);
      
      // Deep copy defaults
      const map = JSON.parse(JSON.stringify(pageDefaults));
      
      // Override/enrich with DB rows
      filtered.forEach((r) => {
        if (!map[r.section]) {
          map[r.section] = {};
        }
        map[r.section][r.key] = r.value;
      });
      
      setPageContentMap(map);
    } else {
      setPageContentMap({});
    }
  };

  const handleSidebarClick = (index: number) => {
    selectPageByIndex(index);
  };

  // Check auth once on mount. Declared after the functions it calls, and
  // deferred so its state updates don't run synchronously inside the effect
  // (react-hooks/set-state-in-effect). Re-running it on every render would
  // reload the whole CMS each time, hence the empty dependency list.
  useEffect(() => {
    let active = true;
    Promise.resolve().then(() => {
      if (active) checkSession();
    });
    return () => {
      active = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Save SEO settings
  const saveSeo = async () => {
    setSaving(true);
    try {
      let structDataParsed = seoForm.structured_data;
      if (typeof seoForm.structured_data === "string" && seoForm.structured_data) {
        try {
          structDataParsed = JSON.parse(seoForm.structured_data);
        } catch {
          throw new Error("Structured Data (JSON-LD) is not valid JSON.");
        }
      }

      const payload = {
        path: seoForm.path,
        title: seoForm.title,
        description: seoForm.description,
        keywords: seoForm.keywords,
        og_image: seoForm.og_image || null,
        structured_data: structDataParsed || {},
        focus_keyphrase: seoForm.focus_keyphrase,
        canonical_url: seoForm.canonical_url,
        meta_robots_noindex: seoForm.meta_robots_noindex,
        meta_robots_nofollow: seoForm.meta_robots_nofollow,
        og_title: seoForm.og_title,
        og_description: seoForm.og_description,
        twitter_title: seoForm.twitter_title,
        twitter_description: seoForm.twitter_description,
        schema_type: seoForm.schema_type,
      };

      const { error } = await supabase
        .from("website_seo")
        .upsert(payload, { onConflict: "path" });

      if (error) throw error;

      // Update state
      const updatedRows = seoRows.map((r) => (r.path === seoForm.path ? { ...r, ...payload } : r));
      if (!seoRows.some((r) => r.path === seoForm.path)) {
        updatedRows.push({ ...payload });
      }
      setSeoRows(updatedRows);
      showToast("success", await savedMessage(`SEO settings for ${seoForm.path}`));
    } catch (err: unknown) {
      console.error(err);
      showToast("error", errorMessage(err, "Failed to save SEO metadata."));
    } finally {
      setSaving(false);
    }
  };

  // Save Content Section
  const saveContentSection = async (sectionName: string, keyName: string, value: CmsJson) => {
    const activePage = PAGES_LIST[selectedPageIndex];
    if (!activePage.id) return;

    setSaving(true);
    try {
      const payload = {
        page: activePage.id,
        section: sectionName,
        key: keyName,
        value,
      };

      const { error } = await supabase
        .from("website_content")
        .upsert(payload, { onConflict: "page,section,key" });

      if (error) throw error;

      // Update local contentRows
      const existingIdx = contentRows.findIndex(
        (r) => r.page === activePage.id && r.section === sectionName && r.key === keyName
      );
      const updatedRows = [...contentRows];
      if (existingIdx >= 0) {
        updatedRows[existingIdx] = { ...updatedRows[existingIdx], value };
      } else {
        updatedRows.push({ ...payload });
      }
      setContentRows(updatedRows);
      showToast("success", await savedMessage(`Section [${sectionName}]`));
    } catch (err: unknown) {
      console.error(err);
      showToast("error", errorMessage(err, "Failed to save content section."));
    } finally {
      setSaving(false);
    }
  };

  // Template tag resolver
  const resolveTemplate = (text: string) => {
    if (!text) return "";
    return text
      .replace(/%title%/g, seoForm.title || "[Page Title]")
      .replace(/%separator%/g, "—")
      .replace(/%sitedesc%/g, "Softraxa is a software studio building practical, offline-first business software.");
  };

  const insertToken = (token: string, targetField: "title" | "description" | "og_title" | "og_description" | "twitter_title" | "twitter_description") => {
    const val = seoForm[targetField] || "";
    setSeoForm({
      ...seoForm,
      [targetField]: val + token,
    });
  };

  // SEO Analysis Audits
  const runSeoAnalysis = () => {
    const audits: { status: "good" | "improvement" | "bad"; label: string }[] = [];
    const keyword = seoForm.focus_keyphrase?.toLowerCase().trim();
    
    // Resolve template variables before checking content lengths and matches
    const resolvedTitle = resolveTemplate(seoForm.title).toLowerCase();
    const resolvedDesc = resolveTemplate(seoForm.description).toLowerCase();
    const path = seoForm.path?.toLowerCase();

    if (!keyword) {
      audits.push({ status: "bad", label: "No focus keyphrase has been set. Enter one below to analyze page optimization." });
      return audits;
    }

    const wordCount = keyword.split(/\s+/).length;
    if (wordCount > 4) {
      audits.push({ status: "improvement", label: "Focus keyphrase is too long (more than 4 words). Shorten it to target specific terms." });
    } else {
      audits.push({ status: "good", label: "Focus keyphrase length is optimal." });
    }

    if (resolvedTitle.includes(keyword)) {
      if (resolvedTitle.startsWith(keyword)) {
        audits.push({ status: "good", label: "Focus keyphrase appears at the very beginning of the SEO Title!" });
      } else {
        audits.push({ status: "good", label: "Focus keyphrase appears in the SEO Title." });
      }
    } else {
      audits.push({ status: "bad", label: "Focus keyphrase does not appear in the SEO Title. Try adding it." });
    }

    if (resolvedDesc.includes(keyword)) {
      audits.push({ status: "good", label: "Focus keyphrase found in the Meta Description." });
    } else {
      audits.push({ status: "bad", label: "Focus keyphrase does not appear in the Meta Description. Add it to improve click-throughs." });
    }

    if (path !== "/") {
      const slugifiedKey = keyword.replace(/\s+/g, "-");
      if (path.includes(slugifiedKey)) {
        audits.push({ status: "good", label: "Focus keyphrase is present in the URL slug." });
      } else {
        audits.push({ status: "improvement", label: "Focus keyphrase is not in the URL slug. Consider rewriting path if possible." });
      }
    }

    const titleLen = resolvedTitle.length;
    if (titleLen === 0) {
      audits.push({ status: "bad", label: "SEO Title is empty." });
    } else if (titleLen < 30) {
      audits.push({ status: "improvement", label: `SEO Title is too short (${titleLen} chars). Use space to add keywords.` });
    } else if (titleLen > 60) {
      audits.push({ status: "improvement", label: `SEO Title is too long (${titleLen} chars). Search engines will truncate it.` });
    } else {
      audits.push({ status: "good", label: `SEO Title width is optimal (${titleLen} chars).` });
    }

    const descLen = resolvedDesc.length;
    if (descLen === 0) {
      audits.push({ status: "bad", label: "Meta Description is empty." });
    } else if (descLen < 100) {
      audits.push({ status: "improvement", label: `Meta Description is too short (${descLen} chars). Expand to 120-160 chars.` });
    } else if (descLen > 160) {
      audits.push({ status: "improvement", label: `Meta Description is too long (${descLen} chars). Search engines will truncate it.` });
    } else {
      audits.push({ status: "good", label: `Meta Description length is optimal (${descLen} chars).` });
    }

    return audits;
  };

  const seoAudits = runSeoAnalysis();
  const goodCount = seoAudits.filter((a) => a.status === "good").length;
  const totalCount = seoAudits.length;
  const scoreColor = goodCount === totalCount ? "bg-emerald-500" : goodCount > totalCount / 2 ? "bg-amber-500" : "bg-red-500";

  const activePageSelector = PAGES_LIST[selectedPageIndex];
  const pageHasContent = !!activePageSelector.id;

  if (authLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-surface py-20">
        <div className="text-center">
          <div className="h-10 w-10 animate-spin rounded-full border-[3px] border-zinc-200 border-t-violet mx-auto mb-4" />
          <p className="text-sm font-medium text-dim">Loading session...</p>
        </div>
      </div>
    );
  }

  // Render Login Form
  if (!authenticated) {
    return (
      <main className="flex min-h-screen items-center justify-center px-6 py-20 bg-surface">
        <div className="relative w-full max-w-md overflow-hidden rounded-3xl border border-hairline bg-white/70 p-8 shadow-2xl backdrop-blur-md">
          <div className="pointer-events-none absolute -right-20 -top-20 h-40 w-40 rounded-full bg-violet/10 blur-2xl" />
          <div className="pointer-events-none absolute -bottom-20 -left-20 h-40 w-40 rounded-full bg-sky/10 blur-2xl" />

          <div className="relative text-center">
            <span className="inline-flex h-12 w-12 items-center justify-center rounded-2xl bg-gradient-to-br from-violet to-sky text-white shadow-lg shadow-violet-500/20">
              <Lock className="h-5 w-5" />
            </span>
            <h1 className="mt-4 font-display text-2xl font-bold tracking-tight text-paper">Softraxa CMS</h1>
            <p className="mt-1.5 text-sm text-dim">Sign in to manage page content and SEO</p>
          </div>

          <form onSubmit={handleLogin} className="relative mt-8 space-y-4">
            <div className="space-y-1.5">
              <label className="text-xs font-semibold text-dim">Administrator Email</label>
              <div className="relative flex items-center">
                <span className="absolute left-3.5 text-zinc-400">
                  <User size={16} />
                </span>
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="admin@softraxa.com"
                  required
                  className="w-full rounded-xl border border-zinc-200 bg-white/50 pl-10 pr-3.5 py-2.5 text-sm text-paper outline-none transition placeholder:text-zinc-400 focus:border-violet focus:ring-4 focus:ring-violet/10"
                />
              </div>
            </div>

            <div className="space-y-1.5">
              <label className="text-xs font-semibold text-dim">Password</label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                required
                className="w-full rounded-xl border border-zinc-200 bg-white/50 px-3.5 py-2.5 text-sm text-paper outline-none transition placeholder:text-zinc-400 focus:border-violet focus:ring-4 focus:ring-violet/10"
              />
            </div>

            {authError && (
              <div className="flex gap-2 rounded-xl border border-red-200 bg-red-50 p-3 text-xs font-medium text-red-700">
                <AlertCircle size={15} className="shrink-0 mt-0.5" />
                <span>{authError}</span>
              </div>
            )}

            <button
              type="submit"
              className="flex w-full min-h-11 items-center justify-center gap-2 rounded-xl bg-violet py-2.5 text-sm font-semibold text-white shadow-lg shadow-violet-500/20 hover:bg-violet-600 active:scale-[0.98] transition duration-150"
            >
              Sign In <ArrowRight size={15} />
            </button>
          </form>
        </div>
      </main>
    );
  }

  // Render CMS dashboard
  return (
    <main className="min-h-screen bg-[#FDFDFE] text-paper">
      {/* CMS Header Bar */}
      <header className="sticky top-0 z-35 border-b border-hairline bg-white/85 backdrop-blur-md px-6 py-4">
        <div className="mx-auto flex max-w-7xl items-center justify-between">
          <div className="flex items-center gap-2.5">
            <span className="inline-flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-violet to-sky text-white">
              <Globe className="h-4.5 w-4.5" />
            </span>
            <div>
              <h1 className="font-display text-lg font-bold tracking-tight">Softraxa CMS</h1>
              <p className="text-[10px] text-dim font-medium uppercase tracking-wider">Unified Control Center</p>
            </div>
          </div>

          <div className="flex items-center gap-4">
            <span className="text-xs font-semibold text-zinc-500">
              Editing: <span className="font-mono text-violet font-bold">{activePageSelector.path}</span>
            </span>

            <button
              onClick={handleLogout}
              className="flex items-center gap-1.5 rounded-xl border border-zinc-200 px-3.5 py-1.5 text-xs font-semibold text-zinc-600 hover:bg-zinc-50 transition"
            >
              <LogOut size={13} /> Sign Out
            </button>
          </div>
        </div>
      </header>

      {/* Main Panel Content Area */}
      <section className="mx-auto max-w-7xl px-6 py-8">
        {/* Toast Alert */}
        {toast && (
          <div
            className={`fixed bottom-5 right-5 z-50 flex items-center gap-2.5 rounded-xl border p-4 shadow-lg animate-rise ${
              toast.type === "success"
                ? "border-emerald-200 bg-emerald-50 text-emerald-800"
                : "border-red-200 bg-red-50 text-red-800"
            }`}
          >
            {toast.type === "success" ? <CheckCircle2 size={18} /> : <AlertCircle size={18} />}
            <p className="text-sm font-medium">{toast.message}</p>
          </div>
        )}

        {loading ? (
          <div className="flex justify-center py-20">
            <div className="h-8 w-8 animate-spin rounded-full border-[3px] border-zinc-200 border-t-violet" />
          </div>
        ) : (
          <div className="grid gap-6 lg:grid-cols-4">
            {/* Unified Sidebar Page Selector */}
            <div className="lg:col-span-1 space-y-4">
              <div className="rounded-2xl border border-hairline bg-white p-5 shadow-sm">
                <h2 className="text-xs font-bold uppercase tracking-wider text-dim mb-3">Website Pages</h2>
                <div className="space-y-1">
                  {PAGES_LIST.map((page, idx) => {
                    const rowSeo = seoRows.find((r) => r.path === page.path);
                    const pathKeyphrase = rowSeo?.focus_keyphrase;
                    
                    return (
                      <button
                        key={page.path}
                        onClick={() => handleSidebarClick(idx)}
                        className={`flex w-full items-center justify-between rounded-xl px-3.5 py-2.5 text-left text-xs transition ${
                          selectedPageIndex === idx
                            ? "bg-violet-50 font-bold text-violet"
                            : "hover:bg-zinc-50 text-zinc-600"
                        }`}
                      >
                        <div className="truncate pr-2">
                          <span className="block font-medium">{page.label}</span>
                          <span className="block text-[10px] text-zinc-400 font-mono mt-0.5">{page.path}</span>
                          {pathKeyphrase && (
                            <span className="block text-[9px] text-violet/60 truncate">Key: {pathKeyphrase}</span>
                          )}
                        </div>
                      </button>
                    );
                  })}
                </div>
              </div>
            </div>

            {/* Right side form section */}
            <div className="lg:col-span-3 space-y-6">
              {/* Inner Tab bar (SEO vs Content) */}
              <div className="flex items-center justify-between rounded-2xl border border-hairline bg-white p-4 shadow-sm">
                <div className="flex gap-2">
                  <button
                    onClick={() => setActiveTab("seo")}
                    className={`flex items-center gap-1.5 rounded-xl px-4 py-2 text-xs font-semibold transition ${
                      activeTab === "seo"
                        ? "bg-violet text-white shadow-sm shadow-violet-500/15"
                        : "text-zinc-500 hover:bg-zinc-50 hover:text-zinc-700"
                    }`}
                  >
                    <Sparkles size={14} />
                    SEO Pro Settings
                  </button>
                  <button
                    onClick={() => setActiveTab("content")}
                    className={`flex items-center gap-1.5 rounded-xl px-4 py-2 text-xs font-semibold transition ${
                      activeTab === "content"
                        ? "bg-violet text-white shadow-sm shadow-violet-500/15"
                        : "text-zinc-500 hover:bg-zinc-50 hover:text-zinc-700"
                    }`}
                  >
                    <FileText size={14} />
                    Page Content Copy
                  </button>
                </div>

                <div className="flex items-center gap-3">
                  {activeTab === "seo" && (
                    <>
                      {seoForm.focus_keyphrase && (
                        <div className="flex items-center gap-1.5 text-xs font-semibold text-zinc-500 bg-zinc-50 border border-hairline px-3 py-1 rounded-xl">
                          <span className={`h-2.5 w-2.5 rounded-full ${scoreColor}`} />
                          <span>SEO Score: {goodCount}/{totalCount} Good</span>
                        </div>
                      )}
                      <button
                        disabled={saving}
                        onClick={saveSeo}
                        className="flex items-center gap-1.5 rounded-xl bg-violet px-4 py-2 text-xs font-bold text-white shadow-md shadow-violet-500/10 hover:bg-violet-600 transition"
                      >
                        <Save size={14} />
                        {saving ? "Saving..." : "Save SEO Settings"}
                      </button>
                    </>
                  )}
                </div>
              </div>

              {/* Sub-tab: SEO Pro Settings */}
              {activeTab === "seo" && (
                <div className="space-y-6">
                  {/* Local Sub-tabs (General / Social / Advanced) */}
                  <div className="flex gap-2 border-b border-zinc-100 pb-2">
                    {[
                      { id: "general", label: "General SEO" },
                      { id: "social", label: "Social Cards Previews" },
                      { id: "advanced", label: "Schema & Advanced" },
                    ].map((subTab) => (
                      <button
                        key={subTab.id}
                        onClick={() => setSeoSubTab(subTab.id as "general" | "social" | "advanced")}
                        className={`text-xs font-bold pb-2 px-1 border-b-2 transition ${
                          seoSubTab === subTab.id
                            ? "border-violet text-violet"
                            : "border-transparent text-zinc-400 hover:text-zinc-600"
                        }`}
                      >
                        {subTab.label}
                      </button>
                    ))}
                  </div>

                  {seoSubTab === "general" && (
                    <div className="grid gap-6 lg:grid-cols-3">
                      {/* Left: Input forms */}
                      <div className="lg:col-span-2 space-y-5 rounded-2xl border border-hairline bg-white p-6 shadow-sm">
                        <h3 className="font-bold text-paper border-b border-zinc-100 pb-2">Snippet Details</h3>
                        
                        <div className="space-y-1.5">
                          <label className="text-xs font-bold text-dim">Focus Keyphrase</label>
                          <input
                            type="text"
                            value={seoForm.focus_keyphrase}
                            onChange={(e) => setSeoForm({ ...seoForm, focus_keyphrase: e.target.value })}
                            placeholder="e.g. offline billing"
                            className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none transition focus:border-violet"
                          />
                        </div>

                        <div className="space-y-1.5">
                          <div className="flex items-center justify-between">
                            <label className="text-xs font-bold text-dim">SEO Title</label>
                            <div className="flex gap-1">
                              <button
                                type="button"
                                onClick={() => insertToken("%title%", "title")}
                                className="bg-zinc-100 text-zinc-600 px-2 py-0.5 rounded text-[10px] font-bold hover:bg-zinc-200 transition"
                              >
                                + Title
                              </button>
                              <button
                                type="button"
                                onClick={() => insertToken("%separator%", "title")}
                                className="bg-zinc-100 text-zinc-600 px-2 py-0.5 rounded text-[10px] font-bold hover:bg-zinc-200 transition"
                              >
                                + Separator
                              </button>
                              <button
                                type="button"
                                onClick={() => insertToken("%sitedesc%", "title")}
                                className="bg-zinc-100 text-zinc-600 px-2 py-0.5 rounded text-[10px] font-bold hover:bg-zinc-200 transition"
                              >
                                + Site Desc
                              </button>
                            </div>
                          </div>
                          <input
                            type="text"
                            value={seoForm.title}
                            onChange={(e) => setSeoForm({ ...seoForm, title: e.target.value })}
                            placeholder="Enter custom meta title"
                            className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none transition focus:border-violet"
                          />
                        </div>

                        <div className="space-y-1.5">
                          <div className="flex items-center justify-between">
                            <label className="text-xs font-bold text-dim">Meta Description</label>
                            <div className="flex gap-1">
                              <button
                                type="button"
                                onClick={() => insertToken("%title%", "description")}
                                className="bg-zinc-100 text-zinc-600 px-2 py-0.5 rounded text-[10px] font-bold hover:bg-zinc-200 transition"
                              >
                                + Title
                              </button>
                              <button
                                type="button"
                                onClick={() => insertToken("%sitedesc%", "description")}
                                className="bg-zinc-100 text-zinc-600 px-2 py-0.5 rounded text-[10px] font-bold hover:bg-zinc-200 transition"
                              >
                                + Site Desc
                              </button>
                            </div>
                          </div>
                          <textarea
                            rows={3}
                            value={seoForm.description}
                            onChange={(e) => setSeoForm({ ...seoForm, description: e.target.value })}
                            placeholder="Enter Meta description"
                            className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none transition focus:border-violet"
                          />
                        </div>

                        <div className="space-y-1.5">
                          <label className="text-xs font-bold text-dim">Keywords (Comma separated)</label>
                          <input
                            type="text"
                            value={seoForm.keywords.join(", ")}
                            onChange={(e) =>
                              setSeoForm({
                                ...seoForm,
                                keywords: e.target.value.split(",").map((k) => k.trim()).filter(Boolean),
                              })
                            }
                            placeholder="e.g. offline, billing, pos"
                            className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none transition focus:border-violet"
                          />
                        </div>
                      </div>

                      {/* Right: Previews & Analysis */}
                      <div className="space-y-6">
                        {/* SERP snippet */}
                        <div className="rounded-2xl border border-hairline bg-white p-5 shadow-sm space-y-4">
                          <div className="flex items-center justify-between border-b border-zinc-100 pb-2">
                            <h3 className="text-xs font-bold uppercase tracking-wider text-dim">Google Preview</h3>
                            <div className="flex gap-1.5 rounded-lg bg-zinc-100 p-0.5">
                              <button
                                onClick={() => setPreviewDevice("desktop")}
                                className={`p-1 rounded-md transition ${previewDevice === "desktop" ? "bg-white text-violet shadow-sm" : "text-zinc-400"}`}
                              >
                                <Laptop size={14} />
                              </button>
                              <button
                                onClick={() => setPreviewDevice("mobile")}
                                className={`p-1 rounded-md transition ${previewDevice === "mobile" ? "bg-white text-violet shadow-sm" : "text-zinc-400"}`}
                              >
                                <Smartphone size={14} />
                              </button>
                            </div>
                          </div>

                          {previewDevice === "desktop" ? (
                            <div className="font-sans text-left text-sm max-w-sm">
                              <div className="text-[12px] text-zinc-400 flex items-center gap-1.5 mb-1.5 truncate">
                                <span>https://softraxa.com</span>
                                <span>›</span>
                                <span className="truncate">{seoForm.path === "/" ? "" : seoForm.path.substring(1)}</span>
                              </div>
                              <h4 className="text-[19px] leading-tight text-[#1a0dab] font-medium hover:underline cursor-pointer truncate mb-1">
                                {resolveTemplate(seoForm.title) || "Please fill in SEO Title"}
                              </h4>
                              <p className="text-[13px] leading-normal text-[#4d5156] font-normal line-clamp-2">
                                {resolveTemplate(seoForm.description) || "Please write a Meta Description..."}
                              </p>
                            </div>
                          ) : (
                            <div className="font-sans text-left text-sm max-w-sm border border-zinc-100 rounded-xl p-3 bg-zinc-50/50">
                              <div className="flex items-center gap-2 mb-1">
                                <span className="grid h-6 w-6 place-items-center rounded-full bg-zinc-200 text-[10px] text-zinc-600 font-bold shrink-0">S</span>
                                <div className="text-[11px] truncate">
                                  <span className="block leading-none font-bold text-zinc-800">Softraxa</span>
                                  <span className="block leading-none text-zinc-500 mt-0.5">https://softraxa.com{seoForm.path}</span>
                                </div>
                              </div>
                              <h4 className="text-[16px] leading-tight text-[#1a0dab] font-medium hover:underline cursor-pointer truncate mt-1">
                                {resolveTemplate(seoForm.title) || "Please fill in SEO Title"}
                              </h4>
                              <p className="text-[12px] leading-normal text-[#4d5156] font-normal line-clamp-3 mt-1.5">
                                {resolveTemplate(seoForm.description) || "Please write a Meta Description..."}
                              </p>
                            </div>
                          )}
                        </div>

                        {/* Audits checklist */}
                        <div className="rounded-2xl border border-hairline bg-white p-5 shadow-sm space-y-3">
                          <h3 className="text-xs font-bold uppercase tracking-wider text-dim border-b border-zinc-100 pb-2">SEO Analysis</h3>
                          <div className="space-y-2">
                            {seoAudits.map((audit, idx) => (
                              <div key={idx} className="flex gap-2.5 text-xs text-zinc-600 items-start">
                                <span className={`h-2.5 w-2.5 rounded-full shrink-0 mt-1 ${
                                  audit.status === "good" ? "bg-emerald-500" : audit.status === "improvement" ? "bg-amber-500" : "bg-red-500"
                                }`} />
                                <span>{audit.label}</span>
                              </div>
                            ))}
                          </div>
                        </div>
                      </div>
                    </div>
                  )}

                  {seoSubTab === "social" && (
                    <div className="grid gap-6 lg:grid-cols-2">
                      {/* FB Card */}
                      <div className="rounded-2xl border border-hairline bg-white p-6 shadow-sm space-y-4">
                        <div className="flex items-center gap-2 border-b border-zinc-100 pb-2">
                          <svg className="text-blue-600 h-[18px] w-[18px]" viewBox="0 0 24 24" fill="currentColor">
                            <path d="M22 12a10 10 0 1 0-11.56 9.88v-6.99H7.9V12h2.54V9.8c0-2.5 1.49-3.89 3.78-3.89 1.09 0 2.24.2 2.24.2v2.46h-1.26c-1.24 0-1.63.77-1.63 1.56V12h2.78l-.44 2.89h-2.34v6.99A10 10 0 0 0 22 12z" />
                          </svg>
                          <h3 className="font-bold text-paper">Facebook Share Settings</h3>
                        </div>

                        <div className="space-y-1.5">
                          <label className="text-xs font-bold text-dim">Facebook Card Title</label>
                          <input
                            type="text"
                            value={seoForm.og_title}
                            onChange={(e) => setSeoForm({ ...seoForm, og_title: e.target.value })}
                            placeholder="Fallback to SEO Title"
                            className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none transition focus:border-violet"
                          />
                        </div>

                        <div className="space-y-1.5">
                          <label className="text-xs font-bold text-dim">Facebook Card Description</label>
                          <textarea
                            rows={2}
                            value={seoForm.og_description}
                            onChange={(e) => setSeoForm({ ...seoForm, og_description: e.target.value })}
                            placeholder="Fallback to Meta Description"
                            className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none transition focus:border-violet"
                          />
                        </div>

                        <div className="space-y-1.5">
                          <label className="text-xs font-bold text-dim">Social Share Image URL</label>
                          <input
                            type="text"
                            value={seoForm.og_image || ""}
                            onChange={(e) => setSeoForm({ ...seoForm, og_image: e.target.value })}
                            placeholder="Image URL shown on Facebook/Twitter posts"
                            className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none transition focus:border-violet"
                          />
                        </div>

                        <div className="border border-zinc-200 rounded-xl overflow-hidden shadow-sm bg-[#f2f3f5] font-sans text-left max-w-sm mt-4">
                          {seoForm.og_image ? (
                            <div className="h-40 w-full bg-zinc-200 overflow-hidden relative">
                              <img src={seoForm.og_image} alt="Facebook Preview" className="h-full w-full object-cover" />
                            </div>
                          ) : (
                            <div className="h-40 w-full bg-zinc-100 flex items-center justify-center text-zinc-400">
                              <Share2 size={24} />
                            </div>
                          )}
                          <div className="p-3 bg-white border-t border-zinc-200">
                            <span className="text-[10px] uppercase text-zinc-500 tracking-wider font-semibold">SOFTRAXA.COM</span>
                            <h4 className="text-[14px] font-bold text-zinc-900 leading-tight mt-1 truncate">
                              {resolveTemplate(seoForm.og_title || seoForm.title) || "Software shaped around your business."}
                            </h4>
                            <p className="text-[12px] text-zinc-500 mt-1 line-clamp-2 leading-snug">
                              {resolveTemplate(seoForm.og_description || seoForm.description) || "Softraxa builds practical, offline-first business software."}
                            </p>
                          </div>
                        </div>
                      </div>

                      {/* X (Twitter) Card */}
                      <div className="rounded-2xl border border-hairline bg-white p-6 shadow-sm space-y-4">
                        <div className="flex items-center gap-2 border-b border-zinc-100 pb-2">
                          <svg className="text-zinc-900 h-[18px] w-[18px]" viewBox="0 0 24 24" fill="currentColor">
                            <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
                          </svg>
                          <h3 className="font-bold text-paper">X / Twitter Card Settings</h3>
                        </div>

                        <div className="space-y-1.5">
                          <label className="text-xs font-bold text-dim">X / Twitter Title</label>
                          <input
                            type="text"
                            value={seoForm.twitter_title}
                            onChange={(e) => setSeoForm({ ...seoForm, twitter_title: e.target.value })}
                            placeholder="Fallback to Facebook Title"
                            className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none transition focus:border-violet"
                          />
                        </div>

                        <div className="space-y-1.5">
                          <label className="text-xs font-bold text-dim">X / Twitter Description</label>
                          <textarea
                            rows={2}
                            value={seoForm.twitter_description}
                            onChange={(e) => setSeoForm({ ...seoForm, twitter_description: e.target.value })}
                            placeholder="Fallback to Facebook Description"
                            className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none transition focus:border-violet"
                          />
                        </div>

                        <div className="border border-zinc-200 rounded-2xl overflow-hidden shadow-sm bg-white font-sans text-left max-w-sm mt-12 relative">
                          {seoForm.og_image ? (
                            <div className="h-40 w-full bg-zinc-200 overflow-hidden">
                              <img src={seoForm.og_image} alt="Twitter Preview" className="h-full w-full object-cover" />
                            </div>
                          ) : (
                            <div className="h-40 w-full bg-zinc-50 flex items-center justify-center text-zinc-400">
                              <Share2 size={24} />
                            </div>
                          )}
                          <div className="p-3 border-t border-zinc-100 bg-white">
                            <span className="text-[10px] text-zinc-500 font-normal">softraxa.com</span>
                            <h4 className="text-[13px] font-semibold text-zinc-950 leading-tight mt-0.5 truncate">
                              {resolveTemplate(seoForm.twitter_title || seoForm.og_title || seoForm.title) || "Software shaped around your business."}
                            </h4>
                            <p className="text-[11px] text-zinc-500 mt-1 line-clamp-2 leading-snug">
                              {resolveTemplate(seoForm.twitter_description || seoForm.og_description || seoForm.description) || "Softraxa builds practical, offline-first business software."}
                            </p>
                          </div>
                        </div>
                      </div>
                    </div>
                  )}

                  {seoSubTab === "advanced" && (
                    <div className="rounded-2xl border border-hairline bg-white p-6 shadow-sm space-y-6">
                      <h3 className="font-bold text-paper border-b border-zinc-100 pb-2">Advanced SEO Configuration</h3>

                      <div className="grid gap-6 md:grid-cols-2">
                        <div className="space-y-4">
                          <h4 className="text-xs font-bold uppercase tracking-wider text-dim">Search Engine Visibility</h4>
                          
                          <div className="flex items-center justify-between rounded-xl bg-zinc-50 p-4 border border-zinc-100">
                            <div>
                              <label className="text-sm font-bold text-paper">Meta Robots: NoIndex</label>
                              <p className="text-[11px] text-dim mt-0.5">Instruct search engines NOT to index this page.</p>
                            </div>
                            <button
                              type="button"
                              onClick={() => setSeoForm({ ...seoForm, meta_robots_noindex: !seoForm.meta_robots_noindex })}
                              className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors duration-200 outline-none ${seoForm.meta_robots_noindex ? "bg-violet" : "bg-zinc-300"}`}
                            >
                              <span className={`inline-block h-5 w-5 transform rounded-full bg-white shadow-sm transition-transform duration-200 ${seoForm.meta_robots_noindex ? "translate-x-5" : "translate-x-0.5"}`} />
                            </button>
                          </div>

                          <div className="flex items-center justify-between rounded-xl bg-zinc-50 p-4 border border-zinc-100">
                            <div>
                              <label className="text-sm font-bold text-paper">Meta Robots: NoFollow</label>
                              <p className="text-[11px] text-dim mt-0.5">Instruct crawlers NOT to follow links on this page.</p>
                            </div>
                            <button
                              type="button"
                              onClick={() => setSeoForm({ ...seoForm, meta_robots_nofollow: !seoForm.meta_robots_nofollow })}
                              className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors duration-200 outline-none ${seoForm.meta_robots_nofollow ? "bg-violet" : "bg-zinc-300"}`}
                            >
                              <span className={`inline-block h-5 w-5 transform rounded-full bg-white shadow-sm transition-transform duration-200 ${seoForm.meta_robots_nofollow ? "translate-x-5" : "translate-x-0.5"}`} />
                            </button>
                          </div>
                        </div>

                        <div className="space-y-4">
                          <h4 className="text-xs font-bold uppercase tracking-wider text-dim">Canonical URL & Schema Type</h4>

                          <div className="space-y-1.5">
                            <label className="text-xs font-semibold text-dim">Canonical URL</label>
                            <input
                              type="text"
                              value={seoForm.canonical_url}
                              onChange={(e) => setSeoForm({ ...seoForm, canonical_url: e.target.value })}
                              placeholder="e.g. https://softraxa.com/original-page-url"
                              className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none transition focus:border-violet"
                            />
                          </div>

                          <div className="space-y-1.5">
                            <label className="text-xs font-semibold text-dim">Structured Page Schema Type</label>
                            <select
                              value={seoForm.schema_type}
                              onChange={(e) => setSeoForm({ ...seoForm, schema_type: e.target.value })}
                              className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none transition focus:border-violet"
                            >
                              <option value="WebPage">WebPage (General page)</option>
                              <option value="AboutPage">AboutPage (About Us details)</option>
                              <option value="ContactPage">ContactPage (Contact form info)</option>
                              <option value="FAQPage">FAQPage (Q&A listings)</option>
                              <option value="ProfilePage">ProfilePage (Personal description)</option>
                            </select>
                          </div>
                        </div>
                      </div>

                      <div className="space-y-1.5 pt-4 border-t border-zinc-100">
                        <label className="text-xs font-bold text-dim">Custom JSON-LD Structured Data Schema Override</label>
                        <textarea
                          rows={5}
                          value={
                            typeof seoForm.structured_data === "object"
                              ? JSON.stringify(seoForm.structured_data, null, 2)
                              : seoForm.structured_data
                          }
                          onChange={(e) => setSeoForm({ ...seoForm, structured_data: e.target.value })}
                          placeholder='{\n  "@context": "https://schema.org",\n  "@type": "WebSite"\n}'
                          className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 font-mono text-xs text-zinc-800 outline-none transition focus:border-violet"
                        />
                      </div>
                    </div>
                  )}
                </div>
              )}

              {/* Sub-tab: Page Copy Content */}
              {activeTab === "content" && (
                <div className="space-y-6">
                  {!pageHasContent ? (
                    <div className="rounded-2xl border border-amber-200 bg-amber-50/50 p-6 text-center space-y-2">
                      <Info className="mx-auto text-amber-600" size={24} />
                      <h4 className="font-bold text-amber-800 text-sm">Static Page Layout Notice</h4>
                      <p className="text-xs text-amber-700 max-w-md mx-auto leading-relaxed">
                        This page ({activePageSelector.path}) uses a custom-coded showcase layout. You can configure its SEO metadata, Open Graph cards, and indexing parameters in the **SEO Pro Settings** tab above.
                      </p>
                    </div>
                  ) : (
                    <>
                      {/* HOME PAGE FORMS */}
                      {activePageSelector.id === "home" && (
                        <>
                          <div className="rounded-2xl border border-hairline bg-white p-6 shadow-sm space-y-4">
                            <div className="flex items-center justify-between border-b border-zinc-100 pb-3">
                              <h3 className="font-bold text-paper">Home Page Hero</h3>
                              <button
                                disabled={saving}
                                onClick={() => saveContentSection("hero", "content", pageContentMap.hero?.content)}
                                className="flex items-center gap-1.5 rounded-xl bg-violet px-3 py-1.5 text-xs font-bold text-white shadow-md hover:bg-violet-600 transition"
                              >
                                <Save size={13} /> Save Hero
                              </button>
                            </div>

                            <div className="space-y-1">
                              <label className="text-xs font-semibold text-dim">Hero Badge Label</label>
                              <input
                                type="text"
                                value={pageContentMap.hero?.content?.badge || ""}
                                onChange={(e) => {
                                  const updated = { ...pageContentMap };
                                  updated.hero.content.badge = e.target.value;
                                  setPageContentMap(updated);
                                }}
                                className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                              />
                            </div>

                            <div className="space-y-1">
                              <label className="text-xs font-semibold text-dim">Hero Title (Use \n for breaks)</label>
                              <textarea
                                rows={2}
                                value={pageContentMap.hero?.content?.title || ""}
                                onChange={(e) => {
                                  const updated = { ...pageContentMap };
                                  updated.hero.content.title = e.target.value;
                                  setPageContentMap(updated);
                                }}
                                className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                              />
                            </div>

                            <div className="space-y-1">
                              <label className="text-xs font-semibold text-dim">Hero Description</label>
                              <textarea
                                rows={3}
                                value={pageContentMap.hero?.content?.description || ""}
                                onChange={(e) => {
                                  const updated = { ...pageContentMap };
                                  updated.hero.content.description = e.target.value;
                                  setPageContentMap(updated);
                                }}
                                className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                              />
                            </div>

                            <div className="grid grid-cols-2 gap-4">
                              <div className="space-y-1">
                                <label className="text-xs font-semibold text-dim">Primary CTA text</label>
                                <input
                                  type="text"
                                  value={pageContentMap.hero?.content?.primary_cta || ""}
                                  onChange={(e) => {
                                    const updated = { ...pageContentMap };
                                    updated.hero.content.primary_cta = e.target.value;
                                    setPageContentMap(updated);
                                  }}
                                  className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                />
                              </div>
                              <div className="space-y-1">
                                <label className="text-xs font-semibold text-dim">Secondary CTA text</label>
                                <input
                                  type="text"
                                  value={pageContentMap.hero?.content?.secondary_cta || ""}
                                  onChange={(e) => {
                                    const updated = { ...pageContentMap };
                                    updated.hero.content.secondary_cta = e.target.value;
                                    setPageContentMap(updated);
                                  }}
                                  className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                />
                              </div>
                            </div>
                          </div>

                          <div className="rounded-2xl border border-hairline bg-white p-6 shadow-sm space-y-4">
                            <div className="flex items-center justify-between border-b border-zinc-100 pb-3">
                              <h3 className="font-bold text-paper">Homepage Stats Grid</h3>
                              <button
                                disabled={saving}
                                onClick={() => saveContentSection("stats", "items", pageContentMap.stats?.items)}
                                className="flex items-center gap-1.5 rounded-xl bg-violet px-3 py-1.5 text-xs font-bold text-white shadow-md hover:bg-violet-600 transition"
                              >
                                <Save size={13} /> Save Stats
                              </button>
                            </div>

                            {pageContentMap.stats?.items?.map((stat: CmsItem, index: number) => (
                              <div key={index} className="grid grid-cols-3 gap-4 border-b border-zinc-50 pb-3 last:border-0 last:pb-0">
                                <div className="space-y-1">
                                  <label className="text-xs font-semibold text-dim">Value</label>
                                  <input
                                    type="number"
                                    value={stat.value}
                                    onChange={(e) => {
                                      const updated = { ...pageContentMap };
                                      updated.stats.items[index].value = parseInt(e.target.value) || 0;
                                      setPageContentMap(updated);
                                    }}
                                    className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                  />
                                </div>
                                <div className="space-y-1">
                                  <label className="text-xs font-semibold text-dim">Suffix</label>
                                  <input
                                    type="text"
                                    value={stat.suffix}
                                    onChange={(e) => {
                                      const updated = { ...pageContentMap };
                                      updated.stats.items[index].suffix = e.target.value;
                                      setPageContentMap(updated);
                                    }}
                                    className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                  />
                                </div>
                                <div className="space-y-1">
                                  <label className="text-xs font-semibold text-dim">Label</label>
                                  <input
                                    type="text"
                                    value={stat.label}
                                    onChange={(e) => {
                                      const updated = { ...pageContentMap };
                                      updated.stats.items[index].label = e.target.value;
                                      setPageContentMap(updated);
                                    }}
                                    className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                  />
                                </div>
                              </div>
                            ))}
                          </div>
                        </>
                      )}

                      {/* ABOUT PAGE FORMS */}
                      {activePageSelector.id === "about" && (
                        <>
                          <div className="rounded-2xl border border-hairline bg-white p-6 shadow-sm space-y-4">
                            <div className="flex items-center justify-between border-b border-zinc-100 pb-3">
                              <h3 className="font-bold text-paper">About Hero</h3>
                              <button
                                disabled={saving}
                                onClick={() => saveContentSection("hero", "content", pageContentMap.hero?.content)}
                                className="flex items-center gap-1.5 rounded-xl bg-violet px-3 py-1.5 text-xs font-bold text-white shadow-md hover:bg-violet-600 transition"
                              >
                                <Save size={13} /> Save Hero
                              </button>
                            </div>

                            <div className="grid grid-cols-2 gap-4">
                              <div className="space-y-1">
                                <label className="text-xs font-semibold text-dim">Eyebrow</label>
                                <input
                                  type="text"
                                  value={pageContentMap.hero?.content?.eyebrow || ""}
                                  onChange={(e) => {
                                    const updated = { ...pageContentMap };
                                    updated.hero.content.eyebrow = e.target.value;
                                    setPageContentMap(updated);
                                  }}
                                  className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                />
                              </div>
                              <div className="space-y-1">
                                <label className="text-xs font-semibold text-dim">Title</label>
                                <input
                                  type="text"
                                  value={pageContentMap.hero?.content?.title || ""}
                                  onChange={(e) => {
                                    const updated = { ...pageContentMap };
                                    updated.hero.content.title = e.target.value;
                                    setPageContentMap(updated);
                                  }}
                                  className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                />
                              </div>
                            </div>

                            <div className="space-y-1">
                              <label className="text-xs font-semibold text-dim">Lead</label>
                              <textarea
                                rows={2}
                                value={pageContentMap.hero?.content?.lead || ""}
                                onChange={(e) => {
                                  const updated = { ...pageContentMap };
                                  updated.hero.content.lead = e.target.value;
                                  setPageContentMap(updated);
                                }}
                                className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                              />
                            </div>
                          </div>

                          <div className="rounded-2xl border border-hairline bg-white p-6 shadow-sm space-y-4">
                            <div className="flex items-center justify-between border-b border-zinc-100 pb-3">
                              <h3 className="font-bold text-paper">Our Story Paragraphs</h3>
                              <button
                                disabled={saving}
                                onClick={() => saveContentSection("story", "paragraphs", pageContentMap.story?.paragraphs)}
                                className="flex items-center gap-1.5 rounded-xl bg-violet px-3 py-1.5 text-xs font-bold text-white shadow-md hover:bg-violet-600 transition"
                              >
                                <Save size={13} /> Save Story
                              </button>
                            </div>

                            {pageContentMap.story?.paragraphs?.map((p: string, idx: number) => (
                              <div key={idx} className="space-y-1.5">
                                <label className="text-xs font-semibold text-dim">Paragraph {idx + 1}</label>
                                <textarea
                                  rows={3}
                                  value={p}
                                  onChange={(e) => {
                                    const updated = { ...pageContentMap };
                                    updated.story.paragraphs[idx] = e.target.value;
                                    setPageContentMap(updated);
                                  }}
                                  className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                />
                              </div>
                            ))}
                          </div>

                          <div className="rounded-2xl border border-hairline bg-white p-6 shadow-sm space-y-4">
                            <div className="flex items-center justify-between border-b border-zinc-100 pb-3">
                              <h3 className="font-bold text-paper">Core Beliefs & Values</h3>
                              <button
                                disabled={saving}
                                onClick={() => saveContentSection("values", "items", pageContentMap.values?.items)}
                                className="flex items-center gap-1.5 rounded-xl bg-violet px-3 py-1.5 text-xs font-bold text-white shadow-md hover:bg-violet-600 transition"
                              >
                                <Save size={13} /> Save Beliefs
                              </button>
                            </div>

                            {pageContentMap.values?.items?.map((item: CmsItem, idx: number) => (
                              <div key={idx} className="grid grid-cols-2 gap-4 border-b border-zinc-100 pb-4 last:border-0 last:pb-0">
                                <div className="space-y-1">
                                  <label className="text-xs font-semibold text-dim">Belief Title</label>
                                  <input
                                    type="text"
                                    value={item.title}
                                    onChange={(e) => {
                                      const updated = { ...pageContentMap };
                                      updated.values.items[idx].title = e.target.value;
                                      setPageContentMap(updated);
                                    }}
                                    className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                  />
                                </div>
                                <div className="space-y-1">
                                  <label className="text-xs font-semibold text-dim">Icon ID</label>
                                  <input
                                    type="text"
                                    value={item.icon}
                                    onChange={(e) => {
                                      const updated = { ...pageContentMap };
                                      updated.values.items[idx].icon = e.target.value;
                                      setPageContentMap(updated);
                                    }}
                                    className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                  />
                                </div>
                                <div className="col-span-2 space-y-1">
                                  <label className="text-xs font-semibold text-dim">Belief Description</label>
                                  <textarea
                                    rows={2}
                                    value={item.body}
                                    onChange={(e) => {
                                      const updated = { ...pageContentMap };
                                      updated.values.items[idx].body = e.target.value;
                                      setPageContentMap(updated);
                                    }}
                                    className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                  />
                                </div>
                              </div>
                            ))}
                          </div>
                        </>
                      )}

                      {/* DUKANIA PRODUCT FORMS */}
                      {activePageSelector.id === "dukania" && (
                        <>
                          <div className="rounded-2xl border border-hairline bg-white p-6 shadow-sm space-y-4">
                            <div className="flex items-center justify-between border-b border-zinc-100 pb-3">
                              <h3 className="font-bold text-paper">Dukania Hero</h3>
                              <button
                                disabled={saving}
                                onClick={() => saveContentSection("hero", "content", pageContentMap.hero?.content)}
                                className="flex items-center gap-1.5 rounded-xl bg-violet px-3 py-1.5 text-xs font-bold text-white shadow-md hover:bg-violet-600 transition"
                              >
                                <Save size={13} /> Save Hero
                              </button>
                            </div>

                            <div className="grid grid-cols-2 gap-4">
                              <div className="space-y-1">
                                <label className="text-xs font-semibold text-dim">Eyebrow</label>
                                <input
                                  type="text"
                                  value={pageContentMap.hero?.content?.eyebrow || ""}
                                  onChange={(e) => {
                                    const updated = { ...pageContentMap };
                                    updated.hero.content.eyebrow = e.target.value;
                                    setPageContentMap(updated);
                                  }}
                                  className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                />
                              </div>
                              <div className="space-y-1">
                                <label className="text-xs font-semibold text-dim">Title</label>
                                <input
                                  type="text"
                                  value={pageContentMap.hero?.content?.title || ""}
                                  onChange={(e) => {
                                    const updated = { ...pageContentMap };
                                    updated.hero.content.title = e.target.value;
                                    setPageContentMap(updated);
                                  }}
                                  className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                />
                              </div>
                            </div>

                            <div className="space-y-1">
                              <label className="text-xs font-semibold text-dim">Lead Copy</label>
                              <textarea
                                rows={2}
                                value={pageContentMap.hero?.content?.lead || ""}
                                onChange={(e) => {
                                  const updated = { ...pageContentMap };
                                  updated.hero.content.lead = e.target.value;
                                  setPageContentMap(updated);
                                }}
                                className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                              />
                            </div>
                          </div>

                          <div className="rounded-2xl border border-hairline bg-white p-6 shadow-sm space-y-4">
                            <div className="flex items-center justify-between border-b border-zinc-100 pb-3">
                              <h3 className="font-bold text-paper">Advantage Comparison Points</h3>
                              <button
                                disabled={saving}
                                onClick={() => saveContentSection("compare", "items", pageContentMap.compare?.items)}
                                className="flex items-center gap-1.5 rounded-xl bg-violet px-3 py-1.5 text-xs font-bold text-white shadow-md hover:bg-violet-600 transition"
                              >
                                <Save size={13} /> Save Compare
                              </button>
                            </div>

                            {pageContentMap.compare?.items?.map((item: string, idx: number) => (
                              <div key={idx} className="flex gap-2.5 items-center">
                                <span className="font-mono text-xs text-zinc-400 font-bold w-6">{idx + 1}</span>
                                <input
                                  type="text"
                                  value={item}
                                  onChange={(e) => {
                                    const updated = { ...pageContentMap };
                                    updated.compare.items[idx] = e.target.value;
                                    setPageContentMap(updated);
                                  }}
                                  className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                />
                              </div>
                            ))}
                          </div>

                          <div className="rounded-2xl border border-hairline bg-white p-6 shadow-sm space-y-4">
                            <div className="flex items-center justify-between border-b border-zinc-100 pb-3">
                              <h3 className="font-bold text-paper">Dukania FAQs</h3>
                              <div className="flex gap-2">
                                <button
                                  onClick={() => {
                                    const updated = { ...pageContentMap };
                                    if (!updated.faqs) updated.faqs = { items: [] };
                                    updated.faqs.items.push({ q: "New FAQ Question?", a: "Add answer here." });
                                    setPageContentMap(updated);
                                  }}
                                  className="flex items-center gap-1.5 rounded-xl border border-zinc-200 px-3 py-1.5 text-xs font-bold text-zinc-600 hover:bg-zinc-50 transition"
                                >
                                  <Plus size={13} /> Add FAQ
                                </button>
                                <button
                                  disabled={saving}
                                  onClick={() => saveContentSection("faqs", "items", pageContentMap.faqs?.items)}
                                  className="flex items-center gap-1.5 rounded-xl bg-violet px-3 py-1.5 text-xs font-bold text-white shadow-md hover:bg-violet-600 transition"
                                >
                                  <Save size={13} /> Save FAQs
                                </button>
                              </div>
                            </div>

                            {pageContentMap.faqs?.items?.map((faq: CmsItem, idx: number) => (
                              <div key={idx} className="border border-zinc-200 rounded-xl p-4 bg-zinc-50/20 relative space-y-2">
                                <button
                                  onClick={() => {
                                    const updated = { ...pageContentMap };
                                    updated.faqs.items.splice(idx, 1);
                                    setPageContentMap(updated);
                                  }}
                                  className="absolute top-4 right-4 text-red-500 hover:text-red-700 transition"
                                >
                                  <Trash2 size={14} />
                                </button>
                                <div className="pr-8 space-y-1">
                                  <label className="text-[10px] font-bold uppercase tracking-wider text-dim">Question</label>
                                  <input
                                    type="text"
                                    value={faq.q}
                                    onChange={(e) => {
                                      const updated = { ...pageContentMap };
                                      updated.faqs.items[idx].q = e.target.value;
                                      setPageContentMap(updated);
                                    }}
                                    className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                  />
                                </div>
                                <div className="space-y-1">
                                  <label className="text-[10px] font-bold uppercase tracking-wider text-dim">Answer</label>
                                  <textarea
                                    rows={2}
                                    value={faq.a}
                                    onChange={(e) => {
                                      const updated = { ...pageContentMap };
                                      updated.faqs.items[idx].a = e.target.value;
                                      setPageContentMap(updated);
                                    }}
                                    className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                  />
                                </div>
                              </div>
                            ))}
                          </div>
                        </>
                      )}

                      {/* SERVICES PAGE FORMS */}
                      {activePageSelector.id === "services" && (
                        <>
                          <div className="rounded-2xl border border-hairline bg-white p-6 shadow-sm space-y-4">
                            <div className="flex items-center justify-between border-b border-zinc-100 pb-3">
                              <h3 className="font-bold text-paper">Services Hero</h3>
                              <button
                                disabled={saving}
                                onClick={() => saveContentSection("hero", "content", pageContentMap.hero?.content)}
                                className="flex items-center gap-1.5 rounded-xl bg-violet px-3 py-1.5 text-xs font-bold text-white shadow-md hover:bg-violet-600 transition"
                              >
                                <Save size={13} /> Save Hero
                              </button>
                            </div>

                            <div className="grid grid-cols-2 gap-4">
                              <div className="space-y-1">
                                <label className="text-xs font-semibold text-dim">Eyebrow</label>
                                <input
                                  type="text"
                                  value={pageContentMap.hero?.content?.eyebrow || ""}
                                  onChange={(e) => {
                                    const updated = { ...pageContentMap };
                                    updated.hero.content.eyebrow = e.target.value;
                                    setPageContentMap(updated);
                                  }}
                                  className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                />
                              </div>
                              <div className="space-y-1">
                                <label className="text-xs font-semibold text-dim">Title</label>
                                <input
                                  type="text"
                                  value={pageContentMap.hero?.content?.title || ""}
                                  onChange={(e) => {
                                    const updated = { ...pageContentMap };
                                    updated.hero.content.title = e.target.value;
                                    setPageContentMap(updated);
                                  }}
                                  className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                />
                              </div>
                            </div>

                            <div className="space-y-1">
                              <label className="text-xs font-semibold text-dim">Lead Copy</label>
                              <textarea
                                rows={2}
                                value={pageContentMap.hero?.content?.lead || ""}
                                onChange={(e) => {
                                  const updated = { ...pageContentMap };
                                  updated.hero.content.lead = e.target.value;
                                  setPageContentMap(updated);
                                }}
                                className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                              />
                            </div>
                          </div>

                          <div className="rounded-2xl border border-hairline bg-white p-6 shadow-sm space-y-4">
                            <div className="flex items-center justify-between border-b border-zinc-100 pb-3">
                              <h3 className="font-bold text-paper">Services List</h3>
                              <button
                                disabled={saving}
                                onClick={() => saveContentSection("list", "items", pageContentMap.list?.items)}
                                className="flex items-center gap-1.5 rounded-xl bg-violet px-3 py-1.5 text-xs font-bold text-white shadow-md hover:bg-violet-600 transition"
                              >
                                <Save size={13} /> Save Services
                              </button>
                            </div>

                            {pageContentMap.list?.items?.map((item: CmsItem, idx: number) => (
                              <div key={idx} className="border-b border-zinc-100 pb-4 mb-4 last:border-0 last:pb-0 last:mb-0 space-y-3">
                                <div className="grid grid-cols-2 gap-4">
                                  <div className="space-y-1">
                                    <label className="text-xs font-semibold text-dim">Service Title</label>
                                    <input
                                      type="text"
                                      value={item.title}
                                      onChange={(e) => {
                                        const updated = { ...pageContentMap };
                                        updated.list.items[idx].title = e.target.value;
                                        setPageContentMap(updated);
                                      }}
                                      className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                    />
                                  </div>
                                  <div className="space-y-1">
                                    <label className="text-xs font-semibold text-dim">Icon Name</label>
                                    <input
                                      type="text"
                                      value={item.icon}
                                      onChange={(e) => {
                                        const updated = { ...pageContentMap };
                                        updated.list.items[idx].icon = e.target.value;
                                        setPageContentMap(updated);
                                      }}
                                      className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                    />
                                  </div>
                                </div>

                                <div className="space-y-1">
                                  <label className="text-xs font-semibold text-dim">Service Description</label>
                                  <textarea
                                    rows={2}
                                    value={item.body}
                                    onChange={(e) => {
                                      const updated = { ...pageContentMap };
                                      updated.list.items[idx].body = e.target.value;
                                      setPageContentMap(updated);
                                    }}
                                    className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                  />
                                </div>

                                <div className="space-y-1">
                                  <label className="text-xs font-semibold text-dim">Bullets / Details (Comma separated)</label>
                                  <input
                                    type="text"
                                    value={item.points?.join(", ") || ""}
                                    onChange={(e) => {
                                      const updated = { ...pageContentMap };
                                      updated.list.items[idx].points = e.target.value
                                        .split(",")
                                        .map((p: string) => p.trim())
                                        .filter(Boolean);
                                      setPageContentMap(updated);
                                    }}
                                    className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                  />
                                </div>
                              </div>
                            ))}
                          </div>

                          <div className="rounded-2xl border border-hairline bg-white p-6 shadow-sm space-y-4">
                            <div className="flex items-center justify-between border-b border-zinc-100 pb-3">
                              <h3 className="font-bold text-paper">Tech Stack Highlights</h3>
                              <button
                                disabled={saving}
                                onClick={() => saveContentSection("stack", "items", pageContentMap.stack?.items)}
                                className="flex items-center gap-1.5 rounded-xl bg-violet px-3 py-1.5 text-xs font-bold text-white shadow-md hover:bg-violet-600 transition"
                              >
                                <Save size={13} /> Save Stack
                              </button>
                            </div>

                            <div className="space-y-1">
                              <label className="text-xs font-semibold text-dim">Stack items (Comma separated)</label>
                              <input
                                type="text"
                                value={pageContentMap.stack?.items?.join(", ") || ""}
                                onChange={(e) => {
                                  const updated = { ...pageContentMap };
                                  updated.stack.items = e.target.value
                                    .split(",")
                                    .map((t: string) => t.trim())
                                    .filter(Boolean);
                                  setPageContentMap(updated);
                                }}
                                className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                              />
                            </div>
                          </div>
                        </>
                      )}

                      {/* CONTACT PAGE FORMS */}
                      {activePageSelector.id === "contact" && (
                        <>
                          <div className="rounded-2xl border border-hairline bg-white p-6 shadow-sm space-y-4">
                            <div className="flex items-center justify-between border-b border-zinc-100 pb-3">
                              <h3 className="font-bold text-paper">Contact Channels</h3>
                              <button
                                disabled={saving}
                                onClick={() => saveContentSection("details", "items", pageContentMap.details?.items)}
                                className="flex items-center gap-1.5 rounded-xl bg-violet px-3 py-1.5 text-xs font-bold text-white shadow-md hover:bg-violet-600 transition"
                              >
                                <Save size={13} /> Save Channels
                              </button>
                            </div>

                            {pageContentMap.details?.items?.map((item: CmsItem, idx: number) => (
                              <div key={idx} className="grid grid-cols-2 gap-4 border-b border-zinc-50 pb-3 last:border-0 last:pb-0">
                                <div className="space-y-1">
                                  <label className="text-xs font-semibold text-dim">{item.label} Value</label>
                                  <input
                                    type="text"
                                    value={item.value}
                                    onChange={(e) => {
                                      const updated = { ...pageContentMap };
                                      updated.details.items[idx].value = e.target.value;
                                      setPageContentMap(updated);
                                    }}
                                    className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                  />
                                </div>
                                <div className="space-y-1">
                                  <label className="text-xs font-semibold text-dim">{item.label} Note</label>
                                  <input
                                    type="text"
                                    value={item.note}
                                    onChange={(e) => {
                                      const updated = { ...pageContentMap };
                                      updated.details.items[idx].note = e.target.value;
                                      setPageContentMap(updated);
                                    }}
                                    className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                  />
                                </div>
                              </div>
                            ))}
                          </div>

                          <div className="rounded-2xl border border-hairline bg-white p-6 shadow-sm space-y-4">
                            <div className="flex items-center justify-between border-b border-zinc-100 pb-3">
                              <h3 className="font-bold text-paper">Contact FAQs</h3>
                              <div className="flex gap-2">
                                <button
                                  onClick={() => {
                                    const updated = { ...pageContentMap };
                                    if (!updated.faqs) updated.faqs = { items: [] };
                                    updated.faqs.items.push({ q: "New Question?", a: "New Answer." });
                                    setPageContentMap(updated);
                                  }}
                                  className="flex items-center gap-1.5 rounded-xl border border-zinc-200 px-3 py-1.5 text-xs font-bold text-zinc-600 hover:bg-zinc-50 transition"
                                >
                                  <Plus size={13} /> Add FAQ
                                </button>
                                <button
                                  disabled={saving}
                                  onClick={() => saveContentSection("faqs", "items", pageContentMap.faqs?.items)}
                                  className="flex items-center gap-1.5 rounded-xl bg-violet px-3 py-1.5 text-xs font-bold text-white shadow-md hover:bg-violet-600 transition"
                                >
                                  <Save size={13} /> Save FAQs
                                </button>
                              </div>
                            </div>

                            {pageContentMap.faqs?.items?.map((faq: CmsItem, idx: number) => (
                              <div key={idx} className="border border-zinc-200 rounded-xl p-4 bg-zinc-50/20 relative space-y-2">
                                <button
                                  onClick={() => {
                                    const updated = { ...pageContentMap };
                                    updated.faqs.items.splice(idx, 1);
                                    setPageContentMap(updated);
                                  }}
                                  className="absolute top-4 right-4 text-red-500 hover:text-red-700 transition"
                                >
                                  <Trash2 size={14} />
                                </button>
                                <div className="pr-8 space-y-1">
                                  <label className="text-[10px] font-bold uppercase tracking-wider text-dim">Question</label>
                                  <input
                                    type="text"
                                    value={faq.q}
                                    onChange={(e) => {
                                      const updated = { ...pageContentMap };
                                      updated.faqs.items[idx].q = e.target.value;
                                      setPageContentMap(updated);
                                    }}
                                    className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                  />
                                </div>
                                <div className="space-y-1">
                                  <label className="text-[10px] font-bold uppercase tracking-wider text-dim">Answer</label>
                                  <textarea
                                    rows={2}
                                    value={faq.a}
                                    onChange={(e) => {
                                      const updated = { ...pageContentMap };
                                      updated.faqs.items[idx].a = e.target.value;
                                      setPageContentMap(updated);
                                    }}
                                    className="w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-paper outline-none focus:border-violet"
                                  />
                                </div>
                              </div>
                            ))}
                          </div>
                        </>
                      )}
                    </>
                  )}
                </div>
              )}
            </div>
          </div>
        )}
      </section>
    </main>
  );
}
