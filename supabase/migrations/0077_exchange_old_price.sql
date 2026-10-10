-- ============================================================
-- 0077: An exchanged item at the price the customer paid.
--
-- A customer swaps a kurta for another size. Its price has gone up since,
-- but the shop gives the new one at the price paid before, so the swap
-- costs nothing. Until now the price check (check_invoice_pricing) saw
-- that as a reduction from today's price: staff without enough discount
-- limit were refused, the owner was warned.
--
-- Now, while create_exchange makes the replacement bill, a product that
-- is also being returned has an extra allowed price: what the customer
-- paid for it (the return line's value per unit, after the bill's
-- discounts). The default becomes the lower of that and today's price,
-- with price source 'exchange'. Nothing is taken from the app: the
-- prices come from the return just made in the same transaction, which
-- create_exchange names in a transaction-local setting.
--
-- invoice_price_lines is 0061's with the "paid" price added;
-- create_exchange is 0042's with the setting around create_invoice.
-- ============================================================

create or replace function public.invoice_price_lines(p_invoice uuid)
returns table (id uuid, quantity numeric, eff numeric, def numeric, def_source text,
               retail numeric, wholesale numeric, customer numeric)
language sql stable security definer set search_path = public as $$
  with i as (
    select inv.id, inv.business_id, inv.invoice_type, inv.customer_id,
           coalesce((select c.is_wholesale from public.customers c where c.id = inv.customer_id), false)
             as wholesale_customer
    from public.invoices inv where inv.id = p_invoice),
  -- During an exchange: what the customer paid per unit for each product
  -- coming back (the lowest, if it came back on more than one line).
  paid as (
    select sri.product_id, min(sri.line_total / nullif(sri.quantity, 0)) as paid
    from i
    join public.sale_returns sr
      on sr.id = nullif(current_setting('app.exchange_return', true), '')::uuid
     and sr.business_id = i.business_id
    join public.sale_return_items sri on sri.sale_return_id = sr.id
    where sri.product_id is not null and sri.quantity > 0
    group by sri.product_id),
  base as (
    select ii.id, ii.quantity, ii.product_id, ii.variant_id,
           (ii.quantity * ii.unit_price - ii.discount_amount) / nullif(ii.quantity, 0)
             * case when i.invoice_type = 'gst' then 1 + ii.gst_rate / 100 else 1 end as eff,
           -- a pack line: the pack price spread over its pieces
           case when ii.sold_as_pack and ii.variant_id is null
                     and coalesce(p.pack_price, 0) > 0 and coalesce(p.conversion_factor, 0) > 0
                then p.pack_price / p.conversion_factor end as pack_unit,
           ii.sold_as_pack,
           nullif(coalesce(pv.selling_price, p.selling_price), 0) as retail,
           nullif(p.wholesale_price, 0) as wholesale,
           p.wholesale_min_qty,
           cp.price as customer,
           i.wholesale_customer,
           pd.paid
    from i
    join public.invoice_items ii on ii.invoice_id = i.id
    left join public.products p on p.id = ii.product_id
    left join public.product_variants pv on pv.id = ii.variant_id
    left join public.customer_prices cp
      on cp.customer_id = i.customer_id and cp.product_id = ii.product_id
     and cp.variant_id is not distinct from ii.variant_id
    left join paid pd on pd.product_id = ii.product_id),
  l as (
    select b.id, b.quantity, b.eff, b.paid,
           coalesce(b.pack_unit, b.retail) as retail,
           case when b.sold_as_pack then null else b.wholesale end as wholesale,
           b.wholesale_min_qty,
           case when b.pack_unit is not null and b.customer >= b.pack_unit then null
                else b.customer end as customer,
           b.wholesale_customer,
           sum(case when b.sold_as_pack then 0 else b.quantity end)
             over (partition by b.product_id, b.variant_id) as product_qty
    from base b),
  t as (
    select l.*, (l.wholesale is not null
                 and (l.wholesale_customer
                      or (l.wholesale_min_qty is not null and l.product_qty >= l.wholesale_min_qty))) as ws
    from l),
  d as (
    select t.*,
           case when t.customer is not null then t.customer when t.ws then t.wholesale else t.retail end
             as normal_def,
           case when t.customer is not null then 'customer' when t.ws then 'wholesale'
                when t.retail is not null then 'retail' else '' end as normal_source
    from t)
  select d.id, d.quantity, d.eff,
         case when d.paid is not null and (d.normal_def is null or d.paid < d.normal_def)
              then d.paid else d.normal_def end,
         case when d.paid is not null and (d.normal_def is null or d.paid < d.normal_def)
              then 'exchange' else d.normal_source end,
         d.retail, d.wholesale, d.customer
  from d;
