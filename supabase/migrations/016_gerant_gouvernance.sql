-- Gouvernance TOK'COS : gérant sans comptabilité, ventes verrouillées,
-- inventaires mensuels avec écarts, campagnes du propriétaire,
-- un seul gérant par point, e-mail gerant.<slug>@tokcos.sn.
-- À exécuter dans Supabase SQL Editor après la migration 015.

-- 1) Slug normalisé des points de vente pour l'e-mail automatique.
alter table public.points_de_vente
  add column if not exists slug text;

do $$
declare
  r record;
  v_base text;
  v_slug text;
  v_suffix integer;
begin
  for r in select id, name from public.points_de_vente
           order by created_at nulls last, name
  loop
    v_base := lower(coalesce(r.name, 'point'));
    v_base := regexp_replace(v_base, '[^a-z0-9]+', '-', 'g');
    v_base := regexp_replace(v_base, '(^-+|-+$)', '', 'g');
    if v_base is null or v_base = '' then v_base := 'point'; end if;
    v_slug := v_base;
    v_suffix := 1;
    while exists (select 1 from public.points_de_vente p
                   where p.slug = v_slug and p.id <> r.id) loop
      v_suffix := v_suffix + 1;
      v_slug := v_base || '-' || v_suffix;
    end loop;
    update public.points_de_vente set slug = v_slug
     where id = r.id and slug is distinct from v_slug;
  end loop;
end;
$$;

alter table public.points_de_vente
  alter column slug set not null;

create unique index if not exists points_de_vente_slug_key
  on public.points_de_vente (slug);

create or replace function public.tokcos_point_slug(p_name text)
returns text
language plpgsql
as $$
declare
  v_base text;
  v_slug text;
  v_suffix integer := 1;
begin
  v_base := lower(coalesce(p_name, 'point'));
  v_base := regexp_replace(v_base, '[^a-z0-9]+', '-', 'g');
  v_base := regexp_replace(v_base, '(^-+|-+$)', '', 'g');
  if v_base is null or v_base = '' then v_base := 'point'; end if;
  v_slug := v_base;
  while exists (select 1 from public.points_de_vente p where p.slug = v_slug) loop
    v_suffix := v_suffix + 1;
    v_slug := v_base || '-' || v_suffix;
  end loop;
  return v_slug;
end;
$$;

create or replace function public.tokcos_set_point_slug()
returns trigger
language plpgsql
as $$
declare
  v_base text;
  v_slug text;
  v_suffix integer := 1;
begin
  if new.slug is not null and new.slug <> '' then
    new.slug := lower(new.slug);
    new.slug := regexp_replace(new.slug, '[^a-z0-9-]+', '-', 'g');
    new.slug := regexp_replace(new.slug, '(^-+|-+$)', '', 'g');
    if new.slug is null or new.slug = '' then new.slug := null; end if;
  end if;
  if new.slug is null or new.slug = '' then
    new.slug := public.tokcos_point_slug(new.name);
  else
    v_base := new.slug;
    v_slug := v_base;
    while exists (select 1 from public.points_de_vente p
                   where p.slug = v_slug and p.id <> new.id) loop
      v_suffix := v_suffix + 1;
      v_slug := v_base || '-' || v_suffix;
    end loop;
    new.slug := v_slug;
  end if;
  return new;
end;
$$;

drop trigger if exists points_de_vente_slug_trigger on public.points_de_vente;
create trigger points_de_vente_slug_trigger
before insert or update of name, slug on public.points_de_vente
for each row execute function public.tokcos_set_point_slug();

