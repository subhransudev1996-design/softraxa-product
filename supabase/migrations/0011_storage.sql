-- ============================================================
-- 0011_storage.sql — Supabase Storage buckets (OPTIONAL)
--
-- NOTE: media uploads now go to ImageKit (see 0012_imagekit.sql).
-- Running this file is harmless but no longer required; it is kept
-- only in case Supabase Storage is wanted later (e.g. product images).
-- ============================================================

insert into storage.buckets (id, name, public)
values ('logos', 'logos', true), ('product-images', 'product-images', true)
on conflict (id) do nothing;

-- Public read (images are embedded in invoices/apps via public URL)
create policy "public read logos" on storage.objects for select
  using (bucket_id = 'logos');
create policy "public read product images" on storage.objects for select
  using (bucket_id = 'product-images');

-- Owners write only inside their own business folder
create policy "own logo write" on storage.objects for insert
  with check (bucket_id = 'logos'
    and (storage.foldername(name))[1] = public.current_business_id()::text);
create policy "own logo update" on storage.objects for update
  using (bucket_id = 'logos'
    and (storage.foldername(name))[1] = public.current_business_id()::text);
create policy "own logo delete" on storage.objects for delete
  using (bucket_id = 'logos'
    and (storage.foldername(name))[1] = public.current_business_id()::text);

create policy "own product image write" on storage.objects for insert
  with check (bucket_id = 'product-images'
    and (storage.foldername(name))[1] = public.current_business_id()::text);
create policy "own product image update" on storage.objects for update
  using (bucket_id = 'product-images'
    and (storage.foldername(name))[1] = public.current_business_id()::text);
create policy "own product image delete" on storage.objects for delete
  using (bucket_id = 'product-images'
    and (storage.foldername(name))[1] = public.current_business_id()::text);
