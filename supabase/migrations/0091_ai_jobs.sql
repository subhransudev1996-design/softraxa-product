-- ============================================================
-- 0091_ai_jobs.sql — Dukania AI: services and job cards (repairs).
--
-- ai_job_action(p) runs one job-card action for the AI assistant through
-- the app's own functions, so their checks apply unchanged:
--   kind 'create_job'  → create_job_card
--   kind 'add_items'   → add_job_card_item per line (parts come out of stock)
--   kind 'estimate'    → create_job_estimate
--   kind 'decision'    → record_estimate_decision (the customer's answer)
--   kind 'status'      → update_job_status
--   kind 'close'       → close_job_card (the bill) and, by default, delivered
-- Lines may name a product (part), a service (labour) or an approved
-- estimate line; missing names, prices (before GST, as the app's job cards
-- use), GST and HSN/SAC come from the product or service — a part's price
-- is its selling price without GST (partPriceExGst in the app).
--
-- p.ref (a uuid from the preview) is kept in ai_action_log: the same ref
-- again returns what was done instead of doing it twice.
-- ============================================================

create table if not exists public.ai_action_log (
  business_id uuid not null references public.businesses(id) on delete cascade,
  ref         uuid not null,
  kind        text not null,
  result      jsonb not null default '{}'::jsonb,
  created_by  uuid,
  created_at  timestamptz not null default now(),
  primary key (business_id, ref)
);
alter table public.ai_action_log enable row level security;
revoke all on public.ai_action_log from public, anon, authenticated;

alter table public.job_cards add column if not exists created_via text not null default 'app';
alter table public.services  add column if not exists created_via text not null default 'app';
alter table public.job_cards alter column created_via set default public.request_source();
alter table public.services  alter column created_via set default public.request_source();

-- One job / estimate line with the product's or service's defaults filled in.
create or replace function public.ai_job_line(p_business uuid, l jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_uuid constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_prod public.products;
  v_var  public.product_variants;
  v_svc  public.services;
  v_type text := nullif(l ->> 'item_type', '');
begin
  if coalesce(l ->> 'product_id', '') ~ v_uuid then
    select * into v_prod from public.products
      where id = (l ->> 'product_id')::uuid and business_id = p_business and is_active;
    if v_prod.id is null then raise exception 'Part not found in your shop'; end if;
    if v_prod.has_variants then
      if coalesce(l ->> 'variant_id', '') !~ v_uuid then
        raise exception '% comes in variants (%): say which one', v_prod.name,
          (select string_agg(name, ', ' order by name) from public.product_variants
           where product_id = v_prod.id and is_active);
      end if;
      select * into v_var from public.product_variants
        where id = (l ->> 'variant_id')::uuid and product_id = v_prod.id;
      if v_var.id is null then raise exception 'That variant of % wasn''t found', v_prod.name; end if;
    end if;
    v_type := coalesce(v_type, 'part');
  elsif coalesce(l ->> 'service_id', '') ~ v_uuid then
    select * into v_svc from public.services
      where id = (l ->> 'service_id')::uuid and business_id = p_business and is_active;
    if v_svc.id is null then raise exception 'Service not found in your shop'; end if;
    v_type := coalesce(v_type, 'labor');
  end if;
  v_type := coalesce(v_type, 'labor');
  if v_type not in ('part', 'labor') then raise exception 'item_type must be part or labor'; end if;
  if coalesce(nullif(l ->> 'quantity', '')::numeric, 1) <= 0 then
    raise exception 'The quantity must be more than 0';
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'item_type', v_type,
    'product_id', v_prod.id,
    'variant_id', v_var.id,
    'service_id', v_svc.id,
    'name', coalesce(nullif(btrim(l ->> 'name'), ''),
                     v_prod.name || coalesce(' (' || v_var.name || ')', ''), v_svc.name),
    'hsn_code', coalesce(nullif(l ->> 'hsn_code', ''), v_prod.hsn_code, v_svc.sac_code, ''),
    'quantity', coalesce(nullif(l ->> 'quantity', '')::numeric, 1),
    'unit_price', coalesce(nullif(l ->> 'unit_price', '')::numeric,
                           round(coalesce(v_var.selling_price, v_prod.selling_price) / (1 + v_prod.gst_rate / 100), 2),
                           v_svc.price),
    'gst_rate', coalesce(nullif(l ->> 'gst_rate', '')::numeric, v_prod.gst_rate, v_svc.gst_rate, 0),
    'cost_price', coalesce(nullif(v_var.purchase_price, 0), v_prod.purchase_price)));
