-- Public storefront access for the active store.
-- Required after 001_multi_tenant_saas.sql so the anonymous storefront can resolve a store.

drop policy if exists stores_public_read on public.stores;
create policy stores_public_read on public.stores
  for select using (active = true);

drop policy if exists sales_public_insert on public.sales;
create policy sales_public_insert on public.sales
  for insert with check (
    store_id in (select id from public.stores where active = true)
    and channel = 'en_ligne'
    and status = 'vendu'
    and fulfilled = false
  );

drop policy if exists sale_items_public_insert on public.sale_items;
create policy sale_items_public_insert on public.sale_items
  for insert with check (
    sale_id in (
      select id from public.sales
      where store_id in (select id from public.stores where active = true)
        and channel = 'en_ligne'
    )
  );
