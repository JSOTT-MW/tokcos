-- Online order lifecycle and the single TOK'COS-wide register day.

alter table public.sales
  add column if not exists processing_by uuid references public.profiles(id) on delete set null,
  add column if not exists claimed_at timestamptz;

create table if not exists public.tokcos_register_days (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  business_date date not null,
  opening_amount numeric(12,2) not null default 0 check (opening_amount >= 0),
  closing_amount numeric(12,2) check (closing_amount >= 0),
  total_sales numeric(12,2) not null default 0,
  sale_count integer not null default 0,
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  closed_by uuid references public.profiles(id) on delete set null,
  reopened_at timestamptz,
  reopened_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (store_id, business_date)
);

create index if not exists tokcos_register_days_store_date_idx
  on public.tokcos_register_days(store_id, business_date desc);

alter table public.tokcos_register_days enable row level security;
drop policy if exists tokcos_register_days_owner_read on public.tokcos_register_days;
create policy tokcos_register_days_owner_read on public.tokcos_register_days
  for select using (store_id in (select public.my_store_ids()));

create or replace function public.ensure_tokcos_register_day(p_store_id uuid)
returns public.tokcos_register_days
language plpgsql
security definer
set search_path = public
as $$
declare
  v_local timestamp without time zone := timezone('Africa/Dakar', now());
  v_day date;
  v_day_row public.tokcos_register_days;
  v_start timestamptz;
  v_end timestamptz;
begin
  v_day := case
    when v_local::time < time '07:00' then v_local::date - 1
    else v_local::date
  end;

  insert into public.tokcos_register_days (store_id, business_date)
  values (p_store_id, v_day)
  on conflict (store_id, business_date) do nothing;

  select * into v_day_row
    from public.tokcos_register_days
   where store_id = p_store_id and business_date = v_day
   for update;

  if v_local::time >= time '04:00' and v_local::time < time '07:00'
     and v_day_row.closed_at is null then
    v_start := (v_day + time '07:00') at time zone 'Africa/Dakar';
    v_end := ((v_day + 1) + time '04:00') at time zone 'Africa/Dakar';
    update public.tokcos_register_days
       set closed_at = now(),
           total_sales = coalesce((
             select sum(s.total) from public.sales s
              where s.store_id = p_store_id
                and s.status = 'vendu'
                and (s.channel <> 'en_ligne' or s.fulfilled = true)
                and s.created_at >= v_start and s.created_at < v_end
           ), 0),
           sale_count = (
             select count(*) from public.sales s
              where s.store_id = p_store_id
                and s.status = 'vendu'
                and (s.channel <> 'en_ligne' or s.fulfilled = true)
                and s.created_at >= v_start and s.created_at < v_end
           )
     where id = v_day_row.id and closed_at is null
     returning * into v_day_row;
  end if;
  return v_day_row;
end;
$$;

