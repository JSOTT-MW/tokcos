-- Correction de submit_online_order : la 2e boucle itérait sur un `record`
-- (colonne `value`) mais appliquait l'opérateur JSON ->> directement sur le
-- record, ce qui provoquait « operator does not exist: record -> unknown ».
-- On accède désormais au jsonb via la colonne `value` du record (v_item.value).
-- create or replace conserve les GRANT existants (anon, authenticated).
create or replace function public.submit_online_order(
  p_store_id uuid,
  p_point_id uuid,
  p_client_name text,
  p_client_phone text,
  p_delivery_mode text,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item record;
  v_stock integer;
  v_reserved integer;
  v_price numeric;
  v_product_name text;
  v_sale_id uuid;
  v_total numeric := 0;
  v_line_total numeric;
begin
  if not exists (select 1 from public.stores where id = p_store_id and active = true)
     or not exists (select 1 from public.points_de_vente where id = p_point_id and store_id = p_store_id and active = true) then
    raise exception 'Store or point of sale is unavailable';
  end if;
  if coalesce(trim(p_client_name), '') = '' or coalesce(trim(p_client_phone), '') = '' then
    raise exception 'Client name and phone are required';
  end if;
  if coalesce(p_delivery_mode, '') not in ('Livraison boutique', 'Retrait au point') then
    raise exception 'Invalid delivery mode';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Order must contain at least one item';
  end if;
  perform public.assert_tokcos_register_open(p_store_id);

  for v_item in
    select (value->>'product_id')::uuid as product_id, sum((value->>'qty')::integer)::integer as qty
      from jsonb_array_elements(p_items)
     group by (value->>'product_id')::uuid
     order by (value->>'product_id')::uuid
  loop
    if v_item.qty is null or v_item.qty <= 0 then raise exception 'Order quantities must be positive'; end if;
    select quantity into v_stock from public.stock
     where store_id = p_store_id and point_id = p_point_id and product_id = v_item.product_id
     for update;
    if not found then raise exception 'Product is out of stock'; end if;
    select coalesce(sum(si.qty), 0)::integer into v_reserved
      from public.sales s join public.sale_items si on si.sale_id = s.id
     where s.store_id = p_store_id and s.point_id = p_point_id
       and s.channel = 'en_ligne' and s.status = 'vendu' and s.fulfilled = false
       and si.product_id = v_item.product_id;
    if v_stock - v_reserved < v_item.qty then raise exception 'Insufficient available stock'; end if;
    select name, price into v_product_name, v_price
      from public.products where id = v_item.product_id and store_id = p_store_id and active = true;
    if not found then raise exception 'Product is unavailable'; end if;
    v_total := v_total + v_price * v_item.qty;
  end loop;

  insert into public.sales (
    point_id, client_name, client_phone, delivery_mode, payment_method,
    total, status, channel, fulfilled, store_id
  ) values (
    p_point_id, trim(p_client_name), trim(p_client_phone), coalesce(nullif(trim(p_delivery_mode), ''), 'Sur place'),
    'À régler', v_total, 'vendu', 'en_ligne', false, p_store_id
  ) returning id into v_sale_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    select name, price into v_product_name, v_price
      from public.products
     where id = (v_item.value->>'product_id')::uuid and store_id = p_store_id and active = true;
    v_line_total := v_price * (v_item.value->>'qty')::integer;
    insert into public.sale_items (sale_id, product_id, product_name, qty, price, subtotal)
    values (v_sale_id, (v_item.value->>'product_id')::uuid, v_product_name, (v_item.value->>'qty')::integer, v_price, v_line_total);
  end loop;
  return v_sale_id;
end;
$$;
