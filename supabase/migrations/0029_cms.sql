-- ============================================================
-- 0029_cms.sql — Website CMS Content and SEO metadata
-- ============================================================

-- ---------- SEO Metadata ----------
create table public.website_seo (
  id             uuid primary key default gen_random_uuid(),
  path           text not null unique, -- e.g. '/', '/about', '/contact', '/dukania', '/services', '/products'
  title          text not null,
  description    text not null,
  keywords       text[] not null default '{}'::text[],
  og_image       text,
  structured_data jsonb not null default '{}'::jsonb,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create trigger trg_website_seo_updated before update on public.website_seo
  for each row execute function public.set_updated_at();

-- ---------- Page Content ----------
create table public.website_content (
  id          uuid primary key default gen_random_uuid(),
  page        text not null, -- e.g. 'home', 'about', 'contact', 'dukania', 'services', 'products'
  section     text not null, -- e.g. 'hero', 'story', 'values', 'compare', 'builtin', 'faqs'
  key         text not null, -- e.g. 'content', 'items', 'list'
  value       jsonb not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (page, section, key)
);

create trigger trg_website_content_updated before update on public.website_content
  for each row execute function public.set_updated_at();

-- ---------- RLS Policies ----------
alter table public.website_seo enable row level security;
create policy "allow public read seo" on public.website_seo for select using (true);
create policy "admin manage seo" on public.website_seo for all
  using (public.is_admin()) with check (public.is_admin());

alter table public.website_content enable row level security;
create policy "allow public read content" on public.website_content for select using (true);
create policy "admin manage content" on public.website_content for all
  using (public.is_admin()) with check (public.is_admin());

-- ---------- Initial Seed Data ----------

-- 1. SEO Seeds
insert into public.website_seo (path, title, description, keywords) values
('/', 'Softraxa — software for businesses that don''t stop moving', 'Softraxa is a software agency building practical, offline-first business software. Dukania, our flagship product, runs billing, stock and reporting for real shops across India.', array['offline-first', 'flutter', 'supabase', 'billing software', 'inventory system']),
('/about', 'About — Softraxa', 'Softraxa is a small software studio building practical, offline-first business software for India — makers of Dukania.', array['software studio', 'odisha tech', 'offline mobile apps']),
('/contact', 'Contact — Softraxa', 'Get in touch with Softraxa. Book a free demo for Dukania, or talk to us about custom offline-first billing & inventory software.', array['contact softraxa', 'dukania demo', 'custom software india']),
('/dukania', 'Dukania — inventory & billing that puts you in control | Softraxa', 'Dukania is Softraxa''s offline-first POS and inventory app: billing, stock and expiry tracking, staff roles, reports and low-stock alerts. Android & Windows.', array['pos app', 'gst billing app', 'offline billing', 'stock tracking']),
('/services', 'Services — Softraxa software agency', 'What Softraxa builds: product engineering, offline-first mobile apps, business software, data & reporting, admin tooling and ongoing support.', array['custom app development', 'offline mobile apps', 'supabase dashboard nextjs']),
('/products', 'Products — Softraxa', 'Explore the software products built by Softraxa, including Dukania, our offline-first inventory & stock management software.', array['business apps', 'dukania billing']),
('/services/custom-solutions', 'Custom Solutions — Softraxa', 'Custom billing, POS, inventory, field-sales, and dashboard software shaped around your business workflows.', array['custom pos', 'field sales software', 'custom business software']);

-- 2. Website Content Seeds (Home Page)
insert into public.website_content (page, section, key, value) values
('home', 'hero', 'content', '{
  "badge": "Software agency · India",
  "title": "Software that runs the business, not just the browser.",
  "description": "Softraxa builds practical, offline-first business software. Our flagship product, Dukania, handles billing, stock and reporting for real shops across India — online or off.",
  "primary_cta": "Book a free demo",
  "secondary_cta": "See Dukania"
}'::jsonb),
('home', 'stats', 'items', '[
  { "value": 100, "suffix": "%", "label": "Works offline" },
  { "value": 30, "suffix": "d", "label": "Expiry alert window" },
  { "value": 3, "suffix": "+", "label": "Staff roles built in" },
  { "value": 2, "suffix": "", "label": "Platforms (Android · Windows)" }
]'::jsonb);

-- 3. Website Content Seeds (About Page)
insert into public.website_content (page, section, key, value) values
('about', 'hero', 'content', '{
  "eyebrow": "About",
  "title": "We''re Softraxa.",
  "lead": "A small software studio building practical, offline-first business software for the way work actually happens in India."
}'::jsonb),
('about', 'story', 'paragraphs', '[
  "Softraxa started from a simple frustration: most business software assumes a fast, always-on internet connection and a person sitting at a desk. Real shops don''t work like that. The connection drops. The counter is busy. Staff need an answer in seconds.",
  "So we build software that survives bad connections and keeps up with a busy shop floor — starting with Dukania, our offline-first billing and inventory app. Everything we make is held to the same bar: it works offline, it''s priced for real margins, and the people who built it are the ones who support it.",
  "We''re a small, focused team. That''s deliberate — it''s how one group of people can own a whole product, end to end, and stay accountable for it."
]'::jsonb),
('about', 'values', 'items', '[
  { "title": "Offline-first, always", "body": "We build for the real world, where the network drops mid-sale. The software has to keep working anyway.", "icon": "WifiOff" },
  { "title": "India-first", "body": "Priced and designed for Indian shops and businesses — their margins, their workflows, their languages.", "icon": "IndianRupee" },
  { "title": "Direct support", "body": "You talk to the people who wrote the code. No call centre, no ticket lottery.", "icon": "MessageCircle" },
  { "title": "Ship, then improve", "body": "We''d rather put working software in your hands early and improve it with you than disappear for six months.", "icon": "Compass" }
]'::jsonb);

-- 4. Website Content Seeds (Dukania Page)
insert into public.website_content (page, section, key, value) values
('dukania', 'hero', 'content', '{
  "eyebrow": "Softraxa product",
  "title": "Inventory & billing that puts you in control.",
  "lead": "Know exactly what''s in stock, bill online or completely offline, and reorder before you run out — with Dukania.",
  "primary_cta": "Book a free demo",
  "secondary_cta": "Watch it work"
}'::jsonb),
('dukania', 'compare', 'items', '[
  "Bill a customer with no internet",
  "Spot low stock instantly",
  "Track expiry dates automatically",
  "GST reports in one tap",
  "Staff logins with limited access",
  "Sync across desktop and mobile"
]'::jsonb),
('dukania', 'builtin', 'items', '[
  { "title": "Barcode scanning", "body": "Scan to bill and to add stock — no add-on hardware app to wire up.", "icon": "ScanLine" },
  { "title": "Reports & GST", "body": "Sales, profit, stock value and GST, all exportable as a clean PDF.", "icon": "BarChart3" },
  { "title": "Android + Windows", "body": "Run it on the counter desktop and in your pocket, in sync.", "icon": "Boxes" }
]'::jsonb),
('dukania', 'faqs', 'items', '[
  { "q": "Does it really work with no internet?", "a": "Yes. Billing, stock updates and job cards all work fully offline. Once a connection is available, everything syncs automatically in the background — no manual step." },
  { "q": "Is my shop''s data secure?", "a": "Every business''s data is isolated at the database level using row-level security, so one shop''s data is never visible to another — even on shared infrastructure." },
  { "q": "What platforms does Dukania run on?", "a": "Dukania runs on Android today, with a Windows desktop build for back-office use. Get in touch if you need something else." },
  { "q": "Can my staff have their own logins?", "a": "Yes. You can create separate logins for staff with different levels of access, so a billing assistant sees only what they need and the owner keeps full control." },
  { "q": "Does it handle GST?", "a": "Yes — GST on bills and services, plus a GST report showing output and input tax by rate. You can also raise non-GST bills, cash memos and estimates." }
]'::jsonb);

-- 5. Website Content Seeds (Services Page)
insert into public.website_content (page, section, key, value) values
('services', 'hero', 'content', '{
  "eyebrow": "Services",
  "title": "What we build.",
  "lead": "Softraxa is a small studio that ships complete products. Here''s the work we take on, end to end."
}'::jsonb),
('services', 'list', 'items', '[
  {
    "title": "Product engineering",
    "body": "We design and build the whole product as one system — mobile app, backend and admin panel — so nothing falls through the cracks between three separate vendors.",
    "points": ["End-to-end architecture", "Mobile + web + backend", "One team, one roadmap"],
    "icon": "Layers"
  },
  {
    "title": "Offline-first mobile apps",
    "body": "Apps that keep working with no signal. Local-first data, background sync and conflict handling built in from the start — not bolted on later.",
    "points": ["Works fully offline", "Automatic background sync", "Android & Windows builds"],
    "icon": "WifiOff"
  },
  {
    "title": "Business software (POS & inventory)",
    "body": "Billing, stock, purchases, returns and job cards modelled on how a real business runs its day — the domain we know best from building Dukania.",
    "points": ["Billing & POS", "Stock + expiry tracking", "Returns & purchases"],
    "icon": "Store"
  },
  {
    "title": "Data & reporting",
    "body": "Turn raw sales and stock data into reports people actually use — daily takings, top products, expenses — and export them cleanly when needed.",
    "points": ["Sales & stock reports", "Expense tracking", "PDF export"],
    "icon": "BarChart3"
  },
  {
    "title": "Admin & operations tooling",
    "body": "The back-office half of a product — client management, plans, subscriptions and support queues — so you can run the business, not just ship the app.",
    "points": ["Client & plan management", "Subscriptions & billing", "Support workflows"],
    "icon": "Settings"
  },
  {
    "title": "Support & maintenance",
    "body": "A direct line to the people who built your software. Fixes, updates and new features handled by the same team — not passed to a stranger.",
    "points": ["Direct WhatsApp-speed support", "Ongoing updates", "New features on request"],
    "icon": "LifeBuoy"
  }
]'::jsonb),
('services', 'stack', 'items', '["Flutter", "Supabase", "Next.js", "Postgres", "Edge Functions", "Row-level security"]'::jsonb);
