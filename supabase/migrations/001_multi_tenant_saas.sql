-- TOK'COS SaaS foundation: organizations, stores, memberships and tenant isolation.
-- Run this migration in Supabase SQL Editor before changing the frontend to use store_id.

create extension if not exists pgcrypto;

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  owner_id uuid not null references auth.users(id) on delete restrict,
  branding jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.stores (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  slug text not null,
  logo_url text,
  description text,
  phone text,
  email text,
  address text,
  currency text not null default 'XOF',
  timezone text not null default 'Africa/Dakar',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id, slug)
);

create table if not exists public.store_members (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'admin', 'manager', 'cashier', 'viewer')),
  created_at timestamptz not null default now(),
  unique (store_id, user_id)
);

create index if not exists stores_organization_id_idx on public.stores(organization_id);
create index if not exists store_members_user_id_idx on public.store_members(user_id);
create index if not exists store_members_store_id_idx on public.store_members(store_id);

-- Add tenant keys to the existing application tables.
alter table public.profiles add column if not exists organization_id uuid references public.organizations(id) on delete set null;
alter table public.products add column if not exists store_id uuid references public.stores(id) on delete cascade;
alter table public.points_de_vente add column if not exists store_id uuid references public.stores(id) on delete cascade;
alter table public.stock add column if not exists store_id uuid references public.stores(id) on delete cascade;
alter table public.sales add column if not exists store_id uuid references public.stores(id) on delete cascade;
alter table public.messages add column if not exists store_id uuid references public.stores(id) on delete cascade;
alter table public.caisse_cloture add column if not exists store_id uuid references public.stores(id) on delete cascade;

-- Backfill the current installation into one initial organization and store.
do $$
declare
  owner_user uuid;
  org_id uuid;
  new_store_id uuid;
begin
  select id into owner_user from public.profiles where role = 'manager' order by created_at nulls first limit 1;
  if owner_user is null then
    select id into owner_user from auth.users order by created_at limit 1;
  end if;

  if owner_user is not null then
    select id into org_id from public.organizations order by created_at limit 1;
    if org_id is null then
      insert into public.organizations (name, slug, owner_id)
      values ('TOK''COS', 'tokcos', owner_user)
      returning id into org_id;
    end if;

    select id into new_store_id from public.stores where organization_id = org_id order by created_at limit 1;
    if new_store_id is null then
      insert into public.stores (organization_id, name, slug, description)
      values (org_id, 'TOK''COS', 'tokcos', 'Boutique principale TOK''COS')
      returning id into new_store_id;
    end if;

    insert into public.store_members (store_id, user_id, role)
    values (new_store_id, owner_user, 'owner')
    on conflict (store_id, user_id) do nothing;

    update public.profiles set organization_id = org_id where id = owner_user and organization_id is null;
    update public.products set store_id = new_store_id where public.products.store_id is null;
    update public.points_de_vente set store_id = new_store_id where public.points_de_vente.store_id is null;
    update public.stock s set store_id = p.store_id
      from public.points_de_vente p where s.point_id = p.id and s.store_id is null;
    update public.sales s set store_id = p.store_id
      from public.points_de_vente p where s.point_id = p.id and s.store_id is null;
    update public.messages m set store_id = p.store_id
      from public.points_de_vente p where m.point_id = p.id and m.store_id is null;
    update public.caisse_cloture c set store_id = p.store_id
      from public.points_de_vente p where c.point_id = p.id and c.store_id is null;
  end if;
end $$;

create index if not exists products_store_id_idx on public.products(store_id);
create index if not exists points_de_vente_store_id_idx on public.points_de_vente(store_id);
create index if not exists stock_store_id_idx on public.stock(store_id);
create index if not exists sales_store_id_created_at_idx on public.sales(store_id, created_at desc);
create index if not exists messages_store_id_idx on public.messages(store_id);
create index if not exists caisse_cloture_store_id_date_idx on public.caisse_cloture(store_id, date desc);

-- This helper is security definer so RLS checks cannot recurse through store_members.
create or replace function public.my_store_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select store_id from public.store_members where user_id = auth.uid();
$$;

create or replace function public.my_organization_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select organization_id from public.profiles where id = auth.uid() and organization_id is not null;
$$;

