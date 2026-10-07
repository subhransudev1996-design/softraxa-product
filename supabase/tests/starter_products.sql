-- Read-only check after running 0067-0072. Changes nothing.
-- Every row must say PASS. Expected counts (before any admin edits):
-- grocery 1122, stationery 433, cosmetics 504, mobile 610, mobile_repair 357,
-- garment 854, hardware 1736, electrical 1520, car_workshop 1012, bike_garage 697.
-- Counts can differ a little: products shops added themselves are counted
-- too, and a starter name a shop had already added is left as it was.
with c as (
  select business_type, count(*) n from public.master_products group by 1
), want(t, min_n) as (values
  ('grocery',1000),('stationery',400),('cosmetics',450),('mobile',550),
  ('mobile_repair',300),('garment',800),('hardware',1600),('electrical',1400),
  ('car_workshop',900),('bike_garage',600))
select 'count ' || w.t as check_name, coalesce(c.n,0) as found, w.min_n as at_least,
       case when coalesce(c.n,0) >= w.min_n then 'PASS' else 'FAIL' end as result
from want w left join c on c.business_type = w.t
union all
select 'bad GST rate', count(*), 0,
       case when count(*)=0 then 'PASS' else 'FAIL' end
from public.master_products where gst_rate not in (0,0.25,3,5,12,18,28,40)
union all
select 'bad HSN (not 4/6/8 digits)', count(*), 0,
       case when count(*)=0 then 'PASS' else 'FAIL' end
from public.master_products where hsn_code <> '' and hsn_code !~ '^[0-9]{4}([0-9]{2}){0,2}$'
union all
select 'starter products with no category', count(*), 0,
       case when count(*)=0 then 'PASS' else 'FAIL' end
from public.master_products where source = 'softraxa' and btrim(category)=''
union all
select 'shop-added products with no category (fine)', count(*), 0, 'INFO'
from public.master_products where source = 'shop' and btrim(category)=''
union all
select 'duplicate names', count(*), 0,
       case when count(*)=0 then 'PASS' else 'FAIL' end
from (select master_name_key(name) k from public.master_products group by 1 having count(*)>1) d
union all
select 'seeded rows hidden or pending', count(*), 0, 'INFO'
from public.master_products where source = 'softraxa' and status <> 'published'
union all
select 'seeded rows marked verified (should be 0)', count(*), 0,
       case when count(*)=0 then 'PASS' else 'FAIL' end
from public.master_products where source = 'softraxa' and verified;
