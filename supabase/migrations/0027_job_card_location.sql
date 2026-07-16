-- ============================================================
-- 0027_job_card_location.sql — service/installation location on
-- job cards. For on-site jobs (e.g. a water-motor store installing
-- a motor at the customer's house, plumbing/fitting work, garment
-- delivery), the shop needs to record WHERE the work happens —
-- distinct from the customer's saved address.
-- ============================================================

alter table public.job_cards
  add column if not exists service_location text not null default '';

-- Reissue create_job_card (last defined in 0017) to accept the new field.
create or replace function public.create_job_card(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_job_id   uuid;
  v_job_no   text;
begin
  if v_business is null then raise exception 'No business for current user'; end if;
  v_job_no := public.next_doc_no(v_business, 'job_card', 'JOB');

  insert into public.job_cards
    (business_id, job_no, customer_id, customer_name, customer_phone, item_name, brand, model,
     serial_no, issue_description, item_condition, accessories_received, technician_name,
     estimated_cost, advance_amount, advance_mode, expected_delivery, customer_note,
     internal_note, warranty_days, service_location, created_by)
  values
    (v_business, v_job_no, (payload ->> 'customer_id')::uuid,
     coalesce(payload ->> 'customer_name', ''), coalesce(payload ->> 'customer_phone', ''),
     coalesce(payload ->> 'item_name', ''), coalesce(payload ->> 'brand', ''),
     coalesce(payload ->> 'model', ''), coalesce(payload ->> 'serial_no', ''),
     coalesce(payload ->> 'issue_description', ''), coalesce(payload ->> 'item_condition', ''),
     coalesce(payload ->> 'accessories_received', ''), coalesce(payload ->> 'technician_name', ''),
     coalesce((payload ->> 'estimated_cost')::numeric, 0),
     coalesce((payload ->> 'advance_amount')::numeric, 0),
     coalesce((payload ->> 'advance_mode')::public.payment_mode, 'cash'),
     nullif(payload ->> 'expected_delivery', '')::date,
     coalesce(payload ->> 'customer_note', ''), coalesce(payload ->> 'internal_note', ''),
     (payload ->> 'warranty_days')::integer,
     coalesce(payload ->> 'service_location', ''), auth.uid())
  returning id into v_job_id;

  insert into public.job_status_history (business_id, job_card_id, status, note, created_by)
  values (v_business, v_job_id, 'received', 'Job card created', auth.uid());

  perform public.log_audit('job_card.created', 'job_card', v_job_id::text,
    jsonb_build_object('job_no', v_job_no));
  return jsonb_build_object('id', v_job_id, 'job_no', v_job_no);
end $$;
