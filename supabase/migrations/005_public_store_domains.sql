-- Public routing helpers for custom domains and slug URLs.
alter table public.stores add constraint stores_slug_format check (slug = lower(slug) and slug ~ '^[a-z0-9]+([a-z0-9-]*[a-z0-9]+)?$');
create unique index if not exists stores_custom_domain_unique_idx on public.stores (lower(custom_domain)) where custom_domain is not null and custom_domain <> '';
