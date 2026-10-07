-- TOK'COS has one workspace with multiple points of sale, not user-created shops.
-- Keep the existing store rows and tenant keys to preserve operational data and RLS.

drop function if exists public.create_store_for_current_user(text, text);
drop function if exists public.create_store_for_current_user(text, text, text);

-- Authenticated users may read and update stores they already belong to, but
-- cannot create additional stores through the client-facing API.
drop policy if exists stores_member_access on public.stores;
drop policy if exists stores_public_update on public.stores;

create policy stores_member_read on public.stores
  for select using (id in (select public.my_store_ids()));

create policy stores_member_update on public.stores
  for update
  using (id in (select public.my_store_ids()))
  with check (id in (select public.my_store_ids()));