end $$;

create or replace function public.ai_job_action(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_uuid     constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_kind     text := coalesce(p ->> 'kind', '');
  v_ref      uuid;
  v_done     jsonb;
  v_job      public.job_cards;
  v_line     jsonb;
  v_lines    jsonb := '[]'::jsonb;
  v_res      jsonb;
  v_out      jsonb := '[]'::jsonb;
  v_est      uuid;
  v_biz      public.businesses;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  perform public.assert_can('can_manage_services');
  perform public.assert_feature('service_module', 'Services & job cards');
  if v_kind not in ('create_job', 'add_items', 'estimate', 'decision', 'status', 'close') then
    raise exception 'Unknown job action %', v_kind;
  end if;
  if coalesce(p ->> 'ref', '') !~ v_uuid then
    raise exception 'Preview it first and confirm with its ref';
  end if;
  v_ref := (p ->> 'ref')::uuid;
  select result into v_done from public.ai_action_log where business_id = v_business and ref = v_ref;
  if v_done is not null then return v_done || jsonb_build_object('already_saved', true); end if;

  if v_kind <> 'create_job' then
    if coalesce(p ->> 'job_id', '') !~ v_uuid then raise exception 'Give the job_id from list_jobs'; end if;
    select * into v_job from public.job_cards where id = (p ->> 'job_id')::uuid and business_id = v_business;
    if v_job.id is null then raise exception 'Job card not found in your shop'; end if;
  end if;

  if v_kind = 'create_job' then
    v_res := public.create_job_card(p -> 'job');
    v_res := v_res || jsonb_build_object('job_id', v_res ->> 'id');

  elsif v_kind = 'add_items' then
    if v_job.invoice_id is not null then raise exception 'Job % is already billed', v_job.job_no; end if;
    if jsonb_typeof(p -> 'lines') is distinct from 'array' or jsonb_array_length(p -> 'lines') = 0 then
      raise exception 'Say what work or parts to add';
    end if;
    for v_line in select * from jsonb_array_elements(p -> 'lines') loop
      -- A job with an approved estimate takes only its approved lines
      -- (guard_job_item_scope): a part or service named here is that line.
      if coalesce(v_line ->> 'estimate_line_id', '') !~ v_uuid and v_job.estimate_required then
        v_lines := public.ai_job_line(v_business, v_line);
        select jsonb_build_object('estimate_line_id', el.id) || v_line into v_line
          from public.job_estimate_lines el
          where el.estimate_id = public.current_job_estimate(v_job.id) and el.approved
            and el.item_type = v_lines ->> 'item_type'
            and el.product_id is not distinct from (v_lines ->> 'product_id')::uuid
            and el.variant_id is not distinct from (v_lines ->> 'variant_id')::uuid
            and (el.item_type = 'part' or el.service_id is not distinct from (v_lines ->> 'service_id')::uuid
                 or lower(el.name) = lower(v_lines ->> 'name'))
          order by el.line_no limit 1;
        if coalesce(v_line ->> 'estimate_line_id', '') !~ v_uuid then
          raise exception '"%" isn''t in the customer''s approved estimate — make a new estimate for it first',
            v_lines ->> 'name';
        end if;
      end if;
      if coalesce(v_line ->> 'estimate_line_id', '') ~ v_uuid then
        v_res := public.add_job_card_item(jsonb_build_object('job_card_id', v_job.id,
          'estimate_line_id', v_line ->> 'estimate_line_id',
          'quantity', coalesce(nullif(v_line ->> 'quantity', '')::numeric,
                               (select quantity from public.job_estimate_lines where id = (v_line ->> 'estimate_line_id')::uuid))));
      else
        v_res := public.add_job_card_item(public.ai_job_line(v_business, v_line)
                                          || jsonb_build_object('job_card_id', v_job.id));
      end if;
      v_out := v_out || jsonb_build_array(v_res);
    end loop;
    v_res := jsonb_build_object('added', v_out,
      'job_total', (select coalesce(sum(line_total), 0) from public.job_card_items where job_card_id = v_job.id));

  elsif v_kind = 'estimate' then
    for v_line in select * from jsonb_array_elements(coalesce(p -> 'lines', '[]'::jsonb)) loop
      v_lines := v_lines || jsonb_build_array(public.ai_job_line(v_business, v_line) - 'cost_price');
    end loop;
    v_res := public.create_job_estimate(v_job.id, v_lines, coalesce(p ->> 'note', ''));

  elsif v_kind = 'decision' then
    v_est := case when coalesce(p ->> 'estimate_id', '') ~ v_uuid then (p ->> 'estimate_id')::uuid end;
    if v_est is null then
      select id into v_est from public.job_estimates
        where job_card_id = v_job.id and status = 'awaiting_approval' order by version desc limit 1;
      if v_est is null then raise exception 'Job % has no estimate waiting for an answer', v_job.job_no; end if;
    end if;
    v_res := public.record_estimate_decision(v_est,
      case when p ->> 'decision' = 'rejected' then 'rejected' else 'approved' end,
      coalesce(p ->> 'customer_name', v_job.customer_name), coalesce(nullif(p ->> 'channel', ''), 'phone'),
      case when p ->> 'decision' = 'some'
           then array(select jsonb_array_elements_text(coalesce(p -> 'line_ids', '[]'::jsonb))::uuid) end,
      null, coalesce(p ->> 'note', ''));

  elsif v_kind = 'status' then
    if p ->> 'status' = 'delivered' and v_job.invoice_id is null then
      raise exception 'Bill the job first (close_job) — it then becomes delivered';
    end if;
    perform public.update_job_status(v_job.id, (p ->> 'status')::public.job_status, coalesce(p ->> 'note', ''));
    v_res := jsonb_build_object('job_no', v_job.job_no, 'status', p ->> 'status');

  elsif v_kind = 'close' then
    select * into v_biz from public.businesses where id = v_business;
    v_res := public.close_job_card(v_job.id, jsonb_strip_nulls(jsonb_build_object(
      'paid_amount', coalesce(nullif(p ->> 'paid', '')::numeric, 0),
      'payment_mode', coalesce(nullif(p ->> 'payment_mode', ''), 'cash'),
      'invoice_type', case when v_biz.tax_preference = 'gst' and public.feature_enabled('gst_billing')
                           then 'gst' else 'non_gst' end,
      'warranty_days', nullif(p ->> 'warranty_days', '')::integer)));
    if coalesce((p ->> 'deliver')::boolean, true) then
      perform public.update_job_status(v_job.id, 'delivered', 'Billed ' || (v_res ->> 'invoice_no'));
    end if;
  end if;

  insert into public.ai_action_log (business_id, ref, kind, result, created_by)
    values (v_business, v_ref, v_kind, coalesce(v_res, '{}'::jsonb), auth.uid());
  return coalesce(v_res, '{}'::jsonb);
end $$;

revoke execute on function public.ai_job_line(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.ai_job_action(jsonb) from public, anon;
grant execute on function public.ai_job_action(jsonb) to authenticated;