$$;
revoke execute on function public.invoice_price_lines(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- create_exchange (as 0042) + names the return while the
-- replacement bill is made
-- ------------------------------------------------------------
create or replace function public.create_exchange(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business    uuid := public.current_business_id();
  v_request     uuid := (payload ->> 'request_id')::uuid;
  v_prior       jsonb;
  v_orig        record;
  v_customer    uuid;
  v_ret         jsonb;
  v_return_id   uuid;
  v_credit      numeric(14,2);
  v_sale        jsonb := payload -> 'sale';
  v_new         jsonb;
  v_new_id      uuid;
  v_new_due     numeric(14,2);
  v_use         numeric(14,2) := 0;
  v_left        numeric(14,2);
  v_refund      numeric(14,2) := 0;
  v_advance     numeric(14,2) := 0;
  v_excess      text := coalesce(payload ->> 'excess', 'advance');
  v_refund_mode public.payment_mode := coalesce((payload ->> 'refund_mode')::public.payment_mode, 'cash');
  v_result      jsonb;
begin
  if v_business is null then raise exception 'No business for current user'; end if;
  if v_request is null then raise exception 'Missing exchange request id'; end if;

  -- Idempotent: a retried request gets the first result back.
  select result into v_prior from public.exchanges
    where business_id = v_business and request_id = v_request;
  if v_prior is not null then
    return v_prior || jsonb_build_object('already_done', true);
  end if;

  perform public.assert_can('can_manage_returns');
  perform public.assert_can('can_create_invoice');

  select * into v_orig from public.invoices
    where id = (payload -> 'return' ->> 'invoice_id')::uuid and business_id = v_business;
  if v_orig.id is null then raise exception 'An exchange starts from the original bill'; end if;
  v_customer := v_orig.customer_id;

  if v_sale is null or jsonb_array_length(coalesce(v_sale -> 'items', '[]'::jsonb)) = 0 then
    raise exception 'Add the replacement items';
  end if;
  if coalesce(v_sale ->> 'invoice_type', 'gst') = 'estimate' then
    raise exception 'The replacement must be a bill, not an estimate';
  end if;
  if v_refund_mode = 'credit' then v_refund_mode := 'cash'; end if;

  -- 1. The return (credit kept for the replacement).
  v_ret := public.create_sale_return(
    (payload -> 'return') || jsonb_build_object('exchange', true, 'refund_amount', 0));
  v_return_id := (v_ret ->> 'id')::uuid;
  v_credit := coalesce((v_ret ->> 'exchange_credit')::numeric, 0);

  -- 2. The replacement bill, for the same customer as the original. An
  --    item that is also coming back may be priced at what was paid for
  --    it (0077): the price check reads this return's lines.
  v_sale := (v_sale - 'local_id' - 'offline_created')
            || jsonb_build_object('customer_id', v_customer);
  if v_customer is not null then
    v_sale := v_sale || jsonb_build_object('customer_name',
      (select name from public.customers where id = v_customer));
  end if;
  perform set_config('app.exchange_return', v_return_id::text, true);
  v_new := public.create_invoice(v_sale);
  perform set_config('app.exchange_return', '', true);
  v_new_id := (v_new ->> 'id')::uuid;

  -- 3. Return credit pays the replacement.
  select due_amount into v_new_due from public.invoices where id = v_new_id for update;
  v_use := least(v_credit, greatest(v_new_due, 0));
  if v_use > 0 then
    update public.invoices set
      paid_amount = paid_amount + v_use,
      payment_status = public.doc_payment_status(total, paid_amount + v_use, credit_amount)
      where id = v_new_id;
    insert into public.invoice_payments
      (business_id, invoice_id, amount, payment_mode, note, sale_return_id)
    values (v_business, v_new_id, v_use, 'other', 'Exchange credit from ' || (v_ret ->> 'return_no'),
            v_return_id);
    if v_customer is not null then
      update public.customers set due_amount = due_amount - v_use
        where id = v_customer and business_id = v_business;
    end if;
  end if;

  if v_customer is null and v_new_due - v_use > 0.005 then
    raise exception 'Collect the full difference (%) for a walk-in exchange', v_new_due - v_use;
  end if;

  -- 4. Credit left over: refund now, or keep as the customer's advance.
  v_left := v_credit - v_use;
  if v_left > 0.005 then
    if v_customer is not null and v_excess = 'advance' then
      perform public.post_customer_advance(v_business, v_customer, v_left, 'return_credit',
        p_sale_return_id => v_return_id, p_invoice_id => v_orig.id,
        p_note => 'Exchange ' || (v_ret ->> 'return_no'));
      v_advance := v_left;
    else
      update public.sale_returns set refund_amount = v_left, refund_mode = v_refund_mode
        where id = v_return_id;
      v_refund := v_left;
    end if;
  end if;

  v_result := jsonb_build_object(
    'return_id', v_return_id, 'return_no', v_ret ->> 'return_no',
    'invoice_id', v_new_id, 'invoice_no', v_new ->> 'invoice_no',
    'return_value', (v_ret ->> 'total')::numeric,
    'applied_to_original', (v_ret ->> 'applied_to_bill')::numeric,
    'credit', v_credit, 'credit_used', v_use,
    'replacement_total', (v_new ->> 'total')::numeric,
    'refund', v_refund, 'advance', v_advance);

  insert into public.exchanges
    (business_id, request_id, original_invoice_id, sale_return_id, new_invoice_id, result, created_by)
  values (v_business, v_request, v_orig.id, v_return_id, v_new_id, v_result, auth.uid());

  perform public.log_audit('exchange.created', 'invoice', v_orig.id::text, v_result);
  return v_result;
end $$;

revoke execute on function public.create_exchange(jsonb) from public, anon;
grant execute on function public.create_exchange(jsonb) to authenticated;
