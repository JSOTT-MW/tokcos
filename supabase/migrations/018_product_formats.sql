-- Formats de boissons TOK'COS : Gobelet (mini) / Gobelet (grand) / Bouteille 1,5L.
-- Chaque format est un article distinct (son propre stock et son propre prix),
-- relié aux autres formats d'une même boisson par `format_group`.
-- `cat = 'bouteille'` alimente la section « Bouteilles — Jus & Wass ».
-- À exécuter dans Supabase SQL Editor après la migration 017.

alter table public.products add column if not exists format_group text;
alter table public.products add column if not exists format text;
alter table public.products add column if not exists format_order integer not null default 0;

create index if not exists products_format_group_idx on public.products(format_group);