-- 2) Journal des inventaires : stock constaté, stock théorique et écarts.
create table if not exists public.inventory_counts (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  point_id uuid not null references public.points_de_vente(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  counted_at date not null default (timezone('Africa/Dakar', now()))::date,
  expected_quantity integer not null default 0,
  counted_quantity integer not null check (counted_quantity >= 0),
  gap integer not null default 0,
  created_by uuid references public.profiles(id) on delete set null,
  campaign_id uuid,
  created_at timestamptz not null default now()
);

alter table public.inventory_counts
  add column if not exists campaign_id uuid,
  add column if not exists created_by uuid references public.profiles(id) on delete set null;

create index if not exists inventory_counts_point_day_idx
  on public.inventory_counts (point_id, counted_at desc);
create index if not exists inventory_counts_point_product_day_idx
  on public.inventory_counts (point_id, product_id, counted_at desc);
create index if not exists inventory_counts_campaign_idx
  on public.inventory_counts (campaign_id);

-- 3) Campagnes d'inventaire déclenchées par le propriétaire.
create table if not exists public.inventory_campaigns (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  point_id uuid references public.points_de_vente(id) on delete cascade,
  title text not null default 'Inventaire',
  mode text not null default 'immediat' check (mode in ('immediat', 'planifie')),
  recurrence text not null default 'ponctuel'
    check (recurrence in ('ponctuel', 'jour', 'semaine', 'mois', 'annee')),
  starts_at timestamptz not null default now(),
  status text not null default 'demande' check (status in ('demande', 'cloture')),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists inventory_campaigns_store_idx
  on public.inventory_campaigns (store_id, starts_at desc);
create index if not exists inventory_campaigns_point_idx
  on public.inventory_campaigns (point_id, starts_at desc);

do $$
begin
  if to_regclass('public.inventory_counts') is not null
     and to_regclass('public.inventory_campaigns') is not null then
    if not exists (
      select 1 from pg_constraint where conname = 'inventory_counts_campaign_fk'
    ) then
      alter table public.inventory_counts
        add constraint inventory_counts_campaign_fk
        foreign key (campaign_id) references public.inventory_campaigns(id) on delete set null;
    end if;
  end if;
end;
$$;

alter table public.inventory_counts enable row level security;
alter table public.inventory_campaigns enable row level security;

-- 4) Un seul gérant par point de vente (rôle gerant + point non nul).
drop index if exists profiles_one_gerant_per_point;
create unique index if not exists profiles_one_gerant_per_point
  on public.profiles (point_id)
  where role = 'gerant' and point_id is not null;

-- 5) Comptabilité : lecture/écriture réservées au propriétaire.
-- Le gérant n'a plus d'onglet Comptabilité ; la RLS verrouille aussi l'accès direct.
drop policy if exists transactions_store_access on public.transactions;
drop policy if exists transactions_member_read on public.transactions;
drop policy if exists transactions_member_insert on public.transactions;
drop policy if exists transactions_member_update on public.transactions;
drop policy if exists transactions_member_delete on public.transactions;

create policy transactions_owner_read on public.transactions
  for select using (
    store_id in (select public.my_store_ids())
    and exists (
      select 1 from public.profiles p
       where p.id = auth.uid() and p.role in ('manager', 'owner')
    )
  );

create policy transactions_owner_insert on public.transactions
  for insert with check (
    store_id in (select public.my_store_ids())
    and exists (
      select 1 from public.profiles p
       where p.id = auth.uid() and p.role in ('manager', 'owner')
    )
  );

create policy transactions_owner_update on public.transactions
  for update using (
    store_id in (select public.my_store_ids())
    and exists (
      select 1 from public.profiles p
       where p.id = auth.uid() and p.role in ('manager', 'owner')
    )
  )
  with check (
    store_id in (select public.my_store_ids())
    and exists (
      select 1 from public.profiles p
       where p.id = auth.uid() and p.role in ('manager', 'owner')
    )
  );

create policy transactions_owner_delete on public.transactions
  for delete using (
    store_id in (select public.my_store_ids())
    and exists (
      select 1 from public.profiles p
       where p.id = auth.uid() and p.role in ('manager', 'owner')
    )
  );

-- 6) Ventes : lecture pour le gérant sur son point, écriture propriétaire.
-- Le stock reste ajusté par les flux (caisse, approvisionnement, inventaire).
drop policy if exists sales_store_access on public.sales;
drop policy if exists sales_member_read on public.sales;
drop policy if exists sales_member_insert on public.sales;
drop policy if exists sales_member_update on public.sales;
drop policy if exists sales_member_delete on public.sales;

