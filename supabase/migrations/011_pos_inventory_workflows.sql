-- Atomic point-of-sale, stock-count, and delivery operations for TOK'COS.

create or replace function public.authorize_tokcos_point(p_point_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_profile_point_id uuid;
  v_store_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select role, point_id
    into v_role, v_profile_point_id
    from public.profiles
   where id = auth.uid();

  if not found then
    raise exception 'User profile not found';
  end if;

  select store_id
    into v_store_id
    from public.points_de_vente
   where id = p_point_id;

  if not found or v_store_id is null then
    raise exception 'Point of sale not found';
  end if;

  if coalesce(v_role, '') not in ('manager', 'owner', 'gerant') then
    raise exception 'This account cannot manage point-of-sale operations';
  end if;

  if not exists (
    select 1 from public.store_members
     where store_id = v_store_id and user_id = auth.uid()
  ) then
    raise exception 'No access to this TOK''COS workspace';
  end if;

  if v_role not in ('manager', 'owner') and v_profile_point_id is distinct from p_point_id then
    raise exception 'No access to this point of sale';
  end if;

  perform 1
    from public.points_de_vente
   where id = p_point_id and store_id = v_store_id
   for update;
  if not found then
    raise exception 'Point of sale is no longer available';
  end if;

  return v_store_id;
end;
$$;

create or replace function public.save_point_inventory(p_point_id uuid, p_items jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_id uuid;
  v_item jsonb;
  v_product_id uuid;
  v_quantity integer;
  v_stock_id uuid;
begin
  v_store_id := public.authorize_tokcos_point(p_point_id);

  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Inventory must contain at least one item';
  end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_quantity := (v_item->>'quantity')::integer;

    if v_quantity is null or v_quantity < 0 then
      raise exception 'Inventory quantity cannot be negative';
    end if;

    if not exists (
      select 1 from public.products
       where id = v_product_id and store_id = v_store_id
    ) then
      raise exception 'Product does not belong to this TOK''COS workspace';
    end if;

    select id into v_stock_id
      from public.stock
     where point_id = p_point_id and product_id = v_product_id and store_id = v_store_id
     for update;

    if v_stock_id is null then
      insert into public.stock (point_id, product_id, quantity, store_id)
      values (p_point_id, v_product_id, v_quantity, v_store_id);
    else
      update public.stock set quantity = v_quantity where id = v_stock_id;
    end if;
    v_stock_id := null;
  end loop;
end;
$$;

create or replace function public.record_pos_sale(
  p_point_id uuid,
  p_client_name text,
  p_payment_method text,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_id uuid;
  v_item jsonb;
  v_product_id uuid;
  v_qty integer;
  v_product_name text;
  v_price numeric;
  v_stock_id uuid;
  v_stock_qty integer;
  v_sale_id uuid;
  v_total numeric := 0;
begin
  v_store_id := public.authorize_tokcos_point(p_point_id);

  if coalesce(trim(p_client_name), '') = '' then
    raise exception 'Client name is required';
  end if;
  if p_payment_method not in ('Espèces', 'Wave', 'Orange Money') then
    raise exception 'Invalid payment method';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Sale must contain at least one item';
  end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'qty')::integer;
    if v_qty is null or v_qty <= 0 then
      raise exception 'Sale quantity must be positive';
    end if;

    select name, price
      into v_product_name, v_price
      from public.products
     where id = v_product_id and store_id = v_store_id and active = true;
    if not found then
      raise exception 'Product is unavailable';
    end if;

    select id, quantity
      into v_stock_id, v_stock_qty
      from public.stock
     where point_id = p_point_id and product_id = v_product_id and store_id = v_store_id
     for update;
    if not found or v_stock_qty < v_qty then
      raise exception 'Insufficient stock for %', v_product_name;
    end if;

    update public.stock
       set quantity = quantity - v_qty
     where id = v_stock_id;

    v_total := v_total + (v_price * v_qty);
  end loop;

  insert into public.sales (
    point_id, client_name, client_phone, delivery_mode, payment_method,
    total, status, channel, fulfilled, store_id
  ) values (
    p_point_id, trim(p_client_name), 'Comptoir', 'Sur place', p_payment_method,
    v_total, 'vendu', 'caisse', true, v_store_id
  ) returning id into v_sale_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'qty')::integer;
    select name, price into v_product_name, v_price
      from public.products where id = v_product_id and store_id = v_store_id;
    insert into public.sale_items (sale_id, product_id, product_name, qty, price, subtotal)
    values (v_sale_id, v_product_id, v_product_name, v_qty, v_price, v_price * v_qty);
  end loop;

  return v_sale_id;
end;
$$;

create or replace function public.fulfill_approvisionnement(p_approvisionnement_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_approvisionnement public.approvisionnements%rowtype;
  v_store_id uuid;
  v_item record;
  v_stock_id uuid;
begin
  select * into v_approvisionnement
    from public.approvisionnements
   where id = p_approvisionnement_id
   for update;
  if not found then
    raise exception 'Approvisionnement not found';
  end if;

  v_store_id := public.authorize_tokcos_point(v_approvisionnement.point_id);
  if v_store_id <> v_approvisionnement.store_id then
    raise exception 'Approvisionnement workspace does not match its point of sale';
  end if;
  if v_approvisionnement.status <> 'demande' then
    raise exception 'Only pending supply requests can be delivered';
  end if;
  if not exists (
    select 1 from public.approvisionnement_items
     where approvisionnement_id = p_approvisionnement_id
  ) then
    raise exception 'Supply request has no items';
  end if;

  for v_item in
    select product_id, sum(qty)::integer as qty
      from public.approvisionnement_items
     where approvisionnement_id = p_approvisionnement_id
     group by product_id
  loop
    if not exists (
      select 1 from public.products
       where id = v_item.product_id and store_id = v_store_id
    ) then
      raise exception 'Supply item product does not belong to this TOK''COS workspace';
    end if;

    select id into v_stock_id
      from public.stock
     where point_id = v_approvisionnement.point_id
       and product_id = v_item.product_id
       and store_id = v_store_id
     for update;

    if v_stock_id is null then
      insert into public.stock (point_id, product_id, quantity, store_id)
      values (v_approvisionnement.point_id, v_item.product_id, v_item.qty, v_store_id);
    else
      update public.stock
         set quantity = quantity + v_item.qty
       where id = v_stock_id;
    end if;
    v_stock_id := null;
  end loop;

  update public.approvisionnements
     set status = 'livre'
   where id = p_approvisionnement_id;
end;
$$;

revoke all on function public.authorize_tokcos_point(uuid) from public;
revoke all on function public.save_point_inventory(uuid, jsonb) from public;
revoke all on function public.record_pos_sale(uuid, text, text, jsonb) from public;
revoke all on function public.fulfill_approvisionnement(uuid) from public;
grant execute on function public.save_point_inventory(uuid, jsonb) to authenticated;
grant execute on function public.record_pos_sale(uuid, text, text, jsonb) to authenticated;
grant execute on function public.fulfill_approvisionnement(uuid) to authenticated;
