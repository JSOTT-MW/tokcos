-- Choix du type de site public : présentation simple ou commande en ligne.
alter table public.stores add column if not exists storefront_mode text not null default 'vitrine';
alter table public.stores drop constraint if exists stores_storefront_mode_check;
alter table public.stores add constraint stores_storefront_mode_check check (storefront_mode in ('vitrine', 'ecommerce'));

drop function if exists public.create_store_for_current_user(text, text);
create or replace function public.create_store_for_current_user(
  store_name text,
  store_slug text,
  store_mode text default 'vitrine'
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
  if store_mode not in ('vitrine', 'ecommerce') then
    raise exception 'Invalid storefront mode';
  end if;
  clean_slug := lower(regexp_replace(trim(store_slug), '[^a-z0-9-]+', '-', 'g'));
  clean_slug := trim(both '-' from clean_slug);
  if length(clean_slug) < 2 then
    raise exception 'Invalid store slug';
  end if;

  insert into public.organizations (name, slug, owner_id)
  values (trim(store_name), clean_slug, auth.uid())
  returning id into new_org_id;

  insert into public.stores (organization_id, name, slug, storefront_mode)
  values (new_org_id, trim(store_name), clean_slug, store_mode)
  returning id into new_store_id;

  insert into public.store_members (store_id, user_id, role)
  values (new_store_id, auth.uid(), 'owner');

  update public.profiles
  set organization_id = new_org_id, role = 'manager'
  where id = auth.uid();

  return new_store_id;
end;
$$;

revoke all on function public.create_store_for_current_user(text, text, text) from public;
grant execute on function public.create_store_for_current_user(text, text, text) to authenticated;