create policy sales_member_read on public.sales
  for select using (
    store_id in (select public.my_store_ids())
    and exists (
      select 1 from public.profiles p
       where p.id = auth.uid()
         and (
           p.role in ('manager', 'owner')
           or (p.role = 'gerant' and (p.point_id is null or p.point_id = sales.point_id))
         )
    )
  );

create policy sales_member_insert on public.sales
  for insert with check (store_id in (select public.my_store_ids()));

create policy sales_member_update on public.sales
  for update using (
    store_id in (select public.my_store_ids())
    and exists (
      select 1 from public.profiles p
       where p.id = auth.uid() and p.role in ('manager', 'owner')
    )
  )
  with check (
    store_id in (select public.my_store_ids())
    and exists (
      select 1 from public.profiles p
       where p.id = auth.uid() and p.role in ('manager', 'owner')
    )
  );

create policy sales_member_delete on public.sales
  for delete using (
    store_id in (select public.my_store_ids())
    and exists (
      select 1 from public.profiles p
       where p.id = auth.uid() and p.role in ('manager', 'owner')
    )
  );

-- 7) Stock ajusté uniquement par les flux métier : aucun update/delete
-- direct pour les gérants, seul le propriétaire garde l'écriture manuelle.
drop policy if exists stock_store_access on public.stock;
drop policy if exists stock_public_read on public.stock;
drop policy if exists stock_member_read on public.stock;
drop policy if exists stock_owner_write on public.stock;

create policy stock_member_read on public.stock
  for select using (store_id in (select public.my_store_ids()));

create policy stock_public_read on public.stock
  for select using (store_id in (select id from public.stores where active = true));

create policy stock_owner_write on public.stock
  for all using (
    store_id in (select public.my_store_ids())
    and exists (
      select 1 from public.profiles p
       where p.id = auth.uid() and p.role in ('manager', 'owner')
    )
  )
  with check (
    store_id in (select public.my_store_ids())
    and exists (
      select 1 from public.profiles p
       where p.id = auth.uid() and p.role in ('manager', 'owner')
    )
  );

