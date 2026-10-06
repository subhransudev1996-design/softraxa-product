-- ============================================================
-- 0065_supplier_edits_and_edited_cut_bills.sql — two fixes found while
-- testing 1.0.4 in the app.
--
-- A. Suppliers could not be changed.
-- guard_party_columns() (0043) runs on customers AND suppliers. One
-- branch read `tg_table_name = 'customers' and new.advance_amount ...`
-- in a single condition; PL/pgSQL plans the whole condition against the
-- row, and suppliers have no advance_amount, so every direct update of a
-- supplier (edit name/phone, delete = hide) failed with
--   record "new" has no field "advance_amount".
-- Adding a supplier still worked (the INSERT branch nests its check).
--
-- Same rules as 0043; the customer-only fields are read inside a nested
-- IF that only runs for customers.
--
-- B. Edited bills of cut-length products left pieces out of step.
-- A bill edit reverses every old line and books the new ones (0025).
-- Since 0064 the reversed length comes back as a piece, but the new
-- lines were never cut, so pieces ended up longer than stock (7 m bill
-- edited to 5 m: +7 m piece, nothing cut). update_invoice now cuts the
-- new lines from the best pieces, the same as create_invoice.
--
-- Run AFTER 0064.
-- ============================================================

create or replace function public.guard_party_columns()
returns trigger language plpgsql as $$
begin
  if public.is_direct_api_write() then
    if tg_op = 'INSERT' then
      new.due_amount := 0;
      if tg_table_name = 'customers' then new.advance_amount := 0; end if;
    else
      if new.due_amount is distinct from old.due_amount then
        raise exception 'Balances can only change through bills, purchases and payments'
          using errcode = '42501';
      end if;
      if tg_table_name = 'customers' then
        if new.advance_amount is distinct from old.advance_amount then
          raise exception 'Advances can only change through payments, returns and refunds'
            using errcode = '42501';
        end if;
      end if;
    end if;
  end if;

  if tg_table_name = 'customers' and auth.uid() is not null then
    if not public.has_permission('owner') then
      if tg_op = 'INSERT' then
        new.credit_unlimited := false;
        new.credit_limit := null;          -- store default, via normalize_customer_credit
      elsif new.credit_limit is distinct from old.credit_limit
         or new.credit_unlimited is distinct from old.credit_unlimited then
        raise exception 'Only the owner can change credit limits' using errcode = '42501';
      end if;
    end if;
    if not public.has_permission('can_edit_prices') then
      if tg_op = 'INSERT' then
        new.is_wholesale := false;
      elsif new.is_wholesale is distinct from old.is_wholesale then
        raise exception 'You don''t have permission to change a customer''s prices' using errcode = '42501';
      end if;
    end if;
  end if;
  return new;
end $$;

-- ------------------------------------------------------------
-- B. Bill edits cut the new lines (replaces 0061's wrapper; only the
--    piece loop is new).
-- ------------------------------------------------------------
create or replace function public.update_invoice(p_invoice_id uuid, payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v         jsonb;
  v_pricing jsonb;
  v_ex      jsonb;
  v_item    jsonb;
begin
  if (select invoice_type::text from public.invoices where id = p_invoice_id) = 'opening' then
    raise exception 'An opening balance can''t be edited — cancel it and enter it again';
  end if;
  v := public.update_invoice_impl(p_invoice_id, payload);
  perform public.mark_pack_lines(p_invoice_id, payload -> 'items');

  if (select invoice_type::text from public.invoices where id = p_invoice_id) <> 'estimate' then
    for v_item in select * from jsonb_array_elements(coalesce(payload -> 'items', '[]'::jsonb)) loop
      if nullif(v_item ->> 'variant_id', '') is null
         and nullif(v_item ->> 'product_id', '') is not null
         and coalesce((v_item ->> 'quantity')::numeric, 0) > 0
         and exists (select 1 from public.products
                     where id = (v_item ->> 'product_id')::uuid and track_pieces) then
        perform public.cut_best_pieces((v_item ->> 'product_id')::uuid,
                                       (v_item ->> 'quantity')::numeric, p_invoice_id);
      end if;
    end loop;
  end if;

  v_pricing := public.check_invoice_pricing(p_invoice_id);
  v_ex := public.sale_exceptions(p_invoice_id, v_pricing);
  perform public.settle_sale_exceptions(p_invoice_id, payload - 'approval_id' - 'offline_created', v_ex);
  return v;
end $$;
