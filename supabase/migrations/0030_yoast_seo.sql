-- ============================================================
-- 0030_yoast_seo.sql — Yoast SEO Pro parameters for website routes
-- ============================================================

alter table public.website_seo
  add column focus_keyphrase        text not null default '',
  add column canonical_url          text not null default '',
  add column meta_robots_noindex    boolean not null default false,
  add column meta_robots_nofollow   boolean not null default false,
  add column og_title               text not null default '',
  add column og_description         text not null default '',
  add column twitter_title          text not null default '',
  add column twitter_description    text not null default '',
  add column schema_type            text not null default 'WebPage';