-- 8) Validation mensuelle : le gérant compte le 1er du mois (ou sur
-- campagne du propriétaire) ; le propriétaire valide à tout moment.
create or replace function public.submit_monthly_stock_count(
  p_point_id uuid,
  p_items jsonb,
  p_campaign_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_id uuid;
  v_role text;
  v_profile_point uuid;
  v_local_date date := (timezone('Africa/Dakar', now()))::date;
  v_campaign public.inventory_campaigns%rowtype;
  v_item jsonb;
  v_product_id uuid;
  v_counted integer;
  v_expected integer;
  v_stock_id uuid;
  v_gap integer;
  v_group uuid := gen_random_uuid();
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role, point_id into v_role, v_profile_point
    from public.profiles where id = auth.uid();
  if not found then raise exception 'User profile not found'; end if;
  select store_id into v_store_id from public.points_de_vente where id = p_point_id;
  if not found or v_store_id is null then raise exception 'Point of sale not found'; end if;
  if not exists (select 1 from public.store_members
                  where store_id = v_store_id and user_id = auth.uid()) then
    raise exception 'No access to this TOK''COS workspace';
  end if;
  if coalesce(v_role, '') not in ('manager', 'owner', 'gerant') then
    raise exception 'This account cannot validate stock';
  end if;
  if v_role = 'gerant' and v_profile_point is distinct from p_point_id then
    raise exception 'No access to this point of sale';
  end if;
  if p_campaign_id is not null then
    select * into v_campaign from public.inventory_campaigns
     where id = p_campaign_id for update;
    if not found then raise exception 'Inventory campaign not found'; end if;
    if v_campaign.store_id <> v_store_id then
      raise exception 'Inventory campaign does not belong to this workspace';
    end if;
    if v_campaign.point_id is not null and v_campaign.point_id <> p_point_id then
      raise exception 'Inventory campaign targets another point of sale';
    end if;
    if v_campaign.status <> 'demande' then
      raise exception 'Inventory campaign is already closed';
    end if;
    v_group := v_campaign.id;
  elsif v_role = 'gerant' then
    if extract(day from v_local_date) <> 1 then
      raise exception 'Stock validation is only allowed on the 1st of the month';
    end if;
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Stock count must contain at least one product';
  end if;
  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_counted := (v_item->>'counted_quantity')::integer;
    if v_counted is null or v_counted < 0 then
      raise exception 'Counted quantity cannot be negative';
    end if;
    if not exists (select 1 from public.products
                    where id = v_product_id and store_id = v_store_id and active = true) then
      raise exception 'Product does not belong to this workspace';
    end if;
    select quantity, id into v_expected, v_stock_id from public.stock
     where point_id = p_point_id and product_id = v_product_id and store_id = v_store_id
     for update;
    if not found then
      v_expected := 0;
      insert into public.stock (point_id, product_id, quantity, store_id)
      values (p_point_id, v_product_id, v_counted, v_store_id)
      returning id into v_stock_id;
    else
      update public.stock set quantity = v_counted where id = v_stock_id;
    end if;
    v_gap := v_counted - coalesce(v_expected, 0);
    insert into public.inventory_counts
      (store_id, point_id, product_id, counted_at,
       expected_quantity, counted_quantity, gap, created_by, campaign_id)
    values
      (v_store_id, p_point_id, v_product_id, v_local_date,
       coalesce(v_expected, 0), v_counted, v_gap, auth.uid(),
       case when p_campaign_id is null then v_group else p_campaign_id end);
    v_stock_id := null;
    v_expected := null;
  end loop;
  if p_campaign_id is not null then
    update public.inventory_campaigns set status = 'cloture' where id = p_campaign_id;
  end if;
  return v_group;
end;
$$;

-- 9) Correction propriétaire d'une vente encaissée : le stock suit l'écart.
create or replace function public.correct_sale_status(
  p_sale_id uuid,
  p_status text,
  p_items jsonb default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale public.sales%rowtype;
  v_role text;
  v_item jsonb;
  v_product_id uuid;
  v_old_qty integer;
  v_new_qty integer;
  v_delta integer;
  v_stock_qty integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id = auth.uid();
  if coalesce(v_role, '') not in ('manager', 'owner') then
    raise exception 'Only the TOK''COS owner can edit a settled sale';
  end if;
  if p_status not in ('vendu', 'rembourse', 'annule') then
    raise exception 'Invalid sale status';
  end if;
  select * into v_sale from public.sales where id = p_sale_id for update;
  if not found then raise exception 'Sale not found'; end if;
  if p_items is null then
    update public.sales set status = p_status where id = p_sale_id;
    return;
  end if;
  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_new_qty := (v_item->>'qty')::integer;
    if v_new_qty is null or v_new_qty < 0 then
      raise exception 'Sale quantity cannot be negative';
    end if;
    select qty into v_old_qty from public.sale_items
     where sale_id = p_sale_id and product_id = v_product_id;
    if not found then raise exception 'Sale item not in this sale'; end if;
    v_delta := v_new_qty - coalesce(v_old_qty, 0);
    if v_delta <> 0 then
      select quantity into v_stock_qty from public.stock
       where point_id = v_sale.point_id and product_id = v_product_id
         and store_id = v_sale.store_id for update;
      if not found then
        if v_delta > 0 then raise exception 'Insufficient stock'; end if;
        insert into public.stock (point_id, product_id, quantity, store_id)
        values (v_sale.point_id, v_product_id, 0, v_sale.store_id);
        v_stock_qty := 0;
      end if;
      if v_stock_qty - v_delta < 0 then raise exception 'Insufficient stock'; end if;
      update public.stock set quantity = quantity - v_delta
       where point_id = v_sale.point_id and product_id = v_product_id
         and store_id = v_sale.store_id;
      update public.sale_items set qty = v_new_qty, subtotal = price * v_new_qty
       where sale_id = p_sale_id and product_id = v_product_id;
    end if;
  end loop;
  update public.sales
     set status = p_status,
         total = coalesce((select sum(subtotal) from public.sale_items
                            where sale_id = p_sale_id), 0)
   where id = p_sale_id;
end;
$$;

create or replace function public.delete_sale_with_restock(p_sale_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale public.sales%rowtype;
  v_role text;
  v_item record;
  v_stock_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id = auth.uid();
  if coalesce(v_role, '') not in ('manager', 'owner') then
    raise exception 'Only the TOK''COS owner can delete a sale';
  end if;
  select * into v_sale from public.sales where id = p_sale_id for update;
  if not found then raise exception 'Sale not found'; end if;
  for v_item in select product_id, qty from public.sale_items where sale_id = p_sale_id
  loop
    select id into v_stock_id from public.stock
     where point_id = v_sale.point_id and product_id = v_item.product_id
       and store_id = v_sale.store_id for update;
    if v_stock_id is null then
      insert into public.stock (point_id, product_id, quantity, store_id)
      values (v_sale.point_id, v_item.product_id, v_item.qty, v_sale.store_id);
    else
      update public.stock set quantity = quantity + v_item.qty where id = v_stock_id;
    end if;
    v_stock_id := null;
  end loop;
  delete from public.sales where id = p_sale_id;
end;
$$;

-- 10) Campagnes d'inventaire : création / clôture réservées au propriétaire.
create or replace function public.create_inventory_campaign(
  p_point_id uuid,
  p_title text,
  p_mode text,
  p_recurrence text,
  p_starts_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_id uuid;
  v_role text;
  v_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id = auth.uid();
  if coalesce(v_role, '') not in ('manager', 'owner') then
    raise exception 'Only the TOK''COS owner can request an inventory';
  end if;
  if p_point_id is not null then
    select store_id into v_store_id from public.points_de_vente where id = p_point_id;
    if not found or v_store_id is null then raise exception 'Point of sale not found'; end if;
  else
    select store_id into v_store_id from public.store_members
     where user_id = auth.uid() order by created_at limit 1;
    if not found or v_store_id is null then raise exception 'No workspace'; end if;
  end if;
  insert into public.inventory_campaigns
    (store_id, point_id, title, mode, recurrence, starts_at, created_by)
  values (
    v_store_id, p_point_id,
    nullif(trim(coalesce(p_title, '')), ''),
    case when p_mode in ('immediat', 'planifie') then p_mode else 'immediat' end,
    case when p_recurrence in ('ponctuel','jour','semaine','mois','annee')
         then p_recurrence else 'ponctuel' end,
    coalesce(p_starts_at, now()),
    auth.uid()
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.close_inventory_campaign(p_campaign_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id = auth.uid();
  if coalesce(v_role, '') not in ('manager', 'owner') then
    raise exception 'Only the TOK''COS owner can close an inventory campaign';
  end if;
  update public.inventory_campaigns set status = 'cloture'
   where id = p_campaign_id
     and store_id in (select public.my_store_ids());
  if not found then raise exception 'Inventory campaign not found'; end if;
end;
$$;

drop policy if exists inventory_counts_store_access on public.inventory_counts;
create policy inventory_counts_store_access on public.inventory_counts
  for all using (store_id in (select public.my_store_ids()))
  with check (store_id in (select public.my_store_ids()));

drop policy if exists inventory_campaigns_store_access on public.inventory_campaigns;
create policy inventory_campaigns_store_access on public.inventory_campaigns
  for all using (store_id in (select public.my_store_ids()))
  with check (store_id in (select public.my_store_ids()));

revoke all on function public.submit_monthly_stock_count(uuid, jsonb, uuid) from public, anon;
revoke all on function public.correct_sale_status(uuid, text, jsonb) from public, anon;
revoke all on function public.delete_sale_with_restock(uuid) from public, anon;
revoke all on function public.create_inventory_campaign(uuid, text, text, text, timestamptz) from public, anon;
revoke all on function public.close_inventory_campaign(uuid) from public, anon;
revoke all on function public.tokcos_point_slug(text) from public, anon;
revoke all on function public.tokcos_set_point_slug() from public, anon;

grant execute on function public.submit_monthly_stock_count(uuid, jsonb, uuid) to authenticated;
grant execute on function public.correct_sale_status(uuid, text, jsonb) to authenticated;
grant execute on function public.delete_sale_with_restock(uuid) to authenticated;
grant execute on function public.create_inventory_campaign(uuid, text, text, text, timestamptz) to authenticated;
grant execute on function public.close_inventory_campaign(uuid) to authenticated;