create or replace function public.assert_tokcos_register_open(p_store_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day public.tokcos_register_days;
begin
  if p_store_id is null then
    raise exception 'TOK''COS workspace is required';
  end if;
  v_day := public.ensure_tokcos_register_day(p_store_id);
  if v_day.closed_at is not null
     and (v_day.reopened_at is null or v_day.reopened_at < v_day.closed_at) then
    raise exception 'The TOK''COS register is closed';
  end if;
end;
$$;

create or replace function public.get_tokcos_register_status(p_store_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day public.tokcos_register_days;
  v_role text;
  v_is_open boolean;
  v_start timestamptz;
  v_end timestamptz;
  v_sales_total numeric;
  v_sale_count integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id = auth.uid();
  if coalesce(v_role, '') not in ('manager', 'owner', 'gerant')
     or not exists (select 1 from public.store_members where store_id = p_store_id and user_id = auth.uid()) then
    raise exception 'No access to this TOK''COS workspace';
  end if;
  v_day := public.ensure_tokcos_register_day(p_store_id);
  v_is_open := v_day.closed_at is null
    or (v_day.reopened_at is not null and v_day.reopened_at >= v_day.closed_at);
  v_start := (v_day.business_date + time '07:00') at time zone 'Africa/Dakar';
  v_end := ((v_day.business_date + 1) + time '04:00') at time zone 'Africa/Dakar';
  select coalesce(sum(s.total), 0), count(*)::integer
    into v_sales_total, v_sale_count
    from public.sales s
   where s.store_id = p_store_id and s.status = 'vendu'
     and (s.channel <> 'en_ligne' or s.fulfilled = true)
     and s.created_at >= v_start and s.created_at < v_end;
  return jsonb_build_object(
    'is_open', v_is_open,
    'can_reopen', not v_is_open and v_role in ('manager', 'owner'),
    'business_date', v_day.business_date,
    'sales_total', v_sales_total,
    'sale_count', v_sale_count,
    'message', case when v_is_open then 'Caisse ouverte'
                    else 'Caisse fermée pour tous les points de vente' end
  );
end;
$$;

create or replace function public.close_tokcos_register(
  p_store_id uuid,
  p_opening_amount numeric,
  p_closing_amount numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_day public.tokcos_register_days;
  v_start timestamptz;
  v_end timestamptz;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id = auth.uid();
  if coalesce(v_role, '') not in ('manager', 'owner', 'gerant')
     or not exists (select 1 from public.store_members where store_id = p_store_id and user_id = auth.uid()) then
    raise exception 'No access to close this TOK''COS register';
  end if;
  if p_opening_amount is null or p_opening_amount < 0
     or p_closing_amount is null or p_closing_amount < 0 then
    raise exception 'Register amounts must be zero or greater';
  end if;
  v_day := public.ensure_tokcos_register_day(p_store_id);
  if v_day.closed_at is not null
     and (v_day.reopened_at is null or v_day.reopened_at < v_day.closed_at) then
    raise exception 'The TOK''COS register is already closed';
  end if;
  v_start := (v_day.business_date + time '07:00') at time zone 'Africa/Dakar';
  v_end := ((v_day.business_date + 1) + time '04:00') at time zone 'Africa/Dakar';
  update public.tokcos_register_days
     set opening_amount = p_opening_amount,
         closing_amount = p_closing_amount,
         total_sales = coalesce((
           select sum(s.total) from public.sales s
            where s.store_id = p_store_id and s.status = 'vendu'
              and (s.channel <> 'en_ligne' or s.fulfilled = true)
              and s.created_at >= v_start and s.created_at < v_end
         ), 0),
         sale_count = (
           select count(*) from public.sales s
            where s.store_id = p_store_id and s.status = 'vendu'
              and (s.channel <> 'en_ligne' or s.fulfilled = true)
              and s.created_at >= v_start and s.created_at < v_end
         ),
         closed_at = now(), closed_by = auth.uid(),
         reopened_at = null, reopened_by = null
   where id = v_day.id;
end;
$$;

create or replace function public.reopen_tokcos_register(p_store_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_day public.tokcos_register_days;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id = auth.uid();
  if coalesce(v_role, '') not in ('manager', 'owner')
     or not exists (select 1 from public.store_members where store_id = p_store_id and user_id = auth.uid()) then
    raise exception 'Only the TOK''COS owner can reopen the register';
  end if;
  v_day := public.ensure_tokcos_register_day(p_store_id);
  if v_day.closed_at is null
     or (v_day.reopened_at is not null and v_day.reopened_at >= v_day.closed_at) then
    raise exception 'The TOK''COS register is not closed';
  end if;
  update public.tokcos_register_days
     set reopened_at = now(), reopened_by = auth.uid()
   where id = v_day.id;
end;
$$;

create or replace function public.auto_close_tokcos_registers()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store record;
begin
  for v_store in select id from public.stores where active = true
  loop
    perform public.ensure_tokcos_register_day(v_store.id);
  end loop;
end;
$$;

-- Add the register guard to every point operation already routed through this helper.
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
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role, point_id into v_role, v_profile_point_id
    from public.profiles where id = auth.uid();
  if not found then raise exception 'User profile not found'; end if;
  select store_id into v_store_id
    from public.points_de_vente where id = p_point_id;
  if not found or v_store_id is null then raise exception 'Point of sale not found'; end if;
  if coalesce(v_role, '') not in ('manager', 'owner', 'gerant') then
    raise exception 'This account cannot manage point-of-sale operations';
  end if;
  if not exists (
    select 1 from public.store_members
     where store_id = v_store_id and user_id = auth.uid()
  ) then raise exception 'No access to this TOK''COS workspace'; end if;
  if v_role not in ('manager', 'owner') and v_profile_point_id is distinct from p_point_id then
    raise exception 'No access to this point of sale';
  end if;
  perform public.assert_tokcos_register_open(v_store_id);
  perform 1 from public.points_de_vente
   where id = p_point_id and store_id = v_store_id for update;
  if not found then raise exception 'Point of sale is no longer available'; end if;
  return v_store_id;
end;
$$;

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
     where id = (v_item->>'product_id')::uuid and store_id = p_store_id and active = true;
    v_line_total := v_price * (v_item->>'qty')::integer;
    insert into public.sale_items (sale_id, product_id, product_name, qty, price, subtotal)
    values (v_sale_id, (v_item->>'product_id')::uuid, v_product_name, (v_item->>'qty')::integer, v_price, v_line_total);
  end loop;
  return v_sale_id;
end;
$$;

create or replace function public.claim_online_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale public.sales;
  v_store_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_sale from public.sales where id = p_order_id for update;
  if not found or v_sale.channel <> 'en_ligne' or v_sale.fulfilled or v_sale.status <> 'vendu' then
    raise exception 'Online order is no longer pending';
  end if;
  v_store_id := public.authorize_tokcos_point(v_sale.point_id);
  if v_sale.store_id <> v_store_id then raise exception 'Order workspace does not match'; end if;
  if v_sale.processing_by is not null and v_sale.processing_by <> auth.uid() then
    raise exception 'This order is already being prepared';
  end if;
  update public.sales set processing_by = auth.uid(), claimed_at = now()
   where id = p_order_id;
end;
$$;

create or replace function public.release_online_order_claim(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale public.sales;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_sale from public.sales where id = p_order_id for update;
  if not found or v_sale.channel <> 'en_ligne' or v_sale.fulfilled then
    raise exception 'Online order is no longer pending';
  end if;
  perform public.authorize_tokcos_point(v_sale.point_id);
  if v_sale.processing_by is distinct from auth.uid() then
    raise exception 'Only the assigned cashier can release this order';
  end if;
  update public.sales set processing_by = null, claimed_at = null where id = p_order_id;
end;
$$;

create or replace function public.settle_online_order(p_sale_id uuid, p_payment_method text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale public.sales;
  v_store_id uuid;
  v_item record;
  v_stock_id uuid;
  v_stock integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_payment_method not in ('Espèces', 'Wave', 'Orange Money') then
    raise exception 'Invalid payment method';
  end if;
  select * into v_sale from public.sales where id = p_sale_id for update;
  if not found or v_sale.channel <> 'en_ligne' or v_sale.fulfilled or v_sale.status <> 'vendu' then
    raise exception 'Online order is no longer pending';
  end if;
  v_store_id := public.authorize_tokcos_point(v_sale.point_id);
  if v_sale.store_id <> v_store_id then raise exception 'Order workspace does not match'; end if;
  if v_sale.processing_by is distinct from auth.uid() then
    raise exception 'Take charge of this order before settling it';
  end if;

  for v_item in
    select product_id, sum(qty)::integer as qty
      from public.sale_items where sale_id = v_sale.id
     group by product_id order by product_id
  loop
    select id, quantity into v_stock_id, v_stock
      from public.stock
     where store_id = v_store_id and point_id = v_sale.point_id and product_id = v_item.product_id
     for update;
    if not found or v_stock < v_item.qty then
      raise exception 'Insufficient stock to settle this order';
    end if;
    update public.stock set quantity = quantity - v_item.qty where id = v_stock_id;
  end loop;

  perform set_config('tokcos.settling_order', v_sale.id::text, true);
  update public.sales
     set payment_method = p_payment_method, fulfilled = true,
         processing_by = null, claimed_at = null
   where id = v_sale.id;
end;
$$;

create or replace function public.update_approvisionnement_request(
  p_approvisionnement_id uuid,
  p_items jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.approvisionnements;
  v_role text;
  v_item record;
  v_name text;
  v_cost numeric;
  v_total numeric := 0;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id = auth.uid();
  if coalesce(v_role, '') not in ('manager', 'owner') then
    raise exception 'Only the TOK''COS owner can edit an approvisionnement';
  end if;
  select * into v_request from public.approvisionnements
   where id = p_approvisionnement_id for update;
  if not found or not exists (
    select 1 from public.store_members
     where store_id = v_request.store_id and user_id = auth.uid()
  ) then raise exception 'Approvisionnement not found or not accessible'; end if;
  if v_request.status <> 'demande' then raise exception 'Only pending requests can be edited'; end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'At least one product is required';
  end if;

  delete from public.approvisionnement_items where approvisionnement_id = v_request.id;
  for v_item in
    select (value->>'product_id')::uuid as product_id, sum((value->>'qty')::integer)::integer as qty
      from jsonb_array_elements(p_items)
     group by (value->>'product_id')::uuid
  loop
    if v_item.qty is null or v_item.qty <= 0 then raise exception 'Quantities must be positive'; end if;
    select name, price into v_name, v_cost
      from public.products
     where id = v_item.product_id and store_id = v_request.store_id and active = true;
    if not found then raise exception 'Product is unavailable'; end if;
    insert into public.approvisionnement_items
      (approvisionnement_id, product_id, product_name, qty, cost)
    values (v_request.id, v_item.product_id, v_name, v_item.qty, v_cost);
    v_total := v_total + v_cost * v_item.qty;
  end loop;
  update public.approvisionnements set total = v_total where id = v_request.id;
end;
$$;

create or replace function public.delete_approvisionnement_request(p_approvisionnement_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.approvisionnements;
  v_role text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id = auth.uid();
  if coalesce(v_role, '') not in ('manager', 'owner') then
    raise exception 'Only the TOK''COS owner can delete an approvisionnement';
  end if;
  select * into v_request from public.approvisionnements
   where id = p_approvisionnement_id for update;
  if not found or not exists (
    select 1 from public.store_members
     where store_id = v_request.store_id and user_id = auth.uid()
  ) then raise exception 'Approvisionnement not found or not accessible'; end if;
  if v_request.status <> 'demande' then raise exception 'Only pending requests can be deleted'; end if;
  delete from public.approvisionnements where id = v_request.id;
end;
$$;

-- Remove direct anonymous inserts; public ordering now goes through the validated RPC.
drop policy if exists sales_public_insert on public.sales;
drop policy if exists sale_items_public_insert on public.sale_items;

create or replace function public.guard_tokcos_sales_register()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_id uuid;
begin
  v_store_id := case when tg_op = 'DELETE' then old.store_id else new.store_id end;
  if tg_op = 'UPDATE' and old.channel = 'en_ligne' and not old.fulfilled
     and (new.status is distinct from old.status
       or new.fulfilled is distinct from old.fulfilled
       or new.payment_method is distinct from old.payment_method)
     and current_setting('tokcos.settling_order', true) is distinct from old.id::text then
    raise exception 'An online order must be settled through the cash register';
  end if;
  perform public.assert_tokcos_register_open(v_store_id);
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function public.guard_tokcos_transaction_register()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_tokcos_register_open(
    case when tg_op = 'DELETE' then old.store_id else new.store_id end
  );
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

-- All sale creation and line creation must use the transactional RPCs above.
drop policy if exists sales_store_access on public.sales;
drop policy if exists sales_member_read on public.sales;
drop policy if exists sales_member_update on public.sales;
create policy sales_member_read on public.sales
  for select using (store_id in (select public.my_store_ids()));
create policy sales_member_update on public.sales
  for update using (store_id in (select public.my_store_ids()))
  with check (store_id in (select public.my_store_ids()));
drop policy if exists sale_items_store_access on public.sale_items;
drop policy if exists sale_items_member_read on public.sale_items;
create policy sale_items_member_read on public.sale_items
  for select using (
    sale_id in (select id from public.sales where store_id in (select public.my_store_ids()))
  );

drop trigger if exists sales_register_open_guard on public.sales;
create trigger sales_register_open_guard
before insert or update or delete on public.sales
for each row execute function public.guard_tokcos_sales_register();

do $$
begin
  if to_regclass('public.transactions') is not null then
    execute 'drop trigger if exists transactions_register_open_guard on public.transactions';
    execute 'create trigger transactions_register_open_guard
      before insert or update or delete on public.transactions
      for each row execute function public.guard_tokcos_transaction_register()';
  end if;
end;
$$;

revoke all on function public.ensure_tokcos_register_day(uuid) from public, anon, authenticated;
revoke all on function public.assert_tokcos_register_open(uuid) from public, anon, authenticated;
revoke all on function public.auto_close_tokcos_registers() from public, anon, authenticated;
revoke all on function public.guard_tokcos_sales_register() from public, anon, authenticated;
revoke all on function public.guard_tokcos_transaction_register() from public, anon, authenticated;
revoke all on function public.get_tokcos_register_status(uuid) from public, anon;
revoke all on function public.close_tokcos_register(uuid, numeric, numeric) from public, anon;
revoke all on function public.reopen_tokcos_register(uuid) from public, anon;
revoke all on function public.submit_online_order(uuid, uuid, text, text, text, jsonb) from public;
revoke all on function public.claim_online_order(uuid) from public, anon;
revoke all on function public.release_online_order_claim(uuid) from public, anon;
revoke all on function public.settle_online_order(uuid, text) from public, anon;
revoke all on function public.update_approvisionnement_request(uuid, jsonb) from public, anon;
revoke all on function public.delete_approvisionnement_request(uuid) from public, anon;

grant execute on function public.get_tokcos_register_status(uuid) to authenticated;
grant execute on function public.close_tokcos_register(uuid, numeric, numeric) to authenticated;
grant execute on function public.reopen_tokcos_register(uuid) to authenticated;
grant execute on function public.submit_online_order(uuid, uuid, text, text, text, jsonb) to anon, authenticated;
grant execute on function public.claim_online_order(uuid) to authenticated;
grant execute on function public.release_online_order_claim(uuid) to authenticated;
grant execute on function public.settle_online_order(uuid, text) to authenticated;
grant execute on function public.update_approvisionnement_request(uuid, jsonb) to authenticated;
grant execute on function public.delete_approvisionnement_request(uuid) to authenticated;

create extension if not exists pg_cron;
do $$
declare
  v_job record;
begin
  for v_job in select jobid from cron.job where jobname = 'tokcos-daily-register-close'
  loop
    perform cron.unschedule(v_job.jobid);
  end loop;
  perform cron.schedule(
    'tokcos-daily-register-close',
    '0 4 * * *',
    'select public.auto_close_tokcos_registers();'
  );
end;
$$;
