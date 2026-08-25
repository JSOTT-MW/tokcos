-- Shop management extensions for the TOK'COS SaaS foundation.

alter table public.stores add column if not exists opening_hours jsonb not null default '{}'::jsonb;
alter table public.stores add column if not exists custom_domain text;
alter table public.stores add column if not exists public_enabled boolean not null default true;

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  name text not null,
  color text,
  created_at timestamptz not null default now(),
  unique(store_id, name)
);

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  name text not null,
  phone text,
  email text,
  notes text,
  created_at timestamptz not null default now()
);

alter table public.products add column if not exists category_id uuid references public.categories(id) on delete set null;
alter table public.sales add column if not exists customer_id uuid references public.customers(id) on delete set null;

create index if not exists categories_store_id_idx on public.categories(store_id);
create index if not exists customers_store_id_idx on public.customers(store_id);
create index if not exists products_category_id_idx on public.products(category_id);
create index if not exists sales_customer_id_idx on public.sales(customer_id);

alter table public.categories enable row level security;
alter table public.customers enable row level security;

drop policy if exists categories_store_access on public.categories;
create policy categories_store_access on public.categories for all using (store_id in (select public.my_store_ids())) with check (store_id in (select public.my_store_ids()));

drop policy if exists customers_store_access on public.customers;
create policy customers_store_access on public.customers for all using (store_id in (select public.my_store_ids())) with check (store_id in (select public.my_store_ids()));

drop policy if exists stores_public_update on public.stores;
create policy stores_public_update on public.stores for update using (id in (select public.my_store_ids())) with check (id in (select public.my_store_ids()));
