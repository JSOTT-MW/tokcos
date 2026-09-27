-- Approvisionnement requests for points de vente -> boutique flow.

create table if not exists public.approvisionnements (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  point_id uuid not null references public.points_de_vente(id) on delete cascade,
  note text,
  total numeric(12,2) not null default 0,
  status text not null default 'demande' check (status in ('demande', 'livre', 'annule')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.approvisionnement_items (
  id uuid primary key default gen_random_uuid(),
  approvisionnement_id uuid not null references public.approvisionnements(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  product_name text not null,
  qty integer not null check (qty > 0),
  cost numeric(12,2) not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists approvisionnements_store_id_idx on public.approvisionnements(store_id, created_at desc);
create index if not exists approvisionnements_point_id_idx on public.approvisionnements(point_id);
create index if not exists approvisionnement_items_approvisionnement_id_idx on public.approvisionnement_items(approvisionnement_id);
create index if not exists approvisionnement_items_product_id_idx on public.approvisionnement_items(product_id);

alter table public.approvisionnements enable row level security;
alter table public.approvisionnement_items enable row level security;

drop policy if exists approvisionnements_store_access on public.approvisionnements;
create policy approvisionnements_store_access on public.approvisionnements
  for all using (store_id in (select public.my_store_ids()))
  with check (store_id in (select public.my_store_ids()));

drop policy if exists approvisionnement_items_store_access on public.approvisionnement_items;
create policy approvisionnement_items_store_access on public.approvisionnement_items
  for all using (
    approvisionnement_id in (
      select id from public.approvisionnements where store_id in (select public.my_store_ids())
    )
  )
  with check (
    approvisionnement_id in (
      select id from public.approvisionnements where store_id in (select public.my_store_ids())
    )
  );

create or replace function public.touch_approvisionnement_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger approvisionnements_updated_at
before update on public.approvisionnements
for each row execute function public.touch_approvisionnement_updated_at();