create or replace function public.create_store_for_current_user(
  store_name text,
  store_slug text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_org_id uuid;
  new_store_id uuid;
  clean_slug text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if length(trim(store_name)) < 2 then
    raise exception 'Store name is too short';
  end if;
  clean_slug := lower(regexp_replace(trim(store_slug), '[^a-z0-9-]+', '-', 'g'));
  clean_slug := trim(both '-' from clean_slug);
  if length(clean_slug) < 2 then
    raise exception 'Invalid store slug';
  end if;

  insert into public.organizations (name, slug, owner_id)
  values (trim(store_name), clean_slug, auth.uid())
  returning id into new_org_id;

  insert into public.stores (organization_id, name, slug)
  values (new_org_id, trim(store_name), clean_slug)
  returning id into new_store_id;

  insert into public.store_members (store_id, user_id, role)
  values (new_store_id, auth.uid(), 'owner');

  update public.profiles
  set organization_id = new_org_id, role = 'manager'
  where id = auth.uid();

  return new_store_id;
end;
$$;

revoke all on function public.create_store_for_current_user(text, text) from public;
grant execute on function public.create_store_for_current_user(text, text) to authenticated;

-- Tenant-scoped access. Existing role checks remain in the frontend; RLS is the boundary.
alter table public.organizations enable row level security;
alter table public.stores enable row level security;
alter table public.store_members enable row level security;
alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.points_de_vente enable row level security;
alter table public.stock enable row level security;
alter table public.sales enable row level security;
alter table public.messages enable row level security;
alter table public.caisse_cloture enable row level security;

 drop policy if exists organizations_member_access on public.organizations;
create policy organizations_member_access on public.organizations
  for all using (id in (select organization_id from public.stores where id in (select public.my_store_ids())))
  with check (owner_id = auth.uid());

 drop policy if exists stores_member_access on public.stores;
create policy stores_member_access on public.stores
  for all using (id in (select public.my_store_ids()))
  with check (id in (select public.my_store_ids()) or organization_id in (select organization_id from public.organizations where owner_id = auth.uid()));

 drop policy if exists store_members_self_or_owner on public.store_members;
create policy store_members_self_or_owner on public.store_members
  for all using (user_id = auth.uid() or store_id in (select public.my_store_ids()))
  with check (user_id = auth.uid() or store_id in (select public.my_store_ids()));

 drop policy if exists profiles_self_or_same_org on public.profiles;
create policy profiles_self_or_same_org on public.profiles
  for all using (id = auth.uid() or organization_id in (select public.my_organization_ids()))
  with check (id = auth.uid() or organization_id in (select public.my_organization_ids()));

-- The following policies isolate every operational table by store_id.
drop policy if exists products_store_access on public.products;
create policy products_store_access on public.products for all using (store_id in (select public.my_store_ids())) with check (store_id in (select public.my_store_ids()));

drop policy if exists products_public_read on public.products;
create policy products_public_read on public.products for select using (store_id in (select id from public.stores where active = true));

drop policy if exists points_store_access on public.points_de_vente;
create policy points_store_access on public.points_de_vente for all using (store_id in (select public.my_store_ids())) with check (store_id in (select public.my_store_ids()));

drop policy if exists points_public_read on public.points_de_vente;
create policy points_public_read on public.points_de_vente for select using (active = true and store_id in (select id from public.stores where active = true));

drop policy if exists stock_store_access on public.stock;
create policy stock_store_access on public.stock for all using (store_id in (select public.my_store_ids())) with check (store_id in (select public.my_store_ids()));

drop policy if exists stock_public_read on public.stock;
create policy stock_public_read on public.stock for select using (store_id in (select id from public.stores where active = true));

drop policy if exists sales_store_access on public.sales;
create policy sales_store_access on public.sales for all using (store_id in (select public.my_store_ids())) with check (store_id in (select public.my_store_ids()));

drop policy if exists messages_store_access on public.messages;
create policy messages_store_access on public.messages for all using (store_id in (select public.my_store_ids())) with check (store_id in (select public.my_store_ids()));

drop policy if exists caisse_cloture_store_access on public.caisse_cloture;
create policy caisse_cloture_store_access on public.caisse_cloture for all using (store_id in (select public.my_store_ids())) with check (store_id in (select public.my_store_ids()));

-- sale_items has no store_id by design: it inherits isolation through its parent sale.
alter table public.sale_items enable row level security;
drop policy if exists sale_items_store_access on public.sale_items;
create policy sale_items_store_access on public.sale_items
  for all using (sale_id in (select id from public.sales where store_id in (select public.my_store_ids())))
  with check (sale_id in (select id from public.sales where store_id in (select public.my_store_ids())));
