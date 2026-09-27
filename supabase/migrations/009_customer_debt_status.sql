-- Customer debt tracking and daily settlement journal.

create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  point_id uuid references public.points_de_vente(id) on delete set null,
  type text not null check (type in ('encaissement', 'apport', 'achat', 'depense', 'sortie')),
  amount numeric(12,2) not null default 0 check (amount >= 0),
  category text,
  label text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists transactions_store_id_created_at_idx on public.transactions(store_id, created_at desc);
create index if not exists transactions_point_id_created_at_idx on public.transactions(point_id, created_at desc);

alter table public.transactions enable row level security;

drop policy if exists transactions_store_access on public.transactions;
create policy transactions_store_access on public.transactions
  for all using (store_id in (select public.my_store_ids()))
  with check (store_id in (select public.my_store_ids()));

alter table public.customers add column if not exists amount numeric(12,2) not null default 0;
alter table public.customers add column if not exists status text not null default 'ouvert' check (status in ('ouvert', 'payé', 'remboursé'));

update public.customers set status = 'ouvert' where status is null or status = '';
update public.customers set amount = coalesce(amount, 0) where amount is null;

create index if not exists customers_store_id_status_idx on public.customers(store_id, status);
