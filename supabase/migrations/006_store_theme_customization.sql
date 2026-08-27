-- Store visual identity & theme customization (façon Shopify).
alter table public.stores add column if not exists tagline text;
alter table public.stores add column if not exists banner_url text;
alter table public.stores add column if not exists theme jsonb not null default '{}'::jsonb;
