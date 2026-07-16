# Dukania (by SOFTRAXA) — GST Billing & Stock Management

A mobile-first inventory, billing, and stock management system for local Indian shops (mobile, garment, hardware). See [prd.md](prd.md) for full requirements and [PLAN.md](PLAN.md) for the implementation plan and progress.

## Structure

| Path | What it is |
|---|---|
| `apps/mobile` | Flutter customer app (shop owners) |
| `apps/admin` | Next.js admin panel (software owner) |
| `supabase/migrations` | Numbered SQL migrations — run in order in the Supabase SQL editor |

## Getting started

1. **Database:** Open your Supabase project → SQL Editor → run each file in `supabase/migrations/` in numeric order.
2. **Mobile app:**
   ```
   cd apps/mobile
   copy .env.example .env   # then paste your SUPABASE_URL and SUPABASE_ANON_KEY
   flutter pub get
   flutter run
   ```
3. **Admin panel:**
   ```
   cd apps/admin
   copy .env.example .env.local   # needs service-role key (server-side only)
   npm install
   npm run dev
   ```
