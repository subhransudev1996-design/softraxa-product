-- ============================================================
-- 0012_imagekit.sql — ImageKit upload authentication
--
-- Media (business logos etc.) is uploaded from the app directly to
-- ImageKit. The ImageKit PRIVATE key must never be shipped inside the
-- mobile app, so the upload signature is generated here, server-side:
-- the app calls get_imagekit_auth() and posts the returned
-- token/expire/signature to https://upload.imagekit.io/api/v1/files/upload.
--
-- (This replaces Supabase Storage for logos; the buckets from
-- 0011_storage.sql are now optional and only kept for future use.)
-- ============================================================

create extension if not exists pgcrypto;

create or replace function public.get_imagekit_auth()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  -- The key that used to be hardcoded here was exposed in source control
  -- and must be rotated. 0037_security_hardening.sql replaces this function
  -- with one that reads the key from Supabase Vault.
  v_private_key text := 'rotated-see-0037';
  v_token       text := gen_random_uuid()::text;
  v_expire      bigint := extract(epoch from now())::bigint + 3540; -- ImageKit max ~1h
  v_signature   text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  v_signature := encode(
    hmac(v_token || v_expire::text, v_private_key, 'sha1'), 'hex');
  return jsonb_build_object(
    'token', v_token,
    'expire', v_expire,
    'signature', v_signature
  );
end $$;

revoke execute on function public.get_imagekit_auth() from public, anon;
grant execute on function public.get_imagekit_auth() to authenticated;
